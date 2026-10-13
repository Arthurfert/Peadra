import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sync_messages.dart';

/// Sends and receives length-prefixed JSON frames over a [Socket].
///
/// Every frame is a 4-byte big-endian length followed by the UTF-8 JSON
/// payload. Length-prefixing avoids newline ambiguity and supports large
/// changeset payloads.
class FrameCodec {
  FrameCodec(this._socket) : _iterator = StreamIterator(_socket);

  /// Upper bound for a single frame payload. Changesets can be large, but
  /// anything beyond this is a corrupt length prefix or an attack — fail
  /// fast instead of buffering unbounded RAM.
  static const int maxFrameBytes = 32 * 1024 * 1024;

  final Socket _socket;
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  /// Read cursor into [_buffer]. Bytes before it are consumed; the prefix
  /// is compacted away once it grows past [_compactionThreshold] so frame
  /// consumption stays amortized O(1) instead of an O(n) memmove per frame.
  int _offset = 0;
  static const int _compactionThreshold = 65536;
  int? _frameLength;

  Future<void> send(Map<String, dynamic> message) async {
    final payload = utf8.encode(jsonEncode(message));
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, payload.length);
    final frame = BytesBuilder(copy: false)
      ..add(header)
      ..add(payload);
    _socket.add(frame.toBytes());
    await _socket.flush();
  }

  /// Reads the next frame, or null on a clean end of stream.
  /// Throws [SyncProtocolException] if the connection ends mid-frame.
  Future<Map<String, dynamic>?> readNext() async {
    while (true) {
      if (_frameLength == null) {
        if (_available < 4) {
          if (!await _readMore()) return _eof();
          continue;
        }
        final length = (_buffer[_offset] << 24) |
            (_buffer[_offset + 1] << 16) |
            (_buffer[_offset + 2] << 8) |
            _buffer[_offset + 3];
        _consume(4);
        if (length < 0 || length > maxFrameBytes) {
          throw SyncProtocolException('Frame length out of bounds: $length');
        }
        _frameLength = length;
      }
      while (_available < _frameLength!) {
        if (!await _readMore()) return _eof();
      }
      final payload =
          Uint8List.fromList(_buffer.sublist(_offset, _offset + _frameLength!));
      _consume(_frameLength!);
      _frameLength = null;
      try {
        return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      } on FormatException {
        throw SyncProtocolException('Malformed JSON in frame');
      } on TypeError {
        throw SyncProtocolException('Frame payload is not a JSON object');
      }
    }
  }

  int get _available => _buffer.length - _offset;

  void _consume(int n) {
    _offset += n;
    if (_offset >= _compactionThreshold && _offset * 2 >= _buffer.length) {
      _buffer.removeRange(0, _offset);
      _offset = 0;
    } else if (_offset == _buffer.length) {
      // Aligned fast path: everything consumed, reset without copying.
      _buffer.clear();
      _offset = 0;
    }
  }

  Future<bool> _readMore() async {
    if (await _iterator.moveNext()) {
      _buffer.addAll(_iterator.current);
      return true;
    }
    return false;
  }

  Map<String, dynamic>? _eof() {
    if (_available == 0 && _frameLength == null) return null;
    throw SyncProtocolException('Connection closed mid-frame');
  }
}

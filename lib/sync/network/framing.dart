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

  final Socket _socket;
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];
  int? _frameLength;

  Future<void> send(Map<String, dynamic> message) async {
    final payload = utf8.encode(jsonEncode(message));
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, payload.length);
    _socket.add(header);
    _socket.add(payload);
    await _socket.flush();
  }

  /// Reads the next frame, or null on a clean end of stream.
  /// Throws [SyncProtocolException] if the connection ends mid-frame.
  Future<Map<String, dynamic>?> readNext() async {
    while (true) {
      if (_frameLength == null) {
        if (_buffer.length < 4) {
          if (!await _readMore()) return _eof();
          continue;
        }
        final length =
            ByteData.sublistView(Uint8List.fromList(_buffer.sublist(0, 4)))
                .getUint32(0);
        _buffer.removeRange(0, 4);
        _frameLength = length;
      }
      while (_buffer.length < _frameLength!) {
        if (!await _readMore()) return _eof();
      }
      final payload = _buffer.sublist(0, _frameLength!);
      _buffer.removeRange(0, _frameLength!);
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

  Future<bool> _readMore() async {
    if (await _iterator.moveNext()) {
      _buffer.addAll(_iterator.current);
      return true;
    }
    return false;
  }

  Map<String, dynamic>? _eof() {
    if (_buffer.isEmpty && _frameLength == null) return null;
    throw SyncProtocolException('Connection closed mid-frame');
  }
}

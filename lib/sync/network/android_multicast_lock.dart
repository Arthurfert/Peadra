import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Acquires the Android `WifiManager.MulticastLock` so the device keeps
/// receiving mDNS multicast packets while browsing (many devices filter them
/// in low-power mode). No-op on non-Android platforms.
class AndroidMulticastLock {
  static const MethodChannel _channel =
      MethodChannel('com.peadra.sync/multicast_lock');

  Future<void> acquire() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod('acquire');
      debugPrint('[peadra-sync] MulticastLock acquired');
    } on PlatformException catch (e) {
      // Browsing can still work without the lock on some devices.
      debugPrint('[peadra-sync] MulticastLock acquire failed: ${e.message}');
      _log(e);
    } on MissingPluginException {
      // MethodChannel not registered (e.g. during tests).
      debugPrint('[peadra-sync] MulticastLock channel missing');
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod('release');
      debugPrint('[peadra-sync] MulticastLock released');
    } on PlatformException catch (e) {
      debugPrint('[peadra-sync] MulticastLock release failed: ${e.message}');
      _log(e);
    } on MissingPluginException {
      // Ignored.
    }
  }

  void _log(PlatformException e) {
    // ignore: avoid_print
    print('MulticastLock: ${e.message}');
  }
}

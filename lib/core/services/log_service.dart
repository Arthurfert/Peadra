import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._() {
    _logStartup();
    _attachErrorHandlers();
  }

  final List<LogEntry> _entries = [];

  void _attachErrorHandlers() {
    FlutterError.onError = (details) {
      _add('ERROR', details.exceptionAsString(), details.stack?.toString());
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _add('FATAL', error.toString(), stack.toString());
      return true;
    };
  }

  Future<void> _logStartup() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _add('INFO', 'App started: ${info.appName} v${info.version}+${info.buildNumber}');
    } catch (_) {
      _add('INFO', 'App started');
    }
    _add('INFO', 'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  void log(String message) => _add('INFO', message);
  void warn(String message) => _add('WARN', message);
  void error(String message, [String? stack]) => _add('ERROR', message, stack);

  void _add(String level, String message, [String? stack]) {
    _entries.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      stack: stack,
    ));
  }

  String buildContent() {
    final buffer = StringBuffer();
    buffer.writeln('Peadra Session Log');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${_entries.length}');
    buffer.writeln('${'=' * 60}\n');

    for (final entry in _entries) {
      final time = DateFormat('HH:mm:ss').format(entry.timestamp);
      buffer.writeln('[$time] [${entry.level}] ${entry.message}');
      if (entry.stack != null) {
        buffer.writeln(entry.stack);
        buffer.writeln('');
      }
    }
    return buffer.toString();
  }

  Future<String> export({String? targetPath}) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final name = 'peadra_log_$timestamp.txt';
    final filePath = targetPath ?? '/storage/emulated/0/Download/$name';
    final file = File(filePath);
    await file.create(recursive: true);
    await file.writeAsString(buildContent());
    return filePath;
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? stack;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stack,
  });
}
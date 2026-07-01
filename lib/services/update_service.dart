import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_manager.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'] as List<dynamic>? ?? [];
    String downloadUrl = json['html_url'] ?? '';
    String? linuxDebUrl;
    String? linuxRpmUrl;
    String? linuxAppImageUrl;
    for (final asset in assets) {
      final name = asset['name'] ?? '';
      final url = asset['browser_download_url'] ?? '';
      if (Platform.isLinux) {
        if (name.contains('.deb')) linuxDebUrl = url;
        if (name.contains('.rpm')) linuxRpmUrl = url;
        if (name.contains('.AppImage')) linuxAppImageUrl = url;
      } else if (Platform.isWindows && name.contains('.exe')) {
        downloadUrl = url;
        break;
      } else if (Platform.isMacOS && name.contains('.dmg')) {
        downloadUrl = url;
        break;
      }
    }
    if (Platform.isLinux) {
      downloadUrl = linuxDebUrl ?? linuxRpmUrl ?? linuxAppImageUrl ?? downloadUrl;
    }

    return UpdateInfo(
      version: (json['tag_name'] ?? '').replaceFirst('v', ''),
      downloadUrl: downloadUrl,
      releaseNotes: json['body'] ?? '',
      publishedAt: json['published_at'] ?? '',
    );
  }
}

class UpdateService {
  final DatabaseManager _db = DatabaseManager.instance;
  static final UpdateService _instance = UpdateService._();
  factory UpdateService() => _instance;
  UpdateService._();

  static const String _repoOwner = 'anomalyco';
  static const String _repoName = 'Peadra';

  /// Check for new version on GitHub Releases.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse(
          'https://api.github.com/repos/Arthurfert/Peadra/releases/latest');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final update = UpdateInfo.fromJson(data);

      final current = await getCurrentVersion();
      if (update.version.isEmpty || current.isEmpty) return null;

      if (_isNewerVersion(update.version, current)) {
        return update;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current app version.
  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  /// Compare two semver strings. Returns true if `a` is newer than `b`.
  bool _isNewerVersion(String a, String b) {
    final aParts = a.split('.').map(int.tryParse).whereType<int>().toList();
    final bParts = b.split('.').map(int.tryParse).whereType<int>().toList();

    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }

  /// Open download URL in browser.
  Future<void> openDownloadUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_manager.dart';
import 'log_service.dart';

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
    for (final asset in assets) {
      final name = asset['name'] ?? '';
      final url = asset['browser_download_url'] ?? '';
      if (Platform.isLinux) {
        if (name.contains('.deb')) { downloadUrl = url; break; }
        if (name.contains('.rpm')) { downloadUrl = url; break; }
        if (name.contains('.AppImage')) { downloadUrl = url; break; }
      } else if (Platform.isWindows && name.contains('.msi')) {
        downloadUrl = url;
        break;
      } else if (Platform.isMacOS && name.contains('.dmg')) {
        downloadUrl = url;
        break;
      } else if (Platform.isAndroid && name.endsWith('.apk')) {
        downloadUrl = url;
        break;
      }
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

      LogService().log('Update check: HTTP ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>? ?? [];
      LogService().log('Update check: ${assets.length} asset(s), tag=${data['tag_name']}');
      for (final a in assets) {
        LogService().log('  Asset: ${a['name']}');
      }

      final update = UpdateInfo.fromJson(data);
      LogService().log('Update check: parsed version="${update.version}", downloadUrl=${update.downloadUrl}');

      final current = await getCurrentVersion();
      LogService().log('Update check: current="$current"');
      if (update.version.isEmpty || current.isEmpty) return null;

      final isNewer = _isNewerVersion(update.version, current);
      LogService().log('Update check: isNewer=$isNewer');
      if (isNewer) {
        return update;
      }
      return null;
    } catch (e) {
      LogService().warn('Update check failed: $e');
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
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

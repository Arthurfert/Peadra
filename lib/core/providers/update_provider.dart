import 'package:flutter/foundation.dart';

import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _availableUpdate;
  bool _checked = false;

  UpdateInfo? get availableUpdate => _availableUpdate;
  bool get checked => _checked;

  /// Checks once per session by default; pass [force] for manual re-checks
  /// (e.g. the settings "check for updates" button).
  Future<void> checkForUpdate({bool force = false}) async {
    if (_checked && !force) return;
    final update = await UpdateService().checkForUpdate();
    _checked = true;
    if (update != null) {
      _availableUpdate = update;
    }
    notifyListeners();
  }
}

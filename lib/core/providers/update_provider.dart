import 'package:flutter/foundation.dart';

import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _availableUpdate;
  bool _checked = false;

  UpdateInfo? get availableUpdate => _availableUpdate;
  bool get checked => _checked;

  Future<void> checkForUpdate() async {
    final update = await UpdateService().checkForUpdate();
    _checked = true;
    if (update != null) {
      _availableUpdate = update;
      notifyListeners();
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/providers/settings_provider.dart';
import 'package:peadra/core/utils/constants.dart';
import 'package:peadra/core/utils/nav_views.dart';
import '../helpers/test_helper.dart';

void main() {
  group('SettingsProvider mobile navigation order', () {
    test('defaults to the default navigation order', () {
      expect(SettingsProvider().navOrder, defaultNavOrder);
    });

    test('the getter returns an unmodifiable copy', () {
      final order = SettingsProvider().navOrder;
      expect(() => order.clear(), throwsUnsupportedError);
    });

    test('an incomplete order is rejected and the current one is kept', () async {
      final settings = SettingsProvider();
      // Invalid orders are refused before any database access, so the
      // instance can be passed as-is here.
      await expectLater(
        settings.setNavOrder(['dashboard'], DatabaseManager.instance),
        completion(isFalse),
      );
      expect(settings.navOrder, defaultNavOrder);

      await expectLater(
        settings.setNavOrder(['dashboard', 'dashboard', 'nope'],
            DatabaseManager.instance),
        completion(isFalse),
      );
      expect(settings.navOrder, defaultNavOrder);
    });
  });

  group('SettingsProvider work-hours equivalent', () {
    test('toggle and hourly rate persist across a reload', () async {
      initializeTestDatabase();
      final dm = DatabaseManager.instance;
      await dm.openInMemoryForTest(userId: 'user-work-hours');

      final settings = SettingsProvider();
      expect(settings.showWorkHours, defaultShowWorkHours);
      expect(settings.hourlyRate, defaultHourlyRate);

      await settings.setShowWorkHours(true, dm);
      await settings.setHourlyRate(17.5, dm);
      expect(settings.showWorkHours, isTrue);
      expect(settings.hourlyRate, 17.5);

      final reloaded = SettingsProvider();
      await reloaded.loadFromSettings(dm);
      expect(reloaded.showWorkHours, isTrue);
      expect(reloaded.hourlyRate, 17.5);
    });
  });
}

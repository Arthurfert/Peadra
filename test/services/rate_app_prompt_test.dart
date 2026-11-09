import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/features/dashboard/presentation/widgets/rate_app_prompt.dart';

void main() {
  group('isRatePromptDue', () {
    final now = DateTime(2026, 3, 15);

    test('is due when never rated and never shown', () {
      expect(isRatePromptDue(rated: false, now: now), true);
    });

    test('is not due when already rated, even if never shown', () {
      expect(isRatePromptDue(rated: true, now: now), false);
    });

    test('is not due within 30 days of the last appearance', () {
      expect(
        isRatePromptDue(
          rated: false,
          lastShown: now.subtract(const Duration(days: 29)),
          now: now,
        ),
        false,
      );
    });

    test('is due again 30 days after the last appearance', () {
      expect(
        isRatePromptDue(
          rated: false,
          lastShown: now.subtract(const Duration(days: 30)),
          now: now,
        ),
        true,
      );
    });
  });
}

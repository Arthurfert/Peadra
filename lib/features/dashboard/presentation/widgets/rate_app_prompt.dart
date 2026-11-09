import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/database_manager.dart';
import '../../../../core/i18n/translator.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/responsive/responsive_layout.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/theme/peadra_colors.dart';
import '../../../../shared/widgets/peadra_modal.dart';

/// Shows the "Rate Peadra" prompt on phones right after login: every 30 days
/// until the user taps the stars, never again after that. The stars button
/// opens the Play Store listing; tapping it counts as a rating.
///
/// State lives in the per-user settings table: `app_rated` blocks the prompt
/// forever, `rate_prompt_last_shown` paces the monthly reappearance.
Future<void> maybeShowRateAppPrompt(BuildContext context) async {
  // The Play Store listing is Android-only: a narrow desktop window would
  // also count as a "phone" layout, and iOS must not get a Play Store link.
  if (!Platform.isAndroid || !ResponsiveLayout.isPhone(context)) return;
  final db = DatabaseManager.instance;
  if (db.userId == null) return;

  final lastShown = DateTime.tryParse(
      await db.getSetting('rate_prompt_last_shown') ?? '');
  final due = isRatePromptDue(
    rated: await db.getSetting('app_rated') == 'true',
    lastShown: lastShown,
  );
  if (!due) return;

  final now = DateTime.now();

  // Recorded when shown (not when dismissed) so killing the app while the
  // prompt is open does not resurface it before the next month.
  await db.setSetting('rate_prompt_last_shown', now.toIso8601String());
  if (!context.mounted) return;

  final colors = PeadraTheme.getColors(context.read<ThemeProvider>().themeName);
  final onAccent = colors.accent.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;

  await showPeadraModal(
    context: context,
    builder: (ctx) => PeadraModal(
      title: Text(
        Translator.t('rate_title'),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translator.t('rate_body'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Semantics(
            button: true,
            label: Translator.t('rate_cta'),
            child: Material(
              color: colors.accent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _rate(db);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(Icons.star_rounded, size: 32, color: onAccent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(Translator.t('rate_later')),
        ),
      ],
    ),
  );
}

Future<void> _rate(DatabaseManager db) async {
  await db.setSetting('app_rated', 'true');
  await UpdateService().openPlayStore();
}

/// Whether the rating prompt is due: the user has not rated yet and the
/// prompt has not been shown within the last 30 days.
bool isRatePromptDue({required bool rated, DateTime? lastShown, DateTime? now}) {
  if (rated) return false;
  final reference = now ?? DateTime.now();
  return lastShown == null ||
      reference.difference(lastShown).inDays >= 30;
}

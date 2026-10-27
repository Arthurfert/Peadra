import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:peadra/core/i18n/translator.dart';
import 'package:peadra/core/providers/theme_provider.dart';
import 'package:peadra/shared/widgets/peadra_modal.dart';

/// Regression test: [showPeadraModal] must accept builders returning a
/// stateful wrapper around [PeadraModal] (e.g. CustomRangeDialog), on both
/// phones (bottom sheet) and larger screens (dialog).
class _WrapperDialog extends StatefulWidget {
  const _WrapperDialog();

  @override
  State<_WrapperDialog> createState() => _WrapperDialogState();
}

class _WrapperDialogState extends State<_WrapperDialog> {
  @override
  Widget build(BuildContext context) {
    return PeadraModal(
      title: const Text('Wrapper title'),
      content: const Text('Wrapper content'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return PeadraModal(
      title: const Text('Confirm title'),
      content: const Text('Confirm content'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(Translator.t('btn_cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Widget _buildApp({Widget dialog = const _WrapperDialog()}) {
  return ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPeadraModal<bool>(
              context: context,
              builder: (_) => dialog,
            ),
            child: const Text('SHOW'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _setLogicalSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
}

/// Simulates a phone with a status bar at the top and a system navigation
/// bar at the bottom (3-button navigation), plus an optional keyboard.
void _setSystemInsets(
  WidgetTester tester, {
  double top = 24,
  double bottom = 48,
  double keyboard = 0,
}) {
  tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
}

void main() {
  group('showPeadraModal', () {
    testWidgets('phone: stateful wrapper renders as bottom sheet',
        (tester) async {
      await _setLogicalSize(tester, const Size(400, 800));
      await tester.pumpWidget(_buildApp());

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      expect(find.text('Wrapper title'), findsOneWidget);
      expect(find.text('Wrapper content'), findsOneWidget);
      // Secondary actions render outlined in sheets.
      expect(find.byType(OutlinedButton), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Wrapper content'), findsNothing);
    });

    testWidgets('desktop: stateful wrapper renders as dialog',
        (tester) async {
      await _setLogicalSize(tester, const Size(1200, 800));
      await tester.pumpWidget(_buildApp());

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      expect(find.text('Wrapper title'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Desktop dialogs keep standard text buttons.
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Wrapper content'), findsNothing);
    });

    testWidgets('phone: cancel action is dropped from sheets',
        (tester) async {
      await _setLogicalSize(tester, const Size(400, 800));
      await tester.pumpWidget(_buildApp(dialog: const _ConfirmDialog()));

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm content'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text(Translator.t('btn_cancel')), findsNothing);
    });

    testWidgets('desktop: cancel action is kept in dialogs',
        (tester) async {
      await _setLogicalSize(tester, const Size(1200, 800));
      await tester.pumpWidget(_buildApp(dialog: const _ConfirmDialog()));

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
      expect(find.text(Translator.t('btn_cancel')), findsOneWidget);
    });

    testWidgets('phone: sheet content stays above the system bar',
        (tester) async {
      await _setLogicalSize(tester, const Size(400, 800));
      _setSystemInsets(tester);
      await tester.pumpWidget(_buildApp(dialog: const _ConfirmDialog()));

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      // The bottom system bar starts 48px above the bottom of the screen;
      // content may dip up to 8px into the bar's dead top edge, so it must
      // stay at or above 800 - 48 + 8.
      const contentFloor = 800 - 48 + 8;
      expect(
        tester.getRect(find.text('Confirm content')).bottom,
        lessThanOrEqualTo(contentFloor),
      );
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Save')).bottom,
        lessThanOrEqualTo(contentFloor),
      );
    });

    testWidgets('phone: sheet content stays above the keyboard',
        (tester) async {
      await _setLogicalSize(tester, const Size(400, 800));
      _setSystemInsets(tester, keyboard: 300);
      await tester.pumpWidget(_buildApp(dialog: const _ConfirmDialog()));

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      const keyboardTop = 800 - 300;
      expect(
        tester.getRect(find.text('Confirm content')).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Save')).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
    });

    testWidgets('phone: tall sheet stops below the status bar',
        (tester) async {
      await _setLogicalSize(tester, const Size(400, 800));
      _setSystemInsets(tester);
      await tester.pumpWidget(_buildApp(
        dialog: PeadraModal(
          title: const Text('Tall title'),
          content: const SizedBox(height: 1200, child: Text('Tall content')),
          actions: const [],
        ),
      ));

      await tester.tap(find.text('SHOW'));
      await tester.pumpAndSettle();

      // The sheet must not slide under the 24px status bar.
      expect(tester.getRect(find.byType(PeadraModal)).top,
          greaterThanOrEqualTo(24));
      expect(
        tester.getRect(find.text('Tall title')).top,
        greaterThanOrEqualTo(24),
      );
    });
  });
}

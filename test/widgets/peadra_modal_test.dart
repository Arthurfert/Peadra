import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

Widget _buildApp() {
  return ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPeadraModal<bool>(
              context: context,
              builder: (_) => const _WrapperDialog(),
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
  });
}

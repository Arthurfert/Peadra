import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/shared/widgets/peadra_notification.dart';

Widget buildApp() {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {},
          child: const Text('SHOW'),
        ),
      ),
    ),
  );
}

void main() {
  group('PeadraNotification', () {
    testWidgets('shows success notification with message and check icon',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(context, message: 'Transaction added');
      await tester.pump();

      expect(find.text('Transaction added'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('shows error notification with error icon', (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(
        context,
        message: 'Something went wrong',
        type: NotificationType.error,
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('shows warning notification with warning icon',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(
        context,
        message: 'Warning message',
        type: NotificationType.warning,
      );
      await tester.pump();

      expect(find.text('Warning message'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('shows info notification with info icon', (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(
        context,
        message: 'Info message',
        type: NotificationType.info,
      );
      await tester.pump();

      expect(find.text('Info message'), findsOneWidget);
      expect(find.byIcon(Icons.info), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('auto-dismisses after 4 seconds', (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(context, message: 'Temporary notification');
      await tester.pump();

      expect(find.text('Temporary notification'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Temporary notification'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Temporary notification'), findsNothing);
    });

    testWidgets('stacks notifications vertically', (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(context, message: 'First');
      await tester.pump();
      PeadraNotification.show(context, message: 'Second');
      await tester.pump();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      // Both use Positioned widgets in the overlay
      expect(find.byType(Positioned), findsAtLeast(2));

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('remaining notification moves down when one dismisses',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      // Show first notification and wait 3 seconds
      PeadraNotification.show(context, message: 'Bottom');
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      // Show second notification (Bottom has 1 second left, Top has 4 seconds)
      PeadraNotification.show(context, message: 'Top');
      await tester.pump();

      expect(find.text('Bottom'), findsOneWidget);
      expect(find.text('Top'), findsOneWidget);

      // Pump past Bottom's dismissal
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));

      // Bottom should have dismissed, Top should still be visible
      expect(find.text('Bottom'), findsNothing);
      expect(find.text('Top'), findsOneWidget);

      // Let Top's timer complete before test ends
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Top'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/components/notification/peadra_notification.dart';

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

Future<void> showNotification(
  WidgetTester tester, {
  required String message,
  NotificationType type = NotificationType.success,
}) async {
  await tester.tap(find.text('SHOW'));
  // Need to find the context of the button to show notification
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

    testWidgets('shows multiple notifications simultaneously',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final context = tester.element(find.text('SHOW'));
      PeadraNotification.show(context, message: 'First notification');
      await tester.pump();
      expect(find.text('First notification'), findsOneWidget);

      PeadraNotification.show(
        context,
        message: 'Second notification',
        type: NotificationType.error,
      );
      await tester.pump();

      expect(find.text('First notification'), findsOneWidget);
      expect(find.text('Second notification'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}

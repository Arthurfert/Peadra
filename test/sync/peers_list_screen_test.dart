import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:peadra/core/i18n/translator.dart';
import 'package:peadra/core/providers/theme_provider.dart';
import 'package:peadra/features/sync/presentation/peers_list_screen.dart';
import 'package:peadra/sync/models/trusted_peer.dart';

TrustedPeer peer({
  String id = 'peer-1',
  String name = 'Phone',
  DateTime? lastSeen,
}) =>
    TrustedPeer(
      peerId: id,
      deviceName: name,
      sharedSecret: 'secret',
      createdAt: DateTime.utc(2024, 1, 1),
      lastSeen: lastSeen,
    );

Widget wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(home: child),
    );

Future<void> drainNotifications(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Translator.setLanguage('en'));

  testWidgets('shows the empty state when there are no peers',
      (tester) async {
    await tester.pumpWidget(
        wrap(PeersListScreen(loadPeers: () async => [])));
    await tester.pumpAndSettle();

    expect(find.text(Translator.t('sync_peers_empty')), findsOneWidget);
  });

  testWidgets('lists peers and triggers a manual sync', (tester) async {
    final synced = <String>[];
    await tester.pumpWidget(wrap(PeersListScreen(
      loadPeers: () async => [peer()],
      syncPeer: (id) async => synced.add(id),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Phone'), findsOneWidget);
    expect(find.text(Translator.t('sync_never_synced')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();

    expect(synced, ['peer-1']);
    await drainNotifications(tester);
  });

  testWidgets('forgetting a peer asks for confirmation then removes it',
      (tester) async {
    var peers = [peer()];
    final forgotten = <String>[];
    await tester.pumpWidget(wrap(PeersListScreen(
      loadPeers: () async => peers,
      forgetPeer: (id) async {
        peers = [];
        forgotten.add(id);
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(
      find.text(Translator.t('sync_forget_confirm', params: {'name': 'Phone'})),
      findsOneWidget,
    );

    await tester.tap(find.text(Translator.t('sync_forget')).last);
    await tester.pumpAndSettle();

    expect(forgotten, ['peer-1']);
    expect(find.text(Translator.t('sync_peers_empty')), findsOneWidget);
    await drainNotifications(tester);
  });

  testWidgets('shows the last-seen time when available', (tester) async {
    final seen = DateTime.utc(2026, 8, 3, 14, 30);
    await tester.pumpWidget(wrap(PeersListScreen(
      loadPeers: () async => [peer(lastSeen: seen)],
    )));
    await tester.pumpAndSettle();

    final expected = Translator.t('sync_last_seen', params: {
      'time': DateFormat('d MMM yyyy, HH:mm').format(seen.toLocal()),
    });
    expect(find.text(expected), findsOneWidget);
  });
}

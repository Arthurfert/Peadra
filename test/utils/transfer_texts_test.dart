import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/utils/transfer_texts.dart';

const _template = 'Transfer from {source} to {dest}';

void main() {
  group('parseTransferText', () {
    test('parses "Transfer to X"', () {
      expect(parseTransferText('Transfer to Savings'),
          (isTo: true, name: 'Savings'));
    });

    test('parses "Transfer from X"', () {
      expect(parseTransferText('Transfer from Checking'),
          (isTo: false, name: 'Checking'));
    });

    test('is case-insensitive', () {
      expect(parseTransferText('transfer to savings')?.isTo, isTrue);
      expect(parseTransferText('TRANSFER FROM X')?.name, 'X');
    });

    test('returns null for ordinary descriptions', () {
      expect(parseTransferText('Coffee'), isNull);
      expect(parseTransferText('Transfer'), isNull);
      expect(parseTransferText(null), isNull);
      expect(parseTransferText('  '), isNull);
    });

    test('isTransferText matches only transfer legs', () {
      expect(isTransferText('Transfer to A'), isTrue);
      expect(isTransferText('Transfer from A'), isTrue);
      expect(isTransferText('Groceries'), isFalse);
    });
  });

  group('transferEndsForSingle (orphaned halves)', () {
    test('source leg on live account resolves both ends', () {
      expect(
        transferEndsForSingle(
            ownAccountName: 'Checking', text: 'Transfer to Savings'),
        (source: 'Checking', dest: 'Savings'),
      );
    });

    test('dest leg on live account resolves both ends', () {
      expect(
        transferEndsForSingle(
            ownAccountName: 'Savings', text: 'Transfer from Checking'),
        (source: 'Checking', dest: 'Savings'),
      );
    });

    test('leg on deleted (NULL) account keeps the parsed counterpart', () {
      // Source account deleted: dest leg survived on a live account.
      expect(
        transferEndsForSingle(
            ownAccountName: null, text: 'Transfer from Checking'),
        (source: 'Checking', dest: null),
      );
      // Dest account deleted: source leg survived on a live account.
      expect(
        transferEndsForSingle(
            ownAccountName: null, text: 'Transfer to Savings'),
        (source: null, dest: 'Savings'),
      );
    });

    test('non-transfer text resolves to (null, null)', () {
      expect(
        transferEndsForSingle(ownAccountName: 'A', text: 'Coffee'),
        (source: null, dest: null),
      );
    });
  });

  group('transferEndsForPair (deleted account on either side)', () {
    test('both accounts live uses live names', () {
      expect(
        transferEndsForPair(
          sourceAccountName: 'Checking',
          destAccountName: 'Savings',
          sourceLegText: 'Transfer to Savings',
          destLegText: 'Transfer from Checking',
        ),
        (source: 'Checking', dest: 'Savings'),
      );
    });

    test('deleted source account recovers name from dest leg text', () {
      expect(
        transferEndsForPair(
          sourceAccountName: null,
          destAccountName: 'Savings',
          sourceLegText: 'Transfer to Savings',
          destLegText: 'Transfer from Checking',
        ),
        (source: 'Checking', dest: 'Savings'),
      );
    });

    test('deleted dest account recovers name from source leg text', () {
      expect(
        transferEndsForPair(
          sourceAccountName: 'Checking',
          destAccountName: null,
          sourceLegText: 'Transfer to Savings',
          destLegText: 'Transfer from Checking',
        ),
        (source: 'Checking', dest: 'Savings'),
      );
    });
  });

  group('transferTitle', () {
    test('builds "Transfer from A to B" when both ends known', () {
      expect(
        transferTitle(
            source: 'Checking',
            dest: 'Savings',
            template: _template,
            fallback: 'Transfer to Savings'),
        'Transfer from Checking to Savings',
      );
    });

    test('falls back to raw description when an end is unknown', () {
      expect(
        transferTitle(
            source: null,
            dest: 'Savings',
            template: _template,
            fallback: 'Transfer to Savings'),
        'Transfer to Savings',
      );
      expect(
        transferTitle(
            source: 'Checking',
            dest: null,
            template: _template,
            fallback: 'Transfer from Checking'),
        'Transfer from Checking',
      );
    });

    test('non-transfer transactions keep their description', () {
      expect(
        transferTitle(
            source: null,
            dest: null,
            template: _template,
            fallback: 'Coffee'),
        'Coffee',
      );
    });
  });
}

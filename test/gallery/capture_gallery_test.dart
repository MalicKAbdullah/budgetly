import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/features/capture/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';
import 'gallery_support.dart';

/// The fixture plus a bill Ali covered for the owner, so a payment out to Ali
/// can settle a balance.
AppData _owingAli() {
  final base = galleryData();
  return base.copyWith(
    txns: [
      ...base.txns,
      Txn(
        id: 'ali-covered',
        type: TxnType.expense,
        amountMinor: 1800000,
        payableMinor: 900000,
        date: DateTime.now().subtract(const Duration(days: 8)),
        accountId: 'card',
        categoryId: 'dining',
        counterparty: 'Ali Raza',
        note: 'Concert tickets',
        createdAt: DateTime(2025),
      ),
    ],
  );
}

/// Opens the review sheet for the Ali Raza alert in both panes: the inbox
/// lists newest first, so it is the second Review button in each pane.
Future<void> _openAliReview(WidgetTester tester) async {
  final review = find.widgetWithText(FilledButton, 'Review');
  await tester.tap(review.at(1));
  await tester.pumpAndSettle();
  await tester.tap(review.at(3), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('capture inbox', (tester) async {
    await renderScreen(
      tester,
      'capture',
      () => const CaptureScreen(),
      data: galleryData(),
      height: 1100,
    );
  }, skip: galleryOut == null);

  testWidgets('review sheet — settles a balance', (tester) async {
    await renderScreen(
      tester,
      'review-sheet',
      () => const CaptureScreen(),
      data: _owingAli(),
      height: 1700,
      interact: (tester) async {
        await _openAliReview(tester);
        for (final f in find.text('Ali Raza').evaluate().toList()) {
          await tester.tap(find.byWidget(f.widget), warnIfMissed: false);
        }
      },
    );
  }, skip: galleryOut == null);

  testWidgets('review sheet — split', (tester) async {
    await renderScreen(
      tester,
      'review-sheet-split',
      () => const CaptureScreen(),
      data: galleryData(),
      height: 1900,
      interact: (tester) async {
        await _openAliReview(tester);
        final toggle = find.text('Split this payment');
        for (var i = 0; i < toggle.evaluate().length; i++) {
          await tester.tap(toggle.at(i), warnIfMissed: false);
          await tester.pumpAndSettle();
        }
      },
    );
  }, skip: galleryOut == null);
}

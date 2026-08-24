import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/features/capture/sms_parser.dart';
import 'package:budgetly/src/features/capture/transfer_hint.dart';

void main() {
  TxnCandidate? parse(String body) =>
      SmsParser.parse(sender: '8079', body: body);

  group('suggestsTransfer', () {
    test('withdrawal wording suggests a transfer', () {
      expect(
        CaptureModeHint.suggestsTransfer(
          'PKR 20,000.00 has been withdrawn from your A/C xxx8463',
        ),
        isTrue,
      );
      expect(
        CaptureModeHint.suggestsTransfer('Cash withdrawal of Rs 5000 at ATM'),
        isTrue,
      );
      expect(CaptureModeHint.suggestsTransfer('ATM debit PKR 3,000'), isTrue);
    });

    test('an ordinary purchase does not', () {
      expect(
        CaptureModeHint.suggestsTransfer(
          'PKR 1,250.00 has been debited at CHECKOUT MART on 21-Jul-2026',
        ),
        isFalse,
      );
      expect(
        CaptureModeHint.suggestsTransfer('PKR 5,000.00 sent to OSAMA SALEEM'),
        isFalse,
      );
    });

    test('is case-insensitive and whole-word', () {
      expect(CaptureModeHint.suggestsTransfer('WITHDRAWN PKR 100'), isTrue);
      expect(CaptureModeHint.suggestsTransfer('WiThDrAwAl'), isTrue);
      // "atm" inside another word is not an ATM.
      expect(
        CaptureModeHint.suggestsTransfer('Payment to BATMAN STORE'),
        isFalse,
      );
    });

    test('unreadable or empty text does not crash', () {
      expect(CaptureModeHint.suggestsTransfer(null), isFalse);
      expect(CaptureModeHint.suggestsTransfer(''), isFalse);
      expect(CaptureModeHint.suggestsTransfer('####  ???'), isFalse);
    });
  });

  group('suggest', () {
    test('a withdrawal opens on Transfer', () {
      const raw =
          'PKR 20,000.00 has been withdrawn at ATM on 20-Aug-2026 at 13:36';
      expect(
        CaptureModeHint.suggest(rawText: raw, parsed: parse(raw)),
        CaptureMode.transfer,
      );
    });

    test('a credit opens on Income', () {
      const raw = 'PKR 990.00 received from IMRAN to your AC# 8463';
      expect(
        CaptureModeHint.suggest(rawText: raw, parsed: parse(raw)),
        CaptureMode.income,
      );
    });

    test('a debit opens on Expense', () {
      const raw = 'PKR 5,000.00 sent to OSAMA SALEEM from your A/C xxx8463';
      expect(
        CaptureModeHint.suggest(rawText: raw, parsed: parse(raw)),
        CaptureMode.expense,
      );
    });

    test('an unparseable alert still opens on Expense', () {
      const raw = 'Your card was used somewhere, no amount here';
      expect(parse(raw), isNull);
      expect(
        CaptureModeHint.suggest(rawText: raw, parsed: null),
        CaptureMode.expense,
      );
    });

    test('the mode maps to the transaction type it records', () {
      expect(CaptureMode.transfer.txnType, TxnType.transfer);
      expect(CaptureMode.income.txnType, TxnType.income);
      expect(CaptureMode.expense.txnType, TxnType.expense);
    });
  });
}

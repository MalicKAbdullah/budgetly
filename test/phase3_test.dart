import 'package:flutter_test/flutter_test.dart';
import 'package:tally/src/features/import/sms_parser.dart';

void main() {
  group('SmsParser — Meezan (8079) real formats', () {
    test('sent to (with account in parens) → debit', () {
      final c = SmsParser.parse(
        sender: '8079',
        body:
            'PKR 5,000.00 sent to OSAMA SALEEM  (MBL AC from your A/C '
            'xxx8463 of MEEZAN BANK LIMITED on 21-Jul-2026 at 13:36 TID:633782',
      );
      expect(c, isNotNull);
      expect(c!.direction, TxnDirection.debit);
      expect(c.amountMinor, 500000);
      expect(c.merchant, 'OSAMA SALEEM');
      expect(c.when, DateTime(2026, 7, 21, 13, 36));
    });

    test('sent as RAAST (name then IBAN) → debit, name only', () {
      final c = SmsParser.parse(
        sender: '8079',
        body:
            'PKR 210.00 sent to M.ABDULLAH PK33JHMAx163 as RAAST payment '
            'from your AC# xxx8463 of MEEZAN BANK LIMITED on 21-Jul-2026 '
            'at 08:54 TID:130350.',
      );
      expect(c!.direction, TxnDirection.debit);
      expect(c.amountMinor, 21000);
      expect(c.merchant, 'M.ABDULLAH');
    });

    test('received from (RAAST, name then AC#) → credit', () {
      final c = SmsParser.parse(
        sender: '8079',
        body:
            'PKR 20,000.00 received from M.MUHAMMAD AC# xxxPYMT PK82SCBL00000 '
            'as RAAST payment to your AC# 0110868463 of MEEZAN BANK LIMITED '
            'on 11-Jul-2026 at 20:38',
      );
      expect(c!.direction, TxnDirection.credit);
      expect(c.amountMinor, 2000000);
      expect(c.merchant, 'M.MUHAMMAD');
      expect(c.when, DateTime(2026, 7, 11, 20, 38));
    });

    test('received from (name in parens) → credit', () {
      final c = SmsParser.parse(
        sender: '8079',
        body:
            'PKR 990.00 received from IMRAN JAVED (MBL AC xxx5665) to your '
            'A/C xxx8463 on 12-Jul-2026 at 00:45',
      );
      expect(c!.direction, TxnDirection.credit);
      expect(c.amountMinor, 99000);
      expect(c.merchant, 'IMRAN JAVED');
    });

    test('plain "has been debited" (card/ATM) → debit, no counterparty', () {
      final c = SmsParser.parse(
        sender: '8079',
        body:
            'PKR 45,000.00 has been debited at 18:39 on 19-Jul-2026 '
            'TID:092620, If you have not done this transaction, please inform '
            'us at 021111331331',
      );
      expect(c!.direction, TxnDirection.debit);
      expect(c.amountMinor, 4500000);
      expect(c.merchant, isNull);
    });

    test('ignores OTP and balance-only messages', () {
      expect(
        SmsParser.parse(
          sender: '8079',
          body: 'Your one-time password is 449213. Do not share it.',
        ),
        isNull,
      );
      expect(
        SmsParser.parse(
          sender: '8079',
          body: 'Your available balance is PKR 84,000.',
        ),
        isNull,
      );
    });
  });
}

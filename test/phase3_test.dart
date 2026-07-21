import 'package:flutter_test/flutter_test.dart';
import 'package:tally/src/features/import/sms_parser.dart';

void main() {
  group('SmsParser', () {
    test('parses a debit SMS into an expense candidate', () {
      final c = SmsParser.parse(
        sender: 'Meezan',
        body:
            'Your account 1234 has been debited PKR 2,400.00 at FOODPANDA on 21-Jul.',
      );
      expect(c, isNotNull);
      expect(c!.direction, TxnDirection.debit);
      expect(c.amountMinor, 240000);
      expect(c.merchant, contains('FOODPANDA'));
    });

    test('parses a credit SMS into an income candidate', () {
      final c = SmsParser.parse(
        sender: 'Meezan',
        body: 'PKR 50,000 has been credited to your account. Salary.',
      );
      expect(c, isNotNull);
      expect(c!.direction, TxnDirection.credit);
      expect(c.amountMinor, 5000000);
    });

    test('parses a wallet "sent" notification as debit', () {
      final c = SmsParser.parse(
        sender: 'JazzCash',
        body: 'You have sent Rs 1,500 to Ali Raza. Ref 998.',
      );
      expect(c!.direction, TxnDirection.debit);
      expect(c.amountMinor, 150000);
    });

    test('ignores an OTP message', () {
      final c = SmsParser.parse(
        sender: 'Bank',
        body: 'Your one-time password is 449213. Do not share it.',
      );
      expect(c, isNull);
    });

    test('ignores a balance-only alert (no direction)', () {
      final c = SmsParser.parse(
        sender: 'Bank',
        body: 'Your available balance is PKR 84,000.',
      );
      expect(c, isNull);
    });
  });
}

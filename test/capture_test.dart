import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/captures.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';

void main() {
  final now = DateTime(2026, 8, 7, 10, 30);

  group('CapturedNotice JSON', () {
    test('round-trips a pending notice', () {
      final notice = CapturedNotice(
        id: 'n1',
        rawText: 'PKR 210.00 sent to M.ABDULLAH',
        capturedAt: now,
      );
      final back = CapturedNotice.fromJson(
        jsonDecode(jsonEncode(notice.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, 'n1');
      expect(back.rawText, notice.rawText);
      expect(back.capturedAt, now);
      expect(back.status, CaptureStatus.pending);
      expect(back.txnId, isNull);
    });

    test('round-trips an added notice with its txnId', () {
      final notice = CapturedNotice(
        id: 'n2',
        rawText: 'PKR 500 has been debited',
        capturedAt: now,
        status: CaptureStatus.added,
        txnId: 't9',
      );
      final back = CapturedNotice.fromJson(
        jsonDecode(jsonEncode(notice.toJson())) as Map<String, dynamic>,
      );
      expect(back.status, CaptureStatus.added);
      expect(back.txnId, 't9');
    });

    test('an unknown status reads back as pending', () {
      final back = CapturedNotice.fromJson({
        'id': 'n3',
        'rawText': 'x',
        'capturedAt': now.toIso8601String(),
        'status': 'archived-in-some-future-version',
      });
      expect(back.status, CaptureStatus.pending);
    });
  });

  group('AppData migration', () {
    // A vault written by v0.9.x — no capturedNotices key at all.
    const oldVaultJson = '''
{
  "schemaVersion": 2,
  "currencyCode": "PKR",
  "accounts": [
    {"id":"cash","name":"Cash","type":"cash","openingBalanceMinor":10000,
     "archived":false,"createdAt":"2026-01-01T00:00:00.000"}
  ],
  "categories": [
    {"id":"groc","name":"Groceries","monthlyBudgetMinor":50000,
     "createdAt":"2026-01-01T00:00:00.000"}
  ],
  "txns": [
    {"id":"t1","type":"expense","amountMinor":2500,
     "date":"2026-07-04T00:00:00.000","accountId":"cash","categoryId":"groc",
     "note":"Milk","reimbursableMinor":0,
     "createdAt":"2026-07-04T00:00:00.000"}
  ],
  "recurringTemplates": []
}''';

    test('an old vault without capturedNotices loads intact', () {
      final data = AppData.fromJson(
        jsonDecode(oldVaultJson) as Map<String, dynamic>,
      );
      expect(data.currencyCode, 'PKR');
      expect(data.accounts.single.id, 'cash');
      expect(data.categories.single.name, 'Groceries');
      expect(data.txns.single.note, 'Milk');
      expect(data.capturedNotices, isEmpty);
      expect(data.pendingNotices, isEmpty);
    });

    test('re-saving an old vault writes the new field and the new version', () {
      final data = AppData.fromJson(
        jsonDecode(oldVaultJson) as Map<String, dynamic>,
      );
      final json = data.toJson();
      expect(json['schemaVersion'], AppData.schemaVersion);
      expect(json['capturedNotices'], isEmpty);
      // And the rewritten vault still reads back with all the old data.
      final again = AppData.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(again.txns.single.amountMinor, 2500);
    });

    test('a vault with notices round-trips them', () {
      final data = AppData(
        capturedNotices: [
          CapturedNotice(id: 'n1', rawText: 'PKR 1 sent to A', capturedAt: now),
        ],
      );
      final back = AppData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
      );
      expect(back.capturedNotices.single.rawText, 'PKR 1 sent to A');
    });
  });

  group('CaptureIngest.merge', () {
    var counter = 0;
    String nextId() => 'id${++counter}';

    setUp(() => counter = 0);

    test('turns drained text into pending notices', () {
      final merged = CaptureIngest.merge(
        existing: const [],
        rawTexts: const ['PKR 100 sent to A', 'PKR 200 received from B'],
        now: now,
        newId: nextId,
      );
      expect(merged.length, 2);
      expect(merged.every((n) => n.isPending), isTrue);
      expect(merged.first.capturedAt, now);
    });

    test('never queues the same raw text twice', () {
      final first = CaptureIngest.merge(
        existing: const [],
        rawTexts: const ['PKR 100 sent to A'],
        now: now,
        newId: nextId,
      );
      final second = CaptureIngest.merge(
        existing: first,
        rawTexts: const ['PKR 100 sent to A', '  PKR 100 sent to A  '],
        now: now,
        newId: nextId,
      );
      expect(second.length, 1);
      expect(identical(second, first), isTrue, reason: 'no pointless write');
    });

    test('dedupes against already-decided history too', () {
      final existing = [
        CapturedNotice(
          id: 'n1',
          rawText: 'PKR 100 sent to A',
          capturedAt: now,
          status: CaptureStatus.dismissed,
        ),
      ];
      final merged = CaptureIngest.merge(
        existing: existing,
        rawTexts: const ['PKR 100 sent to A'],
        now: now,
        newId: nextId,
      );
      expect(merged.length, 1);
      expect(merged.single.status, CaptureStatus.dismissed);
    });

    test('skips blank text', () {
      final merged = CaptureIngest.merge(
        existing: const [],
        rawTexts: const ['', '   '],
        now: now,
        newId: nextId,
      );
      expect(merged, isEmpty);
    });

    test('history stays bounded, dropping the oldest', () {
      final existing = [
        for (var i = 0; i < CaptureIngest.maxHistory; i++)
          CapturedNotice(
            id: 'old$i',
            rawText: 'msg $i',
            capturedAt: now.subtract(Duration(days: i)),
          ),
      ];
      final merged = CaptureIngest.merge(
        existing: existing,
        rawTexts: const ['brand new'],
        now: now,
        newId: nextId,
      );
      expect(merged.length, CaptureIngest.maxHistory);
      expect(merged.last.rawText, 'brand new');
      expect(merged.any((n) => n.rawText == 'msg 0'), isFalse);
    });
  });

  group('CaptureIngest.withStatus', () {
    final notices = [
      CapturedNotice(id: 'a', rawText: 'A', capturedAt: now),
      CapturedNotice(id: 'b', rawText: 'B', capturedAt: now),
    ];

    test('pending → added records the transaction id', () {
      final next = CaptureIngest.withStatus(
        notices,
        'a',
        CaptureStatus.added,
        txnId: 't1',
      );
      expect(next.first.status, CaptureStatus.added);
      expect(next.first.txnId, 't1');
      expect(next.last.status, CaptureStatus.pending, reason: 'others intact');
    });

    test('pending → dismissed keeps the record with no txn', () {
      final next = CaptureIngest.withStatus(
        notices,
        'b',
        CaptureStatus.dismissed,
      );
      expect(next.last.status, CaptureStatus.dismissed);
      expect(next.last.txnId, isNull);
      expect(next.length, 2, reason: 'dismissing never drops the record');
    });

    test('dismissed → added ("Add anyway") works', () {
      final dismissed = CaptureIngest.withStatus(
        notices,
        'a',
        CaptureStatus.dismissed,
      );
      final added = CaptureIngest.withStatus(
        dismissed,
        'a',
        CaptureStatus.added,
        txnId: 't2',
      );
      expect(added.first.status, CaptureStatus.added);
      expect(added.first.txnId, 't2');
    });

    test('an unknown id changes nothing', () {
      final next = CaptureIngest.withStatus(
        notices,
        'nope',
        CaptureStatus.added,
        txnId: 't3',
      );
      expect(next.every((n) => n.isPending), isTrue);
    });
  });
}

import 'dart:typed_data';

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/dashboard/dashboard_period.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a clean black-and-white account statement PDF for a period:
/// money in / out / net, per-account flow, spending by category, and the
/// transaction list. Large typography, thin rules — matches the app's mono
/// theme. All rendered on-device; nothing is uploaded.
abstract final class StatementPdfService {
  static Future<Uint8List> build({
    required AppData data,
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    final (start, end) = period.range(now);
    final code = data.currencyCode;
    String money(int m) => Money.format(m, code: code);
    final dfLong = DateFormat.yMMMMd();
    final dfShort = DateFormat.MMMd();

    final income = DashboardFlow.incomeInRange(data, start, end);
    final spent = DashboardFlow.spentInRange(data, start, end);
    final flows = DashboardFlow.byAccount(
      data,
      start,
      end,
    ).where((f) => f.inMinor > 0 || f.outMinor > 0).toList();

    final txns =
        data.txns
            .where((t) => DashboardFlow.inRange(t.date, start, end))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    // -- Category spend (expense own-share) over the range -----------------
    final byCat = <String, int>{};
    for (final t in txns) {
      if (t.type != TxnType.expense) continue;
      final key = t.categoryId ?? '';
      byCat[key] = (byCat[key] ?? 0) + t.ownShareMinor;
    }
    final cats = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String catName(String? id) => (id == null || id.isEmpty)
        ? 'Uncategorized'
        : (data.categoryById(id)?.name ?? 'Uncategorized');
    String acctName(String? id) =>
        id == null ? '' : (data.accountById(id)?.name ?? '');

    (String, String) txnLabel(Txn t) => switch (t.type) {
      TxnType.expense => (catName(t.categoryId), '-${money(t.amountMinor)}'),
      TxnType.income => (
        t.note.isEmpty ? 'Income' : t.note,
        '+${money(t.amountMinor)}',
      ),
      TxnType.transfer => (
        '${acctName(t.accountId)} → ${acctName(t.toAccountId)}',
        money(t.amountMinor),
      ),
    };

    final doc = pw.Document();
    final black = PdfColors.black;
    final grey = PdfColors.grey700;
    final rule = PdfColors.grey400;

    pw.Widget bigStat(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(fontSize: 9, color: grey, letterSpacing: 1),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );

    pw.Widget row(
      String left,
      String right, {
      bool bold = false,
      PdfColor? c,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              left,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            right,
            style: pw.TextStyle(
              fontSize: 11,
              color: c ?? black,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );

    pw.Widget sectionTitle(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
        build: (context) => [
          // Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BUDGETLY',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: grey,
                      letterSpacing: 3,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Statement',
                    style: pw.TextStyle(
                      fontSize: 30,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    period.label,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${dfLong.format(start)} – ${dfLong.format(end)}',
                    style: pw.TextStyle(fontSize: 10, color: grey),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: rule, thickness: 1),
          pw.SizedBox(height: 16),
          // Big summary
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              bigStat('Money in', money(income)),
              bigStat('Money out', money(spent)),
              bigStat('Net', money(income - spent)),
            ],
          ),
          // Per-account flow
          if (flows.isNotEmpty) ...[
            sectionTitle('By account'),
            pw.Divider(color: rule, thickness: 0.5),
            row('Account', 'In      Out', bold: true),
            for (final f in flows)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        f.name,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Text(
                      '+${money(f.inMinor)}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.SizedBox(width: 16),
                    pw.SizedBox(
                      width: 90,
                      child: pw.Text(
                        '-${money(f.outMinor)}',
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          // Spending by category
          if (cats.isNotEmpty) ...[
            sectionTitle('Spending by category'),
            pw.Divider(color: rule, thickness: 0.5),
            for (final e in cats.take(10)) row(catName(e.key), money(e.value)),
          ],
          // Transactions
          if (txns.isNotEmpty) ...[
            sectionTitle('Transactions'),
            pw.Divider(color: rule, thickness: 0.5),
            for (final t in txns)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 54,
                      child: pw.Text(
                        dfShort.format(t.date),
                        style: pw.TextStyle(fontSize: 10, color: grey),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        txnLabel(t).$1,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.SizedBox(
                      width: 70,
                      child: pw.Text(
                        acctName(t.accountId),
                        style: pw.TextStyle(fontSize: 9, color: grey),
                      ),
                    ),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(
                        txnLabel(t).$2,
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          pw.SizedBox(height: 24),
          pw.Text(
            'Generated ${dfLong.format(now)} · Budgetly · offline & private',
            style: pw.TextStyle(fontSize: 9, color: grey),
          ),
        ],
      ),
    );
    return doc.save();
  }
}

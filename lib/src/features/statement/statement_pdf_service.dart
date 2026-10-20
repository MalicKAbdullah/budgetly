import 'dart:typed_data';

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds an account statement PDF for a period: money in / out / net,
/// per-account flow, spending by category, and the transaction list. It uses
/// the app's light palette — graphite ink, hairline rules, cobalt only for
/// the brand line — so it prints cleanly in greyscale. All rendered
/// on-device; nothing is uploaded.
abstract final class StatementPdfService {
  static Future<Uint8List> build({
    required AppData data,
    required PeriodFilter filter,
    required DateTime now,
  }) async {
    final (start, end) = filter.resolve(now);
    final code = data.currencyCode;
    String money(int m) => Money.format(m, code: code);
    final dfLong = DateFormat.yMMMMd();
    final dfShort = DateFormat.MMMd();

    final savings = Savings.position(data);
    final savingsWindow = Savings.period(data, start, end);
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

    // Own-share expense per category, settlements excluded.
    final cats = DashboardFlow.spendByCategory(data, start, end);

    String catName(String? id) => (id == null || id.isEmpty)
        ? 'Uncategorized'
        : (data.categoryById(id)?.name ?? 'Uncategorized');
    String acctName(String? id) =>
        id == null ? '' : (data.accountById(id)?.name ?? '');

    // The figure printed per row is what the movement cost or earned the
    // owner: a split shows their share with the full bill spelled out, and a
    // settlement is labelled so it never reads as income or spending.
    (String, String) txnLabel(Txn t) {
      if (t.isSettlement) {
        final sign = t.type == TxnType.income ? '+' : '-';
        return (
          '${SplitText.settlementTitle(t)} (settlement)',
          '$sign${money(t.amountMinor)}',
        );
      }
      return switch (t.type) {
        TxnType.expense => (
          [
            catName(t.categoryId),
            SplitText.describe(t, code),
          ].whereType<String>().join(' — '),
          '-${money(t.ownShareMinor)}',
        ),
        TxnType.income => (
          t.note.isEmpty ? 'Income' : t.note,
          '+${money(t.amountMinor)}',
        ),
        TxnType.transfer => (
          '${acctName(t.accountId)} → ${acctName(t.toAccountId)}',
          money(t.amountMinor),
        ),
      };
    }

    final doc = pw.Document();
    // Offlyne light tokens: textPrimary, textSecondary, border, hairline,
    // surfaceAlt, Budgetly accent, positive.
    const black = PdfColor.fromInt(0xFF0E1116);
    const grey = PdfColor.fromInt(0xFF5B6371);
    const rule = PdfColor.fromInt(0xFFE2E5EA);
    const hairline = PdfColor.fromInt(0xFFE8EBEF);
    const tint = PdfColor.fromInt(0xFFF6F7F9);
    const accent = PdfColor.fromInt(0xFF0F62D6);
    const positive = PdfColor.fromInt(0xFF0E9F55);

    pw.Widget bigStat(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: grey)),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 20,
            color: black,
            fontWeight: pw.FontWeight.bold,
          ),
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
                color: bold ? grey : black,
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
          fontSize: 14,
          color: black,
          fontWeight: pw.FontWeight.bold,
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
                    'Budgetly',
                    style: pw.TextStyle(
                      fontSize: 11,
                      color: accent,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Statement',
                    style: pw.TextStyle(
                      fontSize: 30,
                      color: black,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    filter.label(now),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    filter.isAllTime
                        ? 'Everything recorded'
                        : '${dfLong.format(start)} – ${dfLong.format(end)}',
                    style: pw.TextStyle(fontSize: 10, color: grey),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          // Big summary on a tinted panel, the PDF's one card.
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: tint,
              border: pw.Border.all(color: hairline),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                bigStat('Money in', money(income)),
                bigStat('Money out', money(spent)),
                bigStat('Net', money(income - spent)),
              ],
            ),
          ),
          // Savings — a pot reserved across every account, left out of the
          // money in / money out figures above.
          sectionTitle('Savings'),
          pw.Divider(color: rule, thickness: 0.75),
          row('Position', money(savings.positionMinor)),
          if (savings.hasTarget) ...[
            row('Target', money(savings.targetMinor)),
            row(
              'Free to spend',
              '${savings.freeToSpendMinor >= 0 ? '+' : '-'}'
                  '${money(savings.freeToSpendMinor.abs())}',
            ),
          ],
          if (savings.uncountedReceivablesMinor > 0)
            row(
              'Lent out, not counted',
              money(savings.uncountedReceivablesMinor),
            ),
          row('Carried in', money(savingsWindow.carriedInMinor)),
          row(
            'Change this period',
            '${savingsWindow.changeMinor >= 0 ? '+' : '-'}'
                '${money(savingsWindow.changeMinor.abs())}',
          ),
          row('At period end', money(savingsWindow.closingMinor)),
          // Per-account flow
          if (flows.isNotEmpty) ...[
            sectionTitle('By account'),
            pw.Divider(color: rule, thickness: 0.75),
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
                      style: const pw.TextStyle(fontSize: 11, color: positive),
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
            pw.Divider(color: rule, thickness: 0.75),
            for (final e in cats.take(10)) row(catName(e.key), money(e.value)),
          ],
          // Transactions
          if (txns.isNotEmpty) ...[
            sectionTitle('Transactions'),
            pw.Divider(color: rule, thickness: 0.75),
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
            style: const pw.TextStyle(fontSize: 9, color: grey),
          ),
        ],
      ),
    );
    return doc.save();
  }
}

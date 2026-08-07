import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/capture/review_sheet.dart';
import 'package:budgetly/src/features/capture/sms_parser.dart';

/// The captured-transactions inbox. Bank/wallet alerts caught on-device land
/// in **Needs review**; everything that has been added or dismissed stays in
/// **History**, so there is always a record of what Budgetly saw.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  bool _supported = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final capture = ref.read(captureServiceProvider);
    final supported = capture.supported;
    final enabled = supported && await capture.isEnabled();
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
    });
    if (ref.read(appDataProvider).hasValue) {
      await ref.read(appDataProvider.notifier).ingestNativeQueue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured transactions'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for new alerts',
          ),
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : _body(data),
    );
  }

  Widget _body(AppData data) {
    final pending = data.pendingNotices.reversed.toList();
    final history = data.capturedNotices
        .where((n) => !n.isPending)
        .toList()
        .reversed
        .toList();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_supported) _statusCard(),
        const SizedBox(height: AppSpacing.md),
        _sectionTitle(
          'Needs review${pending.isEmpty ? '' : ' (${pending.length})'}',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (pending.isEmpty)
          _emptyCard(
            'Nothing to review',
            'New bank or wallet alerts will show up here.',
          )
        else
          for (final n in pending)
            _PendingCard(notice: n, currencyCode: data.currencyCode),
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle('History'),
        const SizedBox(height: AppSpacing.sm),
        if (history.isEmpty)
          _emptyCard(
            'No history yet',
            'Once you add or dismiss a captured alert, it stays here.',
          )
        else
          for (final n in history) _HistoryCard(notice: n, data: data),
      ],
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  Widget _emptyCard(String title, String body) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _statusCard() {
    if (_enabled) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.notifications_active_outlined),
          title: Text('Auto-capture is on'),
          subtitle: Text('New bank/wallet alerts show up here to confirm.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Turn on auto-capture',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Let Budgetly read bank/wallet transaction alerts on-device (e.g. '
              'Meezan SMS) so they appear here to confirm — nothing is '
              'uploaded. Grant "notification access" to Budgetly.',
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref.read(captureServiceProvider).openSettings();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Grant notification access'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One alert awaiting a decision. Tapping anywhere opens the review sheet.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.notice, required this.currencyCode});

  final CapturedNotice notice;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final parsed = SmsParser.parse(
      sender: 'notification',
      body: notice.rawText,
    );
    final title = parsed == null
        ? 'Needs your details'
        : '${parsed.direction == TxnDirection.debit ? 'Expense' : 'Income'} · '
              '${Money.format(parsed.amountMinor, code: currencyCode)}'
              '${parsed.merchant != null ? ' · ${parsed.merchant}' : ''}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showCaptureReviewSheet(context, notice),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                notice.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => showCaptureReviewSheet(context, notice),
                  child: const Text('Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An already-decided alert: what it became, or that it was dismissed.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.notice, required this.data});

  final CapturedNotice notice;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final added = notice.status == CaptureStatus.added;
    final txn = notice.txnId == null ? null : data.txnById(notice.txnId!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(notice.status.label),
                  avatar: Icon(
                    added ? Icons.check_circle_outline : Icons.block_outlined,
                    size: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                Text(
                  DateFormat.yMMMd().format(notice.capturedAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (txn != null)
              Text(
                '${txn.type.label} · '
                '${Money.format(txn.amountMinor, code: data.currencyCode)} · '
                '${DateFormat.yMMMd().format(txn.date)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 4),
            Text(
              notice.rawText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (!added)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => showCaptureReviewSheet(context, notice),
                  child: const Text('Add anyway'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
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
            icon: const Icon(Icons.refresh_rounded),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.xl,
      ),
      children: [
        if (_supported) ...[
          _statusCard(),
          const SizedBox(height: AppSpacing.sm),
        ],
        SectionHeader(
          title: 'Needs review${pending.isEmpty ? '' : ' (${pending.length})'}',
          subtitle: pending.isEmpty
              ? null
              : 'Confirm each one before it reaches your books',
        ),
        if (pending.isEmpty)
          const VaultCard(
            child: AppEmptyState(
              compact: true,
              icon: Icons.inbox_outlined,
              title: 'Nothing to review',
              message: 'New bank or wallet alerts will show up here.',
            ),
          )
        else
          // Each alert is its own decision, so every one gets its own card.
          for (final n in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.smd),
              child: _PendingCard(notice: n, currencyCode: data.currencyCode),
            ),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader(title: 'History'),
        if (history.isEmpty)
          const VaultCard(
            child: AppEmptyState(
              compact: true,
              icon: Icons.history_rounded,
              title: 'No history yet',
              message:
                  'Once you add or dismiss a captured alert, it stays here.',
            ),
          )
        else
          RowGroup(
            children: [
              for (final n in history) _HistoryRow(notice: n, data: data),
            ],
          ),
      ],
    );
  }

  Widget _statusCard() {
    if (_enabled) {
      return const AppBanner(
        kind: BannerKind.success,
        icon: Icons.notifications_active_outlined,
        title: 'Auto-capture is on',
        message: 'New bank/wallet alerts show up here to confirm.',
      );
    }
    final c = SuiteColors.of(context);
    return VaultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.notifications_none_rounded,
                color: c.accent,
              ),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: Text(
                  'Turn on auto-capture',
                  style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smd),
          Text(
            'Let Budgetly read bank/wallet transaction alerts on-device (e.g. '
            'Meezan SMS) so they appear here to confirm — nothing is '
            'uploaded. Grant "notification access" to Budgetly.',
            style: AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          VaultButton(
            label: 'Grant notification access',
            icon: Icons.settings_outlined,
            variant: VaultButtonVariant.secondary,
            isFullWidth: false,
            compact: true,
            onPressed: () async {
              await ref.read(captureServiceProvider).openSettings();
            },
          ),
        ],
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
    final c = SuiteColors.of(context);
    final parsed = SmsParser.parse(
      sender: 'notification',
      body: notice.rawText,
    );
    final debit = parsed?.direction == TxnDirection.debit;
    final when = DateFormat.MMMd().add_jm().format(
      parsed?.when ?? notice.capturedAt,
    );
    return VaultCard(
      onTap: () => showCaptureReviewSheet(context, notice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: parsed == null
                    ? Icons.help_outline_rounded
                    : debit
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
                color: parsed == null || debit ? null : c.positive,
              ),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parsed == null
                          ? 'Needs your details'
                          : parsed.merchant != null
                          ? _titleCase(parsed.merchant!)
                          : (debit ? 'Money out' : 'Money in'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${parsed == null
                          ? 'Alert'
                          : debit
                          ? 'Expense'
                          : 'Income'}'
                      ' · $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smd),
          Text(
            notice.rawText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: parsed == null
                    ? const SizedBox.shrink()
                    : AmountText(
                        debit ? -parsed.amountMinor : parsed.amountMinor,
                        code: currencyCode,
                        style: AppTextStyles.numberLarge,
                        tone: debit ? MoneyTone.neutral : MoneyTone.signed,
                        showPlus: !debit,
                      ),
              ),
              const SizedBox(width: AppSpacing.smd),
              VaultButton(
                label: 'Review',
                compact: true,
                isFullWidth: false,
                onPressed: () => showCaptureReviewSheet(context, notice),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bank alerts shout names in capitals; the card reads them as names.
String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// An already-decided alert: what it became, or that it was dismissed.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.notice, required this.data});

  final CapturedNotice notice;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final added = notice.status == CaptureStatus.added;
    final txn = notice.txnId == null ? null : data.txnById(notice.txnId!);
    final title = txn == null
        ? (SmsParser.parse(
                sender: 'notification',
                body: notice.rawText,
              )?.merchant ??
              'Bank alert')
        : '${txn.type.label} · '
              '${Money.format(txn.amountMinor, code: data.currencyCode)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.smd,
        AppSpacing.md,
        AppSpacing.smd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: added ? Icons.check_rounded : Icons.block_rounded,
            color: added ? c.positive : null,
          ),
          const SizedBox(width: AppSpacing.smd + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      notice.status.label,
                      style: AppTextStyles.caption.copyWith(
                        color: added ? c.positive : c.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat.yMMMd().format(txn?.date ?? notice.capturedAt)}'
                  ' · ${notice.rawText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                if (!added)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => showCaptureReviewSheet(context, notice),
                      child: const Text('Add anyway'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

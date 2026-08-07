import 'package:core_theme/core_theme.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/providers.dart';

/// "Update available" card, shown when a newer GitHub release exists and the
/// user hasn't dismissed it this session.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).valueOrNull;
    final dismissed = ref.watch(updateDismissedProvider);
    if (info == null || dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: UpdateBanner(
        info: info,
        onUpdate: () => ref.read(updateServiceProvider).openDownload(info),
        onDismiss: () =>
            ref.read(updateDismissedProvider.notifier).state = true,
      ),
    );
  }
}

/// "We captured N transactions — review?" banner. Shows only while captured
/// alerts are still awaiting a decision.
class CaptureBanner extends ConsumerWidget {
  const CaptureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(pendingNoticesProvider).length;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.mark_email_unread_outlined),
          title: Text(
            n == 1
                ? '1 captured transaction to review'
                : '$n captured transactions to review',
          ),
          subtitle: const Text(
            'From your bank/wallet alerts — accept or discard',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/capture'),
        ),
      ),
    );
  }
}

/// Fires the on-open budget notification checks exactly once per app open.
/// Renders nothing.
class NotifyTrigger extends ConsumerStatefulWidget {
  const NotifyTrigger({required this.data, super.key});
  final AppData data;

  @override
  ConsumerState<NotifyTrigger> createState() => _NotifyTriggerState();
}

class _NotifyTriggerState extends ConsumerState<NotifyTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(budgetNotifierProvider).checkOnOpen(widget.data, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

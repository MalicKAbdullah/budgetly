import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/settle_match.dart';
import 'package:budgetly/src/core/money.dart';

/// "Settles a balance?" — the people a transaction could square up with, most
/// likely first. Tapping a person selects them; tapping again clears it. The
/// line under the list says exactly what saving will do to their balance.
class SettleSuggestionPicker extends StatefulWidget {
  const SettleSuggestionPicker({
    required this.suggestions,
    required this.selectedKey,
    required this.amountMinor,
    required this.code,
    required this.onChanged,
    super.key,
  });

  /// Ranked by [SettleMatch.suggest]. Never empty — the caller hides the
  /// section when nobody has a balance in this direction.
  final List<SettleSuggestion> suggestions;

  /// The [PersonPosition.key] of the chosen person, or null for none.
  final String? selectedKey;
  final int? amountMinor;
  final String code;
  final ValueChanged<SettleSuggestion?> onChanged;

  /// What saving does to the chosen balance, in the owner's words.
  static String outcomeText(SettleSuggestion s, int amountMinor, String code) {
    final name = s.position.name;
    final open = s.openMinor;
    if (amountMinor == open) return "Clears $name's balance.";
    if (amountMinor < open) {
      final left = Money.format(open - amountMinor, code: code);
      return s.kind == DebtKind.owedToYou
          ? '$name will still owe you $left.'
          : 'You will still owe $name $left.';
    }
    final excess = Money.format(amountMinor - open, code: code);
    return "Clears $name's balance; the other $excess is recorded as "
        '${s.kind == DebtKind.owedToYou ? 'income' : 'spending'}.';
  }

  @override
  State<SettleSuggestionPicker> createState() => _SettleSuggestionPickerState();
}

class _SettleSuggestionPickerState extends State<SettleSuggestionPicker> {
  /// How many people show before "Show everyone" — the ranking puts the
  /// likely ones on top, so a long list would only bury them.
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final all = widget.suggestions;
    final selectedIndex = all.indexWhere(
      (s) => s.position.key == widget.selectedKey,
    );
    // The chosen person always stays visible, even past the fold.
    final shown = _expanded || all.length <= _collapsedCount
        ? all
        : [
            ...all.take(_collapsedCount),
            if (selectedIndex >= _collapsedCount) all[selectedIndex],
          ];
    final receiving = all.first.kind == DebtKind.owedToYou;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settles a balance?',
          style: AppTextStyles.h4.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          receiving
              ? 'Money in can be someone paying you back.'
              : 'Money out can be you paying someone back.',
          style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpacing.smd),
        for (final s in shown)
          _SuggestionTile(
            s: s,
            code: widget.code,
            selected: s.position.key == widget.selectedKey,
            onTap: () => widget.onChanged(
              s.position.key == widget.selectedKey ? null : s,
            ),
          ),
        if (shown.length < all.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text('Show everyone (${all.length})'),
            ),
          ),
        if (selectedIndex >= 0 && widget.amountMinor != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_rounded, size: 18, color: c.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  SettleSuggestionPicker.outcomeText(
                    all[selectedIndex],
                    widget.amountMinor!,
                    widget.code,
                  ),
                  style: AppTextStyles.bodySmall.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.s,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final SettleSuggestion s;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final reasons = [
      if (s.exactAmount) 'Exact amount',
      if (s.namedInText) 'Named in the alert',
    ];
    final owed = s.kind == DebtKind.owedToYou;
    final name = s.position.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.accentContainer : c.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: BorderSide(
              color: selected ? c.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smd,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: selected
                          ? IconBadge(
                              key: const ValueKey('on'),
                              icon: Icons.check_rounded,
                              color: c.accent,
                              solid: true,
                              size: 36,
                            )
                          : IconBadge(
                              key: const ValueKey('off'),
                              monogram: name.isEmpty
                                  ? '?'
                                  : name[0].toUpperCase(),
                              size: 36,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.smd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.position.name,
                            style: AppTextStyles.body.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            owed
                                ? 'Owes you ${Money.format(s.openMinor, code: code)}'
                                : 'You owe ${Money.format(s.openMinor, code: code)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: c.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          reasons.join(' · '),
                          textAlign: TextAlign.end,
                          style: AppTextStyles.caption.copyWith(
                            color: c.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

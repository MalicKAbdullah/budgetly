import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/providers.dart';

/// Picks somebody to put on a split — from the people already registered, or by
/// typing a new name, which registers them on the spot.
///
/// [exclude] holds the ids already on this split, so nobody can be added twice.
Future<Person?> showPersonPicker(
  BuildContext context, {
  required Set<String> exclude,
}) => showModalBottomSheet<Person>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PersonPickerSheet(exclude: exclude),
);

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet({required this.exclude});
  final Set<String> exclude;

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addTyped(AppData data) async {
    final typed = _name.text.trim();
    if (typed.isEmpty) return;
    final person = await ref.read(appDataProvider.notifier).addPerson(typed);
    if (mounted) Navigator.pop(context, person);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull ?? const AppData();
    final query = _name.text.trim().toLowerCase();
    final available = data.peopleByName
        .where((p) => !widget.exclude.contains(p.id))
        .where((p) => query.isEmpty || p.nameKey.contains(query))
        .toList();
    final exactMatch = data.personByName(_name.text) != null;
    final c = SuiteColors.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Who is on this split?',
            style: AppTextStyles.h3.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Ali',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => exactMatch ? null : _addTyped(data),
          ),
          if (_name.text.trim().isNotEmpty && !exactMatch) ...[
            const SizedBox(height: AppSpacing.sm),
            VaultButton(
              onPressed: () => _addTyped(data),
              icon: Icons.person_add_alt_rounded,
              variant: VaultButtonVariant.secondary,
              label: 'Add "${_name.text.trim()}"',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                data.people.isEmpty
                    ? 'Nobody added yet — type a name above.'
                    : 'No other person matches.',
                style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
              ),
            )
          else
            RowGroup(
              children: [
                for (final p in available)
                  AppListRow(
                    dense: true,
                    leading: IconBadge(
                      monogram: p.name.trim().isEmpty
                          ? '?'
                          : p.name.trim()[0].toUpperCase(),
                      size: 36,
                    ),
                    title: p.name,
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

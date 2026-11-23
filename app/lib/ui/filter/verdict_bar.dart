import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';
import '../../theme/app_theme.dart';
import '../../filter/verdict_controller.dart';

/// Three-way classification control (Inbox · Newsletter · Spam) with Undo.
/// Exposes explicit Semantics labels for screen readers and keyboard navigation.
class VerdictBar extends ConsumerWidget {
  final String messageId;
  final Label currentLabel;
  final void Function(Label newLabel, int similarCount)? onVerdictChanged;

  const VerdictBar({
    super.key,
    required this.messageId,
    required this.currentLabel,
    this.onVerdictChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.df.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildItem(
            context,
            ref,
            label: Label.inbox,
            title: AppStrings.verdictInbox,
            semanticsText: AppStrings.markAsInbox,
            icon: Icons.inbox_outlined,
            isSelected: currentLabel == Label.inbox || currentLabel == Label.ham,
          ),
          const SizedBox(width: 4),
          _buildItem(
            context,
            ref,
            label: Label.newsletter,
            title: AppStrings.verdictNewsletter,
            semanticsText: AppStrings.markAsNewsletter,
            icon: Icons.newspaper_outlined,
            isSelected: currentLabel == Label.newsletter,
          ),
          const SizedBox(width: 4),
          _buildItem(
            context,
            ref,
            label: Label.spam,
            title: AppStrings.verdictSpam,
            semanticsText: AppStrings.markAsSpam,
            icon: Icons.report_outlined,
            isSelected: currentLabel == Label.spam,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref, {
    required Label label,
    required String title,
    required String semanticsText,
    required IconData icon,
    required bool isSelected,
  }) {
    final palette = context.df.colors;
    final color = AppTheme.classificationColor(context, label);

    return Semantics(
      label: semanticsText,
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final similar = await ref.read(verdictControllerProvider).applyVerdict(
              messageId: messageId,
              newLabel: label,
            );
            onVerdictChanged?.call(label, similar);
            if (context.mounted) _showUndoSnackBar(context, ref);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? color : palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Public Sans',
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? color : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUndoSnackBar(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // A SnackBar with an action stays on screen until dismissed unless
        // persist is false; the duration alone is ignored.
        persist: false,
        duration: const Duration(milliseconds: 2500),
        content: const Text(
          AppStrings.verdictLearned,
          style: TextStyle(fontFamily: 'Public Sans'),
        ),
        action: SnackBarAction(
          label: AppStrings.undoAction,
          onPressed: () {
            ref.read(verdictControllerProvider).undo();
          },
        ),
      ),
    );
  }
}

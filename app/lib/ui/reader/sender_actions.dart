import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../filter/sender_rules.dart';
import '../../filter/verdict_controller.dart';
import '../../theme/app_type.dart';

/// Compact row offering actions on the sender (Allow, Block address, Block domain).
class SenderActions extends ConsumerWidget {
  final String messageId;
  final String sender;
  final String? senderDomain;
  final Label currentLabel;

  const SenderActions({
    super.key,
    required this.messageId,
    required this.sender,
    this.senderDomain,
    required this.currentLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.df.colors;
    final email = SenderRules.extractEmail(sender);
    var domain = (senderDomain ?? '').trim().toLowerCase();
    if (domain.isEmpty && email.contains('@')) {
      domain = email.split('@').last.trim().toLowerCase();
    }
    final isFreemail = domain.isNotEmpty && isFreemailDomain(domain);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Always allow sender
        TextButton.icon(
          onPressed: () {
            ref.read(senderRulesProvider).set(email, 'address', SenderRuleAction.allow);
            final wasSpam = currentLabel == Label.spam;
            if (wasSpam) {
              ref.read(verdictControllerProvider).applyVerdict(
                    messageId: messageId,
                    newLabel: Label.ham,
                  );
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Always allowing $email'),
                action: SnackBarAction(
                  label: AppStrings.undoAction,
                  onPressed: () {
                    ref.read(senderRulesProvider).remove(email);
                    if (wasSpam) {
                      ref.read(verdictControllerProvider).applyVerdict(
                            messageId: messageId,
                            newLabel: Label.spam,
                          );
                    }
                  },
                ),
              ),
            );
          },
          icon: Icon(Icons.check_circle_outline_rounded, size: 14, color: c.success.deep),
          label: Text(
            UiStrings.alwaysAllowSender,
            style: AppType.ui(c.textSecondary, size: 12.5, weight: FontWeight.w500),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: c.surfaceSunken,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.sm)),
          ),
        ),
        // Block sender
        TextButton.icon(
          onPressed: () {
            ref.read(senderRulesProvider).set(email, 'address', SenderRuleAction.block);
            ref.read(verdictControllerProvider).applyVerdict(
                  messageId: messageId,
                  newLabel: Label.spam,
                );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Blocked $email'),
                action: SnackBarAction(
                  label: AppStrings.undoAction,
                  onPressed: () {
                    ref.read(senderRulesProvider).remove(email);
                    ref.read(verdictControllerProvider).undo();
                  },
                ),
              ),
            );
          },
          icon: Icon(Icons.block_rounded, size: 14, color: c.error.deep),
          label: Text(
            UiStrings.blockSender,
            style: AppType.ui(c.textSecondary, size: 12.5, weight: FontWeight.w500),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: c.surfaceSunken,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.sm)),
          ),
        ),
        // Block domain (hidden for freemail domains)
        if (!isFreemail && domain.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              ref.read(senderRulesProvider).set(domain, 'domain', SenderRuleAction.block);
              ref.read(verdictControllerProvider).applyVerdict(
                    messageId: messageId,
                    newLabel: Label.spam,
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Blocked domain @$domain'),
                  action: SnackBarAction(
                    label: AppStrings.undoAction,
                    onPressed: () {
                      ref.read(senderRulesProvider).remove(domain);
                      ref.read(verdictControllerProvider).undo();
                    },
                  ),
                ),
              );
            },
            icon: Icon(Icons.domain_disabled_rounded, size: 14, color: c.error.deep),
            label: Text(
              UiStrings.blockDomain,
              style: AppType.ui(c.textSecondary, size: 12.5, weight: FontWeight.w500),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: c.surfaceSunken,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.sm)),
            ),
          ),
      ],
    );
  }
}

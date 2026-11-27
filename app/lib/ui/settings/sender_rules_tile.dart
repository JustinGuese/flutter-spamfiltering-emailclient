import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/ui_strings.dart';
import '../../filter/screener.dart';
import '../../filter/sender_rules.dart';
import '../../mail/sync_engine.dart';
import '../../theme/app_type.dart';

/// Settings tile managing sender rules and screener mode.
class SenderRulesTile extends ConsumerWidget {
  const SenderRulesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mailRevisionProvider);
    final rulesService = ref.watch(senderRulesProvider);
    final screener = ref.watch(screenerProvider);
    final screenerMode = ref.watch(screenerModeProvider);
    final isStrict = screenerMode == 'strict';
    final palette = context.df.colors;
    final rules = rulesService.all();

    return DfSettingsTile(
      title: const Text('Sender Rules & Screener'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Screener mode switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              UiStrings.screenerStrict,
              style: AppType.ui(palette.textPrimary, size: 14, weight: FontWeight.w600),
            ),
            subtitle: Text(
              UiStrings.screenerStrictHelp,
              style: AppType.ui(palette.textSecondary, size: 12),
            ),
            value: isStrict,
            onChanged: (val) {
              screener.setScreenerMode(val ? 'strict' : 'tab');
              ref.read(mailRevisionProvider.notifier).bump();
            },
          ),
          const SizedBox(height: 8),
          Divider(color: palette.hairline),
          const SizedBox(height: 6),
          Text(
            'Rules (${rules.length})',
            style: AppType.ui(palette.textPrimary, size: 13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (rules.isEmpty)
            Text(
              UiStrings.senderRulesEmpty,
              style: AppType.ui(palette.textTertiary, size: 12),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final r = rules[index];
                final isAllow = r.action == SenderRuleAction.allow;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isAllow
                              ? palette.success.bg
                              : palette.error.bg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAllow ? 'ALLOW' : 'BLOCK',
                          style: AppType.mono(
                            isAllow ? palette.success.deep : palette.error.deep,
                            size: 10,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.pattern,
                          style: AppType.mono(palette.textPrimary, size: 12.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: palette.textTertiary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          rulesService.remove(r.pattern);
                          ref.read(mailRevisionProvider.notifier).bump();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

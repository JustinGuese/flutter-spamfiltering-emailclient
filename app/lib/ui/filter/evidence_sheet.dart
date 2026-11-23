import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';

/// Mono-spaced ledger sheet displaying individual signals and their weights.
class EvidenceSheet extends StatelessWidget {
  final Verdict verdict;

  const EvidenceSheet({
    super.key,
    required this.verdict,
  });

  static void show(BuildContext context, Verdict verdict) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.df.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => EvidenceSheet(verdict: verdict),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.evidenceTitle,
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppStrings.evidenceSubtitle} · Total Score: ${(verdict.spamScore * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            if (verdict.evidence.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No explicit evidence signals recorded.',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: verdict.evidence.length,
                  separatorBuilder: (_, _) => Divider(color: palette.hairline),
                  itemBuilder: (context, index) {
                    final e = verdict.evidence[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceSunken,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              e.weight >= 0
                                  ? '+${e.weight.toStringAsFixed(2)}'
                                  : e.weight.toStringAsFixed(2),
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: e.weight > 0.5 ? palette.error.base : palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.id,
                                  style: TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  e.detail,
                                  style: TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

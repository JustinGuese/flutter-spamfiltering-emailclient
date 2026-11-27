import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../filter/evidence_sheet.dart';

/// Card warning user of suspected phishing attempt.
class PhishingBanner extends StatelessWidget {
  final Verdict verdict;
  final VoidCallback? onDetails;

  const PhishingBanner({
    super.key,
    required this.verdict,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;

    // Find top phishing evidence detail
    final topPhish = verdict.evidence.firstWhere(
      (e) => phishingEvidenceIds.contains(e.id),
      orElse: () => verdict.evidence.isNotEmpty
          ? verdict.evidence.first
          : const Evidence(id: 'phishing', weight: 1.0, detail: UiStrings.phishingFallbackDetail),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.error.bg,
        borderRadius: BorderRadius.circular(context.df.shape.sm),
        border: Border.all(color: c.error.base.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: c.error.deep, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  UiStrings.phishingTitle,
                  style: AppType.ui(c.error.deep, size: 14.5, weight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onDetails ?? () => EvidenceSheet.show(context, verdict),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Details',
                  style: AppType.ui(c.error.deep, size: 12.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            UiStrings.phishingBody,
            style: AppType.ui(c.textPrimary, size: 13, height: 1.4),
          ),
          if (topPhish.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.canvas.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                topPhish.detail,
                style: AppType.mono(c.error.deep, size: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

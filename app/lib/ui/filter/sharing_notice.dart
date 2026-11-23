import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';

/// First-time notice displayed inline when a user marks a message as spam,
/// explaining anonymous cryptographic fingerprinting and offering an off-switch.
class SharingNoticeBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onTurnOff;
  final VoidCallback? onLearnMore;

  const SharingNoticeBanner({
    super.key,
    required this.onDismiss,
    required this.onTurnOff,
    this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: palette.accent.base),
              const SizedBox(width: 8),
              Text(
                AppStrings.sharingNoticeTitle,
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.sharingNoticeBody,
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onLearnMore != null)
                TextButton(
                  onPressed: onLearnMore,
                  child: Text(
                    AppStrings.sharingNoticeLearnMore,
                    style: TextStyle(
                      fontFamily: 'Public Sans',
                      fontSize: 12,
                      color: palette.brand.base,
                    ),
                  ),
                ),
              TextButton(
                onPressed: onTurnOff,
                child: Text(
                  AppStrings.sharingNoticeTurnOff,
                  style: TextStyle(
                    fontFamily: 'Public Sans',
                    fontSize: 12,
                    color: palette.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onDismiss,
                child: const Text(
                  AppStrings.sharingNoticeDismiss,
                  style: TextStyle(fontFamily: 'Public Sans', fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

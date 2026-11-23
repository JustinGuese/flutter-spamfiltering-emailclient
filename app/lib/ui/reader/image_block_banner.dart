import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/strings.dart';
import '../../theme/app_type.dart';

/// Slim privacy strip: remote images were not fetched (no tracking pixels).
/// Offers "Load once" and "Always for this sender".
class ImageBlockBanner extends StatelessWidget {
  final VoidCallback onLoadOnce;
  final VoidCallback onAlwaysAllow;

  const ImageBlockBanner({
    super.key,
    required this.onLoadOnce,
    required this.onAlwaysAllow,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    Widget action(String text, VoidCallback onTap, {required bool primary}) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: Text(text, style: AppType.ui(primary ? c.brand.deep : c.textTertiary, size: 12.5, weight: primary ? FontWeight.w700 : FontWeight.w500)),
        );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 40, vertical: 4),
      decoration: BoxDecoration(
        color: c.brand.container.withValues(alpha: 0.55),
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 16, color: c.brand.onContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.remoteImagesBlocked,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.ui(c.brand.onContainer, size: 12.5, weight: FontWeight.w600),
            ),
          ),
          action(AppStrings.loadImagesOnce, onLoadOnce, primary: true),
          if (!narrow) action(AppStrings.alwaysAllowImages, onAlwaysAllow, primary: false),
        ],
      ),
    );
  }
}

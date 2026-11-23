import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import '../../theme/app_theme.dart';

/// 1/2/3 pane responsive layout matching the design brief:
/// - <700dp: single stack
/// - 700-1100dp: two-pane (list 380 | reader flex)
/// - >=1100dp: three-pane (folders 240 | list 380 | reader flex)
class ThreePaneLayout extends StatelessWidget {
  final Widget foldersPane;
  final Widget listPane;
  final Widget readerPane;
  final bool hasSelectedMessage;
  final VoidCallback? onBackToMailbox;

  const ThreePaneLayout({
    super.key,
    required this.foldersPane,
    required this.listPane,
    required this.readerPane,
    this.hasSelectedMessage = false,
    this.onBackToMailbox,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (AppTheme.isThreePane(width)) {
          // Three-pane layout (240 | 380 | flex)
          return Row(
            children: [
              SizedBox(
                width: 240,
                child: foldersPane,
              ),
              VerticalDivider(width: 1, thickness: 1, color: palette.hairline),
              SizedBox(
                width: 380,
                child: listPane,
              ),
              VerticalDivider(width: 1, thickness: 1, color: palette.hairline),
              Expanded(child: readerPane),
            ],
          );
        } else if (AppTheme.isTwoPane(width)) {
          // Two-pane layout (380 | flex)
          return Row(
            children: [
              SizedBox(
                width: 380,
                child: listPane,
              ),
              VerticalDivider(width: 1, thickness: 1, color: palette.hairline),
              Expanded(child: readerPane),
            ],
          );
        } else {
          // Single-pane mobile layout (<700dp)
          if (hasSelectedMessage) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) onBackToMailbox?.call();
              },
              child: readerPane,
            );
          }
          return listPane;
        }
      },
    );
  }
}

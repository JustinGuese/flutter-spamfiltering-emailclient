import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import 'app_brand.dart';

/// Helper utilities for classification colors, density, and icons.
class AppTheme {
  static DfBrand get brand => AppBrand.brand;

  /// Classification color roles adhering to the design brief:
  /// - Inbox/ham: neutral ink (textPrimary)
  /// - Newsletter: accent (verdigris)
  /// - Spam: error (oxblood)
  /// - Unsure: warning
  /// - Learned: success
  static Color classificationColor(BuildContext context, Label label) {
    final palette = context.df.colors;
    switch (label) {
      case Label.spam:
        return palette.error.base;
      case Label.newsletter:
        return palette.accent.base;
      case Label.ham:
      case Label.inbox:
        return palette.textPrimary;
    }
  }

  static IconData classificationIcon(Label label) {
    switch (label) {
      case Label.spam:
        return Icons.report_outlined;
      case Label.newsletter:
        return Icons.newspaper_outlined;
      case Label.ham:
      case Label.inbox:
        return Icons.inbox_outlined;
    }
  }

  /// Breakpoint helpers (<700 single stack, 700-1100 2-pane, >=1100 3-pane)
  static bool isSinglePane(double width) => width < 700;
  static bool isTwoPane(double width) => width >= 700 && width < 1100;
  static bool isThreePane(double width) => width >= 1100;

  /// Row height density
  static const double comfortableRowHeight = 72.0;
  static const double compactRowHeight = 52.0;
}

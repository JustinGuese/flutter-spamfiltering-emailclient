
import 'package:material_ui/material_ui.dart';

/// Type system for "The Ledger Desk": Fraunces for display, Public Sans for UI,
/// JetBrains Mono for addresses, figures and metadata (always tabular).
abstract final class AppType {
  static const String displayFamily = 'Fraunces';
  static const String uiFamily = 'Public Sans';
  static const String monoFamily = 'JetBrains Mono';

  /// Fraunces is a variable font: opsz follows the size so large headings get the
  /// high-contrast cut and small ones stay sturdy; SOFT rounds the terminals.
  static TextStyle display(
    Color color, {
    double size = 28,
    double weight = 600,
    double height = 1.08,
    double letterSpacing = -0.4,
    bool italic = false,
  }) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontVariations: [
          FontVariation('wght', weight),
          FontVariation('opsz', size.clamp(9, 144).toDouble()),
          const FontVariation('SOFT', 40),
        ],
      );

  static TextStyle ui(
    Color color, {
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double height = 1.35,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: uiFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  static TextStyle mono(
    Color color, {
    double size = 11.5,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

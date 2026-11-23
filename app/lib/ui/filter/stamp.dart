import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';

/// Brief rubber-stamp mark animation on classification verdict:
/// scale 1.15 -> 1.0, +-6 deg settle, ~180 ms in brass / oxblood ink.
class LedgerStamp extends StatefulWidget {
  final Label label;
  final int similarCount;
  final VoidCallback? onComplete;

  const LedgerStamp({
    super.key,
    required this.label,
    required this.similarCount,
    this.onComplete,
  });

  @override
  State<LedgerStamp> createState() => _LedgerStampState();
}

class _LedgerStampState extends State<LedgerStamp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _scaleAnimation = Tween<double>(begin: 1.15, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _rotateAnimation = Tween<double>(begin: -0.10, end: -0.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) widget.onComplete?.call();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;
    final stampColor = widget.label == Label.spam ? palette.error.base : palette.brand.base;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotateAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: stampColor, width: 2),
                borderRadius: BorderRadius.circular(6),
                color: stampColor.withValues(alpha: 0.08),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label.name.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: stampColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.similarCount > 0
                        ? AppStrings.verdictMovedFormat.replaceAll('%d', widget.similarCount.toString())
                        : AppStrings.verdictLearnedOnly,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: stampColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

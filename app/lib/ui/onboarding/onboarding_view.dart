import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import 'onboarding_art.dart';

class OnboardingView extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingView({super.key, required this.onComplete});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    (numeral: '01', title: AppStrings.onbPage1Title, body: AppStrings.onbPage1Body, badge: 'EDITORIAL & PRIVATE'),
    (numeral: '02', title: AppStrings.onbPage2Title, body: AppStrings.onbPage2Body, badge: 'ON-DEVICE INTELLIGENCE'),
    (numeral: '03', title: AppStrings.onbPage3Title, body: AppStrings.onbPage3Body, badge: 'ZERO-ID CRYPTOGRAPHY'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _art(int i) => switch (i) {
        0 => const PaperStackArt(),
        1 => const VerdictDemoArt(),
        _ => const HashLedgerArt(),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final last = _currentPage == _pages.length - 1;

    Widget text(int i) {
      final page = _pages[i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Reveal(
            order: 0,
            child: Text(page.numeral, style: AppType.display(c.brand.base.withValues(alpha: 0.55), size: wide ? 120 : 84, weight: 500, height: 0.9, letterSpacing: -4)),
          ),
          SizedBox(height: wide ? 14 : 8),
          _Reveal(
            order: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: c.brand.container, borderRadius: BorderRadius.circular(6)),
              child: Text(page.badge, style: AppType.mono(c.brand.onContainer, size: 10.5, weight: FontWeight.w700, letterSpacing: 1.4)),
            ),
          ),
          const SizedBox(height: 18),
          _Reveal(
            order: 2,
            child: Text(page.title, style: AppType.display(c.textPrimary, size: wide ? 58 : 38, weight: 600, height: 1.02, letterSpacing: -1.4)),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 3,
            child: Text(page.body, style: AppType.ui(c.textSecondary, size: wide ? 18 : 16, height: 1.55)),
          ),
        ],
      );
    }

    Widget artPanel(int i) => Container(
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(context.df.shape.xl),
            border: Border.all(color: c.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: LedgerPaper(
            lineGap: 28,
            opacity: 0.7,
            child: Center(
              child: SizedBox(
                width: wide ? 540 : 330,
                height: wide ? 470 : 290,
                child: FittedBox(fit: BoxFit.contain, child: _art(i)),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(wide ? 56 : 24, 12, wide ? 48 : 12, 0),
              child: Row(children: [
                Text('${_pages[_currentPage].numeral} / 03', style: AppType.mono(c.textTertiary, size: 12, weight: FontWeight.w600, letterSpacing: 1.2)),
                const Spacer(),
                TextButton(
                  onPressed: widget.onComplete,
                  child: Text(AppStrings.onbSkip, style: AppType.ui(c.textTertiary, size: 14, weight: FontWeight.w600)),
                ),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 24, vertical: wide ? 24 : 8),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 5, child: Padding(padding: const EdgeInsets.only(right: 56), child: SingleChildScrollView(child: text(index)))),
                            Expanded(flex: 6, child: artPanel(index)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            text(index),
                            const SizedBox(height: 20),
                            Expanded(child: artPanel(index)),
                          ],
                        ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(wide ? 56 : 24, 16, wide ? 56 : 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _pages.length,
                      (idx) => AnimatedContainer(
                        duration: context.df.motion.normal,
                        curve: context.df.motion.standard,
                        width: idx == _currentPage ? 28 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: idx == _currentPage ? c.brand.base : c.border,
                        ),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!last) {
                        _pageController.nextPage(duration: context.df.motion.medium, curve: context.df.motion.standard);
                      } else {
                        widget.onComplete();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand.deep,
                      foregroundColor: c.textOnBrand,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.pill)),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(last ? AppStrings.onbGetStarted : AppStrings.onbContinue, style: AppType.ui(c.textOnBrand, size: 15, weight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Polish-lens entrance: short rise, staggered by [order].
///
/// Deliberately no opacity fade: where frames are presented slowly (WSLg
/// software rendering) a fade can leave the content stuck invisible.
class _Reveal extends StatelessWidget {
  final int order;
  final Widget child;
  const _Reveal({required this.order, required this.child});

  @override
  Widget build(BuildContext context) {
    final m = context.df.motion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: m.medium + m.stagger * order * 2,
      curve: m.standard,
      builder: (context, t, child) => Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      child: child,
    );
  }
}

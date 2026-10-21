import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';

/// Écran de lancement premium LifeHelm.
///
/// Visuel officiel plein cadre « Votre vie, un seul gouvernail »
/// (assets/brand/launch-premium.webp — kit de marque favicon_lifehelm) :
/// entrée en fondu + zoom très doux, puis route automatique vers
/// l'onboarding (première utilisation) ou le cockpit. Un appui passe
/// directement — la premium attitude n'exclut pas la rapidité.
class PremiumSplashScreen extends StatefulWidget {
  const PremiumSplashScreen({super.key});

  @override
  State<PremiumSplashScreen> createState() => _PremiumSplashScreenState();
}

class _PremiumSplashScreenState extends State<PremiumSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _zoom;
  bool _left = false;

  static const _hold = Duration(milliseconds: 2100);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..forward();
    _fade = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.28, curve: Curves.easeOut));
    _zoom = Tween(begin: 1.0, end: 1.045).animate(CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 1, curve: Curves.easeOut)));
    Future.delayed(_hold, _leave);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _leave() {
    if (!mounted || _left) return;
    setState(() => _left = true);
    // Le redirect global du routeur envoie vers /onboarding lors de la
    // première utilisation, vers le cockpit sinon — une seule vérité.
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Ivoire officiel — visible pendant le court instant où le visuel
      // (fond blanc → bleu très pâle) se charge.
      backgroundColor: LHColors.ivoire,
      body: GestureDetector(
        onTap: _leave,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => FadeTransition(
            opacity: _fade,
            child: Transform.scale(scale: _zoom.value, child: child),
          ),
          child: const SizedBox.expand(
            child: Image(
              image: AssetImage('assets/brand/launch-premium.webp'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

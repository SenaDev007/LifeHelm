import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/finance')) return 1;
    if (location.startsWith('/goals')) return 2;
    if (location.startsWith('/routines')) return 3;
    if (location.startsWith('/health')) return 4;
    if (location.startsWith('/ai')) return 5;
    if (location.startsWith('/profile') || location.startsWith('/settings')) return 6;
    return 0; // home
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _currentIndex(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/'); break;
            case 1: context.go('/finance'); break;
            case 2: context.go('/goals'); break;
            case 3: context.go('/routines'); break;
            case 4: context.go('/health'); break;
            case 5: context.go('/ai'); break;
            case 6: context.go('/profile'); break;
          }
        },
        type: NavigationBarType.fixed,
        backgroundColor: LifeHelmColors.bgCard,
        indicatorColor: LifeHelmColors.primary.withValues(alpha: 0.1),
        selectedItemColor: LifeHelmColors.primary,
        unselectedItemColor: LifeHelmColors.textTertiary,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Finance'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Objectifs'),
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Routines'),
          NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite), label: 'Santé'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'HELM AI'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

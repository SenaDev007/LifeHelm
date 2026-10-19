import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import 'widgets.dart';

/// Shell principal — 5 destinations : Accueil, Finances, Activités, Agenda, Plus
/// (CDC §4.5 Navigation principale).
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          initialLocation: i == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Finances',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: 'Activités',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps_rounded),
            label: 'Plus',
          ),
        ],
      ),
    );
  }
}

/// Écran de chargement initial (base en cours d'ouverture).
class BootSplash extends StatelessWidget {
  const BootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LHColors.noir,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const HelmMark(size: 72),
          const SizedBox(height: LHSpacing.lg),
          Text('LifeHelm',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: LHColors.texteClair,
                  fontFamily: LHFonts.titres,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: LHSpacing.xl),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
                color: LHColors.or, strokeWidth: 2.5),
          ),
        ]),
      ),
    );
  }
}

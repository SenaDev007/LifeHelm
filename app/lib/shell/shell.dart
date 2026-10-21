import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/push/push_service.dart';
import '../features/ai/briefing.dart' show briefingOpenRequest;

/// Shell principal — 5 destinations : Accueil, Finances, Activités, Agenda, Plus
/// (CDC §4.5 Navigation principale).
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Amorçage idempotent des notifications push du briefing (D17.6) :
    // restaure les notifications programmées, ré-enregistre l'appareil si
    // besoin et écoute les taps (→ cockpit + feuille briefing).
    Future.microtask(() {
      ref.read(pushProvider.notifier).boot(onOpenBriefing: () {
        // Ramène au cockpit puis pose le signal d'ouverture de la feuille
        // (le cockpit consomme le signal au build ou à l'écoute).
        ref.read(briefingOpenRequest.notifier).state = true;
        context.go('/');
      });
    });

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

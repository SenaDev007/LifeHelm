// Routing principal
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/home/screens/main_shell.dart';
import '../features/finance/screens/finance_screen.dart';
import '../features/finance/screens/transactions_screen.dart';
import '../features/finance/screens/add_transaction_screen.dart';
import '../features/finance/screens/savings_goals_screen.dart';
import '../features/finance/screens/tontines_screen.dart';
import '../features/finance/screens/debts_screen.dart';
import '../features/finance/screens/bills_screen.dart';
import '../features/finance/screens/accounts_screen.dart';
import '../features/goals/screens/goals_screen.dart';
import '../features/routines/screens/routines_screen.dart';
import '../features/health/screens/health_screen.dart';
import '../features/ai/screens/ai_screen.dart';
import '../features/accessible/screens/accessible_home_screen.dart';
import '../features/accessible/screens/accessible_vente_screen.dart';
import '../features/accessible/screens/accessible_depense_screen.dart';
import '../features/accessible/screens/accessible_bilan_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../services/api_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isOnAuth = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      final isOnOnboarding = state.matchedLocation == '/onboarding';
      final isOnAccessibleOnboarding = state.matchedLocation == '/accessible-onboarding';

      if (authState.status == AuthStatus.unknown) return null;

      if (!isLoggedIn && !isOnAuth) return '/login';
      if (isLoggedIn && isOnAuth) {
        final user = authState.user;
        if (user == null) return '/login';
        final onboarded = user['onboarded'] as bool? ?? false;
        final appMode = user['appMode'] as String? ?? 'STANDARD';
        final accessibleOnboarded = user['accessibleOnboarded'] as bool? ?? false;
        if (!onboarded) return '/onboarding';
        if (appMode == 'ACCESSIBLE' && !accessibleOnboarded) return '/accessible-onboarding';
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/accessible-onboarding',
        builder: (context, state) => const OnboardingScreen(accessible: true),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/finance', builder: (context, state) => const FinanceScreen()),
          GoRoute(path: '/finance/transactions', builder: (context, state) => const TransactionsScreen()),
          GoRoute(path: '/finance/transactions/add', builder: (context, state) {
            final txType = state.uri.queryParameters['type'] ?? 'EXPENSE';
            return AddTransactionScreen(type: txType);
          }),
          GoRoute(path: '/finance/accounts', builder: (context, state) => const AccountsScreen()),
          GoRoute(path: '/finance/savings', builder: (context, state) => const SavingsGoalsScreen()),
          GoRoute(path: '/finance/tontines', builder: (context, state) => const TontinesScreen()),
          GoRoute(path: '/finance/debts', builder: (context, state) => const DebtsScreen()),
          GoRoute(path: '/finance/bills', builder: (context, state) => const BillsScreen()),
          GoRoute(path: '/goals', builder: (context, state) => const GoalsScreen()),
          GoRoute(path: '/routines', builder: (context, state) => const RoutinesScreen()),
          GoRoute(path: '/health', builder: (context, state) => const HealthScreen()),
          GoRoute(path: '/ai', builder: (context, state) => const AIScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ],
      ),
      // Mode Accessible (sans bottom nav)
      GoRoute(path: '/accessible', builder: (context, state) => const AccessibleHomeScreen()),
      GoRoute(path: '/accessible/vente', builder: (context, state) => const AccessibleVenteScreen()),
      GoRoute(path: '/accessible/depense', builder: (context, state) => const AccessibleDepenseScreen()),
      GoRoute(path: '/accessible/bilan', builder: (context, state) => const AccessibleBilanScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(child: Text('Erreur: ${state.error}')),
    ),
  );
});

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/agenda/agenda.dart';
import 'features/auth/auth.dart';
import 'features/cockpit/cockpit.dart';
import 'features/contacts/contacts.dart';
import 'features/finance/finance.dart';
import 'features/finance/finance_screens.dart';
import 'features/habits/habits.dart';
import 'features/messaging/messaging.dart';
import 'features/more/more.dart';
import 'features/notes/notes.dart';
import 'features/notifications/notifications.dart';
import 'features/onboarding/onboarding.dart';
import 'features/onboarding/cgu.dart';
import 'features/profile/profile.dart';
import 'features/projects/projects.dart';
import 'features/search/search.dart';
import 'features/statistics/statistics.dart';
import 'features/tasks/tasks.dart';
import 'features/wellbeing/wellbeing.dart';
import 'features/ai/assistant.dart';
import 'features/ai/preferences.dart';
import 'features/career/career.dart';
import 'features/finance/loans.dart';
import 'main.dart' show bootState;
import 'shell/shell.dart';
import 'shell/splash.dart';

/// Routeur LifeHelm — navigation principale à 5 destinations (CDC §4.5)
/// + routes détaillées par module.
final router = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    // L'écran de lancement premium gère lui-même la suite (tap ou délai).
    if (state.matchedLocation == '/splash') return null;
    final inOnboarding = state.matchedLocation == '/onboarding';
    if (!bootState.onboarded && !inOnboarding) return '/onboarding';
    if (bootState.onboarded && inOnboarding) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const PremiumSplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),

    // ── Shell principal : 5 onglets ──
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScreen(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const CockpitScreen(),
            routes: [
              GoRoute(
                path: 'search',
                builder: (context, state) => const SearchScreen(),
              ),
              GoRoute(
                path: 'notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/finance',
            builder: (context, state) => const FinanceScreen(),
            routes: [
              GoRoute(
                path: 'transaction/new',
                builder: (context, state) => TransactionEditScreen(
                  initialType: state.uri.queryParameters['type'],
                  initialAccountId:
                      state.uri.queryParameters['account'],
                ),
              ),
              GoRoute(
                path: 'account/:id',
                builder: (context, state) =>
                    AccountDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'budgets',
                builder: (context, state) => const BudgetsScreen(),
              ),
              GoRoute(
                path: 'dues',
                builder: (context, state) => const DuesScreen(),
              ),
              GoRoute(
                path: 'loans',
                builder: (context, state) => const LoansScreen(),
              ),
              GoRoute(
                path: 'statistics',
                builder: (context, state) => const StatisticsScreen(),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/activities',
            builder: (context, state) => const TasksScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => TaskEditScreen(
                  parentId: state.uri.queryParameters['parent'],
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    TaskEditScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/agenda',
            builder: (context, state) => const AgendaScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const EventEditScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    EventEditScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/more',
            builder: (context, state) => const MoreScreen(),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
              GoRoute(
                path: 'spaces',
                builder: (context, state) => const SpacesScreen(),
              ),
              GoRoute(
                path: 'sync',
                builder: (context, state) => const SyncScreen(),
              ),
              GoRoute(
                path: 'notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
              GoRoute(
                path: 'notification-preferences',
                builder: (context, state) =>
                    const NotificationPrefsScreen(),
              ),
              GoRoute(
                path: 'search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
        ]),
      ],
    ),

    // ── Notes (D06) ──
    GoRoute(
      path: '/notes',
      builder: (context, state) => const NotesScreen(),
      routes: [
        GoRoute(
          path: 'trash',
          builder: (context, state) => const TrashScreen(),
        ),
        GoRoute(
          path: 'new',
          builder: (context, state) => const NoteEditorScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              NoteEditorScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),

    // ── Projets & objectifs (D07) ──
    GoRoute(
      path: '/projects',
      builder: (context, state) => const ProjectsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              ProjectDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/goals',
      builder: (context, state) => const GoalsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              GoalDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),

    // ── Habitudes & routines (D08) ──
    GoRoute(
      path: '/habits',
      builder: (context, state) => const HabitsScreen(),
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) =>
              const HabitDetailScreen(id: 'new'),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              HabitDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/routines',
      builder: (context, state) => const RoutinesScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              RoutineDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),

    // ── Bien-être (D09) ──
    GoRoute(
      path: '/wellbeing',
      builder: (context, state) => const WellbeingScreen(),
      routes: [
        GoRoute(
          path: 'review',
          builder: (context, state) => const DailyReviewScreen(),
        ),
      ],
    ),

    // ── Carrière (D10) ──
    GoRoute(
      path: '/career',
      builder: (context, state) => const CareerScreen(),
    ),

    // ── Contacts (D11) ──
    GoRoute(
      path: '/contacts',
      builder: (context, state) => const ContactsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              ContactDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),

    // ── Messagerie (D12) ──
    GoRoute(
      path: '/messages',
      builder: (context, state) => const ConversationsScreen(),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) =>
          ChatScreen(id: state.pathParameters['id']!),
    ),

    // ── Notifications & recherche (D13/D14) ──
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/notification-preferences',
      builder: (context, state) => const NotificationPrefsScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),

    // ── HELM AI — assistant central (D17, plein écran) ──
    GoRoute(
      path: '/assistant',
      builder: (context, state) => AiAssistantScreen(
        moduleContext: state.uri.queryParameters['module'],
      ),
    ),

    // ── HELM AI — préférences (autonomie, périmètre, transparence) ──
    GoRoute(
      path: '/ai-preferences',
      builder: (context, state) => const AiPreferencesScreen(),
    ),

    // ── Paramètres, espaces, sync ──
    GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen()),
    GoRoute(
        path: '/spaces', builder: (context, state) => const SpacesScreen()),
    GoRoute(
        path: '/sync', builder: (context, state) => const SyncScreen()),

    // ── Compte & authentification (plein écran, hors shell) ──
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginScreen(
        loggedOut: state.uri.queryParameters['loggedOut'] == '1',
      ),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => ResetPasswordScreen(
        initialToken: state.uri.queryParameters['token'],
      ),
    ),
    GoRoute(
      path: '/account',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/sessions',
      builder: (context, state) => const SessionsScreen(),
    ),
    GoRoute(
      path: '/security',
      builder: (context, state) => const SecurityScreen(),
    ),

    // ── Alias pratiques utilisés par les modules (chemins absolus) ──
    GoRoute(
      path: '/task/new',
      builder: (context, state) =>
          TaskEditScreen(parentId: state.uri.queryParameters['parent']),
    ),
    GoRoute(
      path: '/task/:id',
      builder: (context, state) =>
          TaskEditScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/event/new',
      builder: (context, state) => const EventEditScreen(),
    ),
    GoRoute(
      path: '/event/:id',
      builder: (context, state) =>
          EventEditScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/transaction/new',
      builder: (context, state) => TransactionEditScreen(
        initialType: state.uri.queryParameters['type'],
        initialAccountId: state.uri.queryParameters['account'],
      ),
    ),
    GoRoute(
      path: '/account/:id',
      builder: (context, state) =>
          AccountDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
        path: '/budgets',
        builder: (context, state) => const BudgetsScreen()),
    GoRoute(
        path: '/dues', builder: (context, state) => const DuesScreen()),
    GoRoute(
        path: '/loans', builder: (context, state) => const LoansScreen()),
    GoRoute(
        path: '/statistics',
        builder: (context, state) => const StatisticsScreen()),
    GoRoute(
        path: '/cgu', builder: (context, state) => const CguScreen()),
    GoRoute(
      path: '/note/new',
      builder: (context, state) => NoteEditorScreen(
          folderId: state.uri.queryParameters['folder']),
    ),
    GoRoute(
      path: '/note/:id',
      builder: (context, state) =>
          NoteEditorScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/project/:id',
      builder: (context, state) =>
          ProjectDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/goal/:id',
      builder: (context, state) =>
          GoalDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/habit/:id',
      builder: (context, state) =>
          HabitDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/routine/:id',
      builder: (context, state) =>
          RoutineDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/contact/:id',
      builder: (context, state) =>
          ContactDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) =>
          ChatScreen(id: state.pathParameters['id']!),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Page introuvable')),
    body: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.explore_off, size: 56, color: LHColorsNeutral.neutre),
        const SizedBox(height: 12),
        Text('Cette page n\'existe pas : ${state.uri}'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Retour à l\'accueil'),
        ),
      ]),
    ),
  ),
);

// Petit alias de couleur pour l'écran d'erreur (évite un import de plus).
class LHColorsNeutral {
  static const Color neutre = Color(0xFF64748B); // gris ardoise — palette officielle
}

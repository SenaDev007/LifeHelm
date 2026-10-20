import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart' as dbm;
import '../../core/net/api_client.dart';
import '../../core/net/sync_service.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../main.dart' show bootState;

// ═══════════════════════════ ÉCRAN : PLUS ═══════════════════════════

class _ModuleEntry {
  const _ModuleEntry(this.route, this.label, this.subtitle, this.icon,
      this.moduleKey);
  final String route;
  final String label;
  final String subtitle;
  final IconData icon;
  final String moduleKey;
}

const _modules = [
  _ModuleEntry('/notes', 'Notes', 'Éditeur riche, dossiers, versions',
      Icons.edit_note_rounded, 'notes'),
  _ModuleEntry('/projects', 'Projets', 'Étapes, jalons, progression',
      Icons.flag_rounded, 'projects'),
  _ModuleEntry('/goals', 'Objectifs', 'Indicateurs et bilans',
      Icons.track_changes, 'goals'),
  _ModuleEntry('/habits', 'Habitudes', 'Séries et routines',
      Icons.repeat_rounded, 'habits'),
  _ModuleEntry('/routines', 'Routines', 'Séquences du quotidien',
      Icons.timeline_rounded, 'habits'),
  _ModuleEntry('/wellbeing', 'Bien-être', 'Journal et bilan quotidien',
      Icons.self_improvement_rounded, 'habits'),
  _ModuleEntry('/career', 'Carrière', 'Compétences, parcours, portfolio',
      Icons.work_outline, 'goals'),
  _ModuleEntry('/contacts', 'Contacts', 'Carnets par espace',
      Icons.people_outline, 'contacts'),
  _ModuleEntry('/messages', 'Messagerie', 'Conversations internes',
      Icons.chat_bubble_outline_rounded, 'messages'),
  _ModuleEntry('/notifications', 'Notifications', 'Centre d\'alertes',
      Icons.notifications_none_rounded, 'tasks'),
  _ModuleEntry('/search', 'Recherche', 'Tous vos contenus',
      Icons.search, 'notes'),
];

/// Onglet « Plus » — accès aux modules secondaires (CDC §4.5).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final space = ref.watch(activeSpaceProvider).valueOrNull;
    final pendingOps = ref.watch(pendingOpCountProvider).valueOrNull ?? 0;
    final unread = ref.watch(unreadNotifCountProvider).valueOrNull ?? 0;
    final syncState = ref.watch(syncStateProvider).valueOrNull;

    return Scaffold(
      appBar: LhAppBarLike(title: 'Plus'),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        // ── Compte & synchronisation (authentification optionnelle) ──
        const _AccountSection(),
        // Carte espace actif
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: LHCard(
            onTap: () => context.push('/spaces'),
            child: Row(children: [
              InitialsAvatar(
                  name: space?.name ?? '?',
                  color: spaceColor(space?.type ?? 'PERSONAL'),
                  size: 46),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(space?.name ?? '…',
                          style: theme.textTheme.titleMedium),
                      Text(
                        '${spaceTypeLabel(space?.type ?? '')} — gérer les membres et les rôles',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            ]),
          ),
        ),
        // Synchronisation (état réel, jamais mensonger)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: LHCard(
            onTap: () => context.push('/sync'),
            accent: syncState == null
                ? LHColors.neutre
                : syncState.pending > 0 || syncState.conflicts > 0
                    ? LHColors.or
                    : LHColors.emeraudeClair,
            child: Row(children: [
              Icon(
                syncState == null
                    ? Icons.cloud_off_outlined
                    : !syncState.connected
                        ? Icons.cloud_off_outlined
                        : syncState.running
                            ? Icons.sync_rounded
                            : syncState.pending > 0 || syncState.conflicts > 0
                                ? Icons.cloud_upload_outlined
                                : Icons.cloud_done_outlined,
                color: syncState != null && syncState.connected
                    ? (syncState.pending > 0 || syncState.conflicts > 0
                        ? LHColors.or
                        : LHColors.emeraudeClair)
                    : LHColors.neutre,
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Synchronisation',
                          style: theme.textTheme.titleSmall),
                      Text(
                        _syncWording(syncState, pendingOps),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
              ),
            ]),
          ),
        ),
        SectionHeader('Modules', overline: 'Toute votre vie'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              for (final m in _modules)
                _ModuleCard(
                    entry: m,
                    badge: m.route == '/notifications' && unread > 0
                        ? '$unread'
                        : null),
            ],
          ),
        ),
        SectionHeader('Application', overline: 'Réglages'),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Paramètres'),
          subtitle: const Text('Thème, cockpit, budgets, confidentialité'),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: LHColors.neutre),
          onTap: () => context.push('/settings'),
        ),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Espaces'),
          subtitle: const Text('Personnel, famille, professionnel'),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: LHColors.neutre),
          onTap: () => context.push('/spaces'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('File de synchronisation'),
          subtitle: Text(_syncWording(syncState, pendingOps)),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: LHColors.neutre),
          onTap: () => context.push('/sync'),
        ),
      ]),
    );
  }

  /// Libellé d'état réel (jamais « Tout est synchronisé » hors connexion).
  static String _syncWording(LhSyncState? s, int pendingOps) {
    if (s == null) return 'État inconnu — ouvrez l\'écran de synchronisation';
    if (!s.connected) {
      return pendingOps > 0
          ? 'Hors ligne — $pendingOps opération${pendingOps > 1 ? 's' : ''} en attente locale'
          : 'Hors ligne — données locales uniquement';
    }
    if (s.conflicts > 0) {
      return '${s.conflicts} conflit${s.conflicts > 1 ? 's' : ''} à résoudre';
    }
    if (s.running) return 'Synchronisation en cours…';
    if (pendingOps > 0) {
      return '$pendingOps opération${pendingOps > 1 ? 's' : ''} en attente d\'envoi';
    }
    if (s.lastError != null) return 'Dernière erreur : ${s.lastError}';
    return s.lastSyncAt == null
        ? 'Jamais synchronisé'
        : 'À jour — ${fmt.timeAgo(s.lastSyncAt!)}';
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.entry, this.badge});
  final _ModuleEntry entry;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () => context.push(entry.route),
      borderRadius: BorderRadius.circular(LHRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(LHRadius.lg),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.7)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(entry.icon,
                    size: 22,
                    color: isDark ? LHColors.or : LHColors.orDeep),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: const BoxDecoration(
                        color: LHColors.erreur, shape: BoxShape.circle),
                    child: Text(badge!,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(entry.label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                entry.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
      ),
    );
  }
}

/// Section « Compte & synchronisation » : CTA anonyme (offline-first, le
/// compte est optionnel) ou carte profil + entrées de gestion du compte.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await lhConfirm(
      context,
      title: 'Se déconnecter ?',
      message:
          'Vos données restent sur cet appareil — seule la sauvegarde en ligne est interrompue.',
      confirmLabel: 'Se déconnecter',
    );
    if (!ok) return;
    final store = ref.read(tokenStoreProvider);
    final session = await store.load();
    try {
      if (session != null) {
        await ref.read(apiClientProvider).logout(session.refreshToken);
      }
    } catch (_) {
      // Le serveur est injoignable : la déconnexion locale prime.
    }
    await store.clear();
    if (context.mounted) {
      // Déconnexion effective : retour à l'écran de connexion (et non au
      // shell) — impossible de continuer à naviguer « déconnecté ».
      context.go('/login?loggedOut=1');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final syncState = ref.watch(syncStateProvider).valueOrNull;

    // ── Anonyme : appel à l'action, tout reste utilisable sans compte ──
    if (!session.isConnected || session.user == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: LHCard(
          onTap: () => context.push('/login'),
          accent: theme.brightness == Brightness.dark
              ? LHColors.or
              : LHColors.orDeep,
          child: Row(children: [
            Icon(Icons.cloud_outlined,
                color: theme.brightness == Brightness.dark
                    ? LHColors.or
                    : LHColors.orDeep),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Se connecter ou créer un compte',
                        style: theme.textTheme.titleSmall),
                    Text(
                      'Retrouvez vos espaces sur vos autres appareils',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: LHColors.neutre),
          ]),
        ),
      );
    }

    // ── Connecté : profil + gestion ──
    final user = session.user!;
    final (badge, badgeColor) = _statusBadge(syncState);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Compte & synchronisation',
          overline: 'Sauvegarde multi-appareils'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LHCard(
          onTap: () => context.push('/account'),
          child: Row(children: [
            InitialsAvatar(name: user.displayName, size: 46),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(user.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(label: badge, color: badgeColor, small: true),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      user.email ?? user.phone ?? 'Compte LifeHelm',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
          ]),
        ),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.person_outline),
        title: const Text('Mon profil'),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: LHColors.neutre),
        onTap: () => context.push('/account'),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.devices_outlined),
        title: const Text('Sessions & appareils'),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: LHColors.neutre),
        onTap: () => context.push('/sessions'),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Sécurité & 2FA'),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: LHColors.neutre),
        onTap: () => context.push('/security'),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_sync_outlined),
        title: const Text('Synchronisation'),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: LHColors.neutre),
        onTap: () => context.push('/sync'),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.logout, color: LHColors.erreur),
        title: Text('Se déconnecter',
            style: TextStyle(color: LHColors.erreur)),
        onTap: () => _logout(context, ref),
      ),
    ]);
  }

  /// Badge d'état réel du compte selon l'état de synchronisation.
  (String, Color) _statusBadge(LhSyncState? s) {
    if (s == null || !s.connected) return ('Hors ligne', LHColors.neutre);
    if (s.conflicts > 0) return ('Conflits', LHColors.alerte);
    if (s.pending > 0) return ('En attente', LHColors.financeAttente);
    if (s.lastError != null) return ('Erreur', LHColors.erreur);
    if (s.lastSyncAt != null) return ('Synchronisé', LHColors.emeraudeClair);
    return ('Jamais synchronisé', LHColors.neutre);
  }
}

/// AppBar locale (évite la dépendance circulaire avec le shell).
class LhAppBarLike extends StatelessWidget implements PreferredSizeWidget {
  const LhAppBarLike({super.key, this.title});
  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Text(
        title ?? '',
        style: theme.textTheme.titleLarge,
      ),
      actions: [
        IconButton(
          tooltip: 'Recherche',
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/search'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ═══════════════════════════ ÉCRAN : PARAMÈTRES ═══════════════════════════

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        SectionHeader('Apparence', overline: 'Thèmes'),
        // Thème : clair / sombre / système (CDC §4.3)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'light', label: Text('Clair'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(
                  value: 'dark', label: Text('Sombre'), icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(
                  value: 'system', label: Text('Système'), icon: Icon(Icons.settings_suggest)),
            ],
            selected: {
              settings['themeMode'] ?? 'dark'
            },
            onSelectionChanged: (s) => db.setSetting('themeMode', s.first),
          ),
        ),
        SectionHeader('Cockpit', overline: 'Personnalisation'),
        ListTile(
          title: const Text('Fenêtre des échéances'),
          subtitle: Text(
              '${int.tryParse(settings['upcomingWindowDays'] ?? '7') ?? 7} jours — les priorités et l\'agenda proche regardent cette fenêtre'),
          trailing: DropdownButton<int>(
            value: int.tryParse(settings['upcomingWindowDays'] ?? '7') ?? 7,
            items: [
              for (final d in [3, 5, 7, 14, 30])
                DropdownMenuItem(value: d, child: Text('$d j')),
            ],
            onChanged: (v) =>
                v != null ? db.setSetting('upcomingWindowDays', '$v') : null,
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.savings_outlined),
          title: const Text('Résumé financier au cockpit'),
          subtitle: const Text(
              'Affiche le patrimoine consolidé sur l\'accueil (selon les permissions de l\'espace).'),
          value: (settings['showFinanceSummary'] ?? 'true') == 'true',
          onChanged: (v) => db.setSetting('showFinanceSummary', '$v'),
        ),
        SectionHeader('Finances', overline: 'Alertes'),
        ListTile(
          title: const Text('Seuil d\'alerte des budgets'),
          subtitle: Text(
              'Alerte à ${((double.tryParse(settings['budgetAlertThreshold'] ?? '0.8') ?? 0.8) * 100).round()} % de l\'enveloppe consommée'),
          trailing: Slider(
            value: double.tryParse(settings['budgetAlertThreshold'] ?? '0.8') ??
                0.8,
            min: 0.5,
            max: 1.0,
            divisions: 10,
            label:
                '${(((double.tryParse(settings['budgetAlertThreshold'] ?? '0.8') ?? 0.8) * 100).round())} %',
            onChanged: (v) => db.setSetting('budgetAlertThreshold', '$v'),
          ),
        ),
        SectionHeader('Confidentialité & données', overline: 'Vos droits'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Données locales'),
          subtitle: const Text(
              'Tout est stocké sur l\'appareil (SQLite) et journalisé en attente de synchronisation. Aucun envoi externe sans compte.'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('File de synchronisation'),
          subtitle: Text(
              '${ref.watch(pendingOpCountProvider).valueOrNull ?? 0} opérations en attente'),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: LHColors.neutre),
          onTap: () => context.push('/sync'),
        ),
        ListTile(
          leading:
              const Icon(Icons.delete_forever_outlined, color: LHColors.erreur),
          title: Text('Effacer les données locales',
              style: const TextStyle(color: LHColors.erreur)),
          subtitle: const Text(
              'Supprime tout le contenu de l\'appareil (espaces, jetons, réglages) puis relance l\'accueil.'),
          onTap: () => _wipeLocalData(context, ref),
        ),
        SectionHeader('Avancé', overline: 'Connexion au serveur'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LabeledField(
            label: 'URL du serveur (API)',
            child: _ServerUrlField(initial: settings['apiBaseUrl']),
          ),
        ),
        const SizedBox(height: LHSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Web : « /api/v1 » (même origine que l\'application web). '
            'Mobile : par défaut le serveur de production '
            'https://lifehelm-production.up.railway.app/api/v1 — modifiable ci-dessus.',
            style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        SectionHeader('À propos', overline: 'LifeHelm'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'LifeHelm v0.1.0 — Life Management System.\n'
            'Implémentation Flutter offline-first des Dossiers 01 à 14 du cahier des charges. '
            'Backend NestJS/PostgreSQL à brancher via l\'API de synchronisation (D01.4).',
            style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  /// Effacement complet des données locales (double confirmation) :
  /// contenu de toutes les tables + session + réglages, puis retour à
  /// l'écran d'accueil (onboarding).
  Future<void> _wipeLocalData(BuildContext context, WidgetRef ref) async {
    final ok1 = await lhConfirm(
      context,
      title: 'Effacer les données locales ?',
      message:
          'Tous les espaces, tâches, finances, notes et réglages de cet appareil seront supprimés. La session (jetons) est également effacée.',
      confirmLabel: 'Continuer',
      destructive: true,
    );
    if (!ok1 || !context.mounted) return;
    final ok2 = await lhConfirm(
      context,
      title: 'Dernière confirmation',
      message:
          'Cette action est irréversible. Les données non synchronisées seront perdues définitivement.',
      confirmLabel: 'Tout effacer',
      destructive: true,
    );
    if (!ok2) return;

    final db = ref.read(dbProvider);
    // Purge de toutes les tables (contenu + réglages + file de sync).
    for (final table in db.allTables) {
      await db.delete(table).go();
    }
    // Session effacée elle aussi (jetons + profil).
    await ref.read(tokenStoreProvider).clear();
    bootState.onboarded = false;
    if (context.mounted) {
      lhToast(context, 'Données locales effacées.');
      context.go('/onboarding');
    }
  }
}

/// Champ « URL du serveur » : validation http(s):// ou chemin relatif
/// commençant par « / », puis invalidation du cache de connexion.
class _ServerUrlField extends ConsumerStatefulWidget {
  const _ServerUrlField({this.initial});

  final String? initial;

  @override
  ConsumerState<_ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends ConsumerState<_ServerUrlField> {
  late final _controller =
      TextEditingController(text: widget.initial ?? ApiClient.defaultBaseUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _valid(String v) {
    final t = v.trim();
    if (t.isEmpty) return false;
    return t.startsWith(RegExp(r'https?://')) ||
        (t.startsWith('/') && !t.startsWith('//'));
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (!_valid(value)) {
      lhToast(context,
          'URL invalide — https://… ou chemin relatif commençant par « / ».');
      return;
    }
    await ref.read(dbProvider).setSetting('apiBaseUrl', value);
    ref.read(apiClientProvider).invalidateBaseUrl();
    if (mounted) lhToast(context, 'Redémarrage de la connexion.');
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
              hintText: '/api/v1', prefixIcon: Icon(Icons.dns_outlined)),
        ),
      ),
      const SizedBox(width: LHSpacing.sm),
      FilledButton.tonal(
        onPressed: _save,
        child: const Text('Enregistrer'),
      ),
    ]);
  }
}

// ═══════════════════════════ ÉCRAN : ESPACES ═══════════════════════════

/// Gestion des espaces, membres et rôles (CDC §5).
class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(spacesProvider);
    final activeId = ref.watch(activeSpaceIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Espaces')),
      body: spacesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: '$e'),
        data: (spaces) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            for (final s in spaces)
              Column(children: [
                ListTile(
                  leading: InitialsAvatar(
                      name: s.name, color: spaceColor(s.type), size: 44),
                  title: Text(s.name,
                      style: theme.textTheme.titleMedium),
                  subtitle: Text(spaceTypeLabel(s.type)),
                  trailing: s.id == activeId
                      ? const StatusChip(
                          label: 'Actif', color: LHColors.emeraudeClair)
                      : TextButton(
                          onPressed: () => ref
                              .read(activeSpaceIdProvider.notifier)
                              .set(s.id),
                          child: const Text('Activer'),
                        ),
                ),
                _MembersList(spaceId: s.id, isActive: s.id == activeId),
                const Divider(height: 1, indent: 16, endIndent: 16),
              ]),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Les données sont isolées par espace, sauf partage explicite (CDC §2.1). '
                'Les rôles OWNER, ADMIN, MANAGER, MEMBER et VIEWER seront appliqués côté serveur à chaque opération.',
                style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersList extends ConsumerWidget {
  const _MembersList({required this.spaceId, required this.isActive});
  final String spaceId;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider(spaceId));
    final theme = Theme.of(context);

    return membersAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (members) => Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 8),
        child: Column(children: [
          for (final m in members)
            ListTile(
              dense: true,
              leading: InitialsAvatar(name: m.displayName, size: 30),
              title: Text(m.displayName,
                  style: theme.textTheme.bodyMedium),
              trailing: Text(
                switch (m.role) {
                  'OWNER' => 'Propriétaire',
                  'ADMIN' => 'Admin',
                  'MANAGER' => 'Gestionnaire',
                  'VIEWER' => 'Observateur',
                  _ => 'Membre',
                },
                style: theme.textTheme.labelMedium?.copyWith(
                    color: m.role == 'OWNER'
                        ? (theme.brightness == Brightness.dark
                            ? LHColors.or
                            : LHColors.orDeep)
                        : theme.colorScheme.onSurfaceVariant),
              ),
              subtitle: m.email != null ? Text(m.email!) : null,
            ),
        ]),
      ),
    );
  }
}

final membersProvider =
    StreamProvider.family<List<dbm.SpaceMember>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchMembers(spaceId));

// ═══════════════════════════ ÉCRAN : MON PROFIL ═══════════════════════════

/// Profil du compte : lecture (le MVP n'expose pas de mise à jour serveur du
/// profil) + changement de mot de passe via POST /auth/password.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_new.text.length < 8) {
      setState(() => _error =
          'Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(apiClientProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() => _info = 'Mot de passe modifié.');
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final user = session.user;

    if (!session.isConnected || user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon profil')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          message: 'Aucun compte connecté',
          hint: 'Créez un compte pour activer la synchronisation.',
          action: FilledButton.icon(
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Activer la synchronisation'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(sessionProvider.notifier).refreshUser(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: LHSpacing.md),
          Center(
            child: Column(children: [
              InitialsAvatar(name: user.displayName, size: 72),
              const SizedBox(height: LHSpacing.md),
              Text(user.displayName, style: theme.textTheme.titleLarge),
              Text(
                'Membre depuis ${fmt.formatMonthYear(user.createdAt)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
          SectionHeader('Identité', overline: 'Lecture seule'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Prénom'),
            subtitle: Text(user.firstName.isEmpty ? '—' : user.firstName),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Nom'),
            subtitle: Text(user.lastName?.isEmpty ?? true ? '—' : user.lastName!),
          ),
          SectionHeader('Contact', overline: 'Coordonnées du compte'),
          if (user.email != null)
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(user.email!),
              subtitle: const Text('Courriel'),
              trailing: StatusChip(
                label: user.emailVerifiedAt != null
                    ? 'Vérifié'
                    : 'Non vérifié',
                color: user.emailVerifiedAt != null
                    ? LHColors.emeraudeClair
                    : LHColors.alerte,
                small: true,
              ),
            ),
          if (user.phone != null)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(user.phone!),
              subtitle: const Text('Téléphone'),
              trailing: StatusChip(
                label: user.phoneVerifiedAt != null
                    ? 'Vérifié'
                    : 'Non vérifié',
                color: user.phoneVerifiedAt != null
                    ? LHColors.emeraudeClair
                    : LHColors.alerte,
                small: true,
              ),
            ),
          if (user.email == null && user.phone == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Aucune coordonnée renseignée.'),
            ),
          SectionHeader('Sécurité', overline: 'Protection du compte'),
          ListTile(
            leading: Icon(
              user.twoFactorEnabled
                  ? Icons.verified_user_outlined
                  : Icons.gpp_maybe_outlined,
              color: user.twoFactorEnabled
                  ? LHColors.emeraudeClair
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: const Text('Double authentification (2FA)'),
            subtitle: Text(user.twoFactorEnabled
                ? 'Activée — un code TOTP est demandé à la connexion.'
                : 'Désactivée.'),
            trailing: TextButton(
              onPressed: () => context.push('/security'),
              child: const Text('Gérer'),
            ),
          ),
          SectionHeader('Nouveau mot de passe', overline: 'Sécurité'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LHSpacing.md),
                    child: Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: LHColors.erreur)),
                  ),
                if (_info != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LHSpacing.md),
                    child: Text(_info!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: LHColors.emeraudeClair)),
                  ),
                LabeledField(
                  label: 'Mot de passe actuel',
                  child: TextField(
                    controller: _current,
                    obscureText: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.lock_outline)),
                  ),
                ),
                const SizedBox(height: LHSpacing.md),
                LabeledField(
                  label: 'Nouveau mot de passe (8 caractères minimum)',
                  child: TextField(
                    controller: _new,
                    obscureText: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.lock_outline)),
                  ),
                ),
                const SizedBox(height: LHSpacing.md),
                LabeledField(
                  label: 'Confirmer le nouveau mot de passe',
                  child: TextField(
                    controller: _confirm,
                    obscureText: true,
                    onSubmitted: (_) => _changePassword(),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.lock_outline)),
                  ),
                ),
                const SizedBox(height: LHSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _changePassword,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Modifier le mot de passe'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : SESSIONS & APPAREILS ═══════════════════════════

/// Sessions actives du compte (GET /auth/sessions) avec révocation
/// individuelle (DELETE /auth/sessions/:id) et déconnexion globale.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  List<LhDeviceSession>? _sessions;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final sessions = await ref.read(apiClientProvider).sessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _error = null;
      });
    } on LhApiException catch (e) {
      if (mounted) setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      if (mounted) setState(() => _error = apiErrorText(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Erreur inattendue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(LhDeviceSession s) async {
    final ok = await lhConfirm(
      context,
      title: 'Révoquer cette session ?',
      message:
          'L\'appareil « ${s.deviceName} » sera déconnecté du compte.',
      confirmLabel: 'Révoquer',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).revokeSession(s.id);
      await _load();
    } on LhApiException catch (e) {
      if (mounted) lhToast(context, apiErrorText(e));
    } on LhNetworkException catch (e) {
      if (mounted) lhToast(context, apiErrorText(e));
    }
  }

  Future<void> _revokeAll() async {
    final ok = await lhConfirm(
      context,
      title: 'Déconnecter tous les appareils ?',
      message:
          'Toutes les sessions seront révoquées, y compris celle-ci. Vous devrez vous reconnecter.',
      confirmLabel: 'Tout déconnecter',
      destructive: true,
    );
    if (!ok) return;
    final store = ref.read(tokenStoreProvider);
    try {
      await ref.read(apiClientProvider).logoutAll();
    } catch (_) {
      // Même injoignable, la session locale est effacée.
    }
    await store.clear();
    if (mounted) {
      // Toutes les sessions sont révoquées : écran de connexion.
      context.go('/login?loggedOut=1');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions & appareils')),
      body: _busy && _sessions == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  message: _error!,
                  action: OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Réessayer'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Chaque appareil connecté à votre compte. Révoquez les sessions que vous ne reconnaissez pas.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      for (final s in _sessions ?? const <LhDeviceSession>[])
                        ListTile(
                          leading: Icon(
                            s.current
                                ? Icons.smartphone
                                : Icons.devices_other_outlined,
                            color: s.current ? LHColors.emeraudeClair : null,
                          ),
                          title: Row(children: [
                            Expanded(
                                child: Text(s.deviceName,
                                    overflow: TextOverflow.ellipsis)),
                            if (s.current)
                              const StatusChip(
                                  label: 'Session actuelle',
                                  color: LHColors.emeraudeClair,
                                  small: true),
                          ]),
                          subtitle: Text(
                            '${s.ip ?? 'IP inconnue'} · utilisée ${fmt.timeAgo(s.lastUsedAt)}',
                          ),
                          trailing: s.current
                              ? null
                              : IconButton(
                                  tooltip: 'Révoquer',
                                  icon: const Icon(Icons.logout,
                                      size: 20, color: LHColors.erreur),
                                  onPressed: () => _revoke(s),
                                ),
                        ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: LHColors.erreur),
                          onPressed: _revokeAll,
                          icon: const Icon(Icons.phonelink_erase_outlined,
                              size: 18),
                          label:
                              const Text('Déconnecter tous les appareils'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : SÉCURITÉ & 2FA ═══════════════════════════

/// Double authentification TOTP : activation (secret + otpauth + code) ou
/// désactivation (code + confirmation).
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  ({String secret, String otpauthUrl})? _setup;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final setup = await ref.read(apiClientProvider).setup2fa();
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _info = 'Scannez le secret dans votre application TOTP '
            '(Google Authenticator, FreeOTP…), puis saisissez le code généré.';
      });
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Erreur inattendue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Saisissez le code à 6 chiffres généré.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).enable2fa(_code.text.trim());
      await ref.read(sessionProvider.notifier).refreshUser();
      if (!mounted) return;
      setState(() {
        _setup = null;
        _code.clear();
        _info = 'Double authentification activée.';
      });
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Erreur inattendue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Saisissez le code à 6 chiffres généré.');
      return;
    }
    final ok = await lhConfirm(
      context,
      title: 'Désactiver la 2FA ?',
      message:
          'Votre compte sera protégé par le mot de passe seul. Cette action est déconseillée.',
      confirmLabel: 'Désactiver',
      destructive: true,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).disable2fa(_code.text.trim());
      await ref.read(sessionProvider.notifier).refreshUser();
      if (!mounted) return;
      setState(() {
        _code.clear();
        _info = 'Double authentification désactivée.';
      });
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Erreur inattendue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sécurité & 2FA')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          message: 'Aucun compte connecté',
          hint: 'Créez un compte pour gérer la sécurité.',
          action: FilledButton.icon(
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Activer la synchronisation'),
          ),
        ),
      );
    }

    final enabled = user.twoFactorEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité & 2FA')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(
                enabled
                    ? Icons.verified_user_outlined
                    : Icons.gpp_maybe_outlined,
                color: enabled
                    ? LHColors.emeraudeClair
                    : theme.colorScheme.onSurfaceVariant,
                size: 40,
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Double authentification (TOTP)',
                          style: theme.textTheme.titleMedium),
                      Text(
                        enabled
                            ? 'Activée — un code à 6 chiffres est demandé à chaque connexion.'
                            : 'Désactivée — ajoutez une seconde protection à votre compte.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4),
                      ),
                    ]),
              ),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: LHColors.erreur)),
            ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_info!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: LHColors.emeraudeClair)),
            ),
          if (!enabled && _setup == null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton.icon(
                onPressed: _busy ? null : _startSetup,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_2, size: 18),
                label: const Text('Activer la 2FA'),
              ),
            ),
          if (!enabled && _setup != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LHCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Secret (base32)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            SelectableText(
                              _setup!.secret,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                            const SizedBox(height: LHSpacing.md),
                            Text('URI otpauth',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            SelectableText(
                              _setup!.otpauthUrl,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 11),
                            ),
                            const SizedBox(height: LHSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text: _setup!.secret));
                                  lhToast(context, 'Secret copié.');
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copier le secret'),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    LabeledField(
                      label: 'Code de vérification',
                      child: TextField(
                        controller: _code,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            hintText: 'Code à 6 chiffres',
                            prefixIcon: Icon(Icons.pin_outlined),
                            counterText: ''),
                      ),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    FilledButton(
                      onPressed: _busy ? null : _enable,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Confirmer l\'activation'),
                    ),
                  ]),
            ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                      label: 'Code de vérification actuel',
                      child: TextField(
                        controller: _code,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            hintText: 'Code à 6 chiffres',
                            prefixIcon: Icon(Icons.pin_outlined),
                            counterText: ''),
                      ),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: LHColors.erreur),
                      onPressed: _busy ? null : _disable,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Désactiver la 2FA'),
                    ),
                  ]),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : SYNCHRONISATION ═══════════════════════════

/// Écran de pilotage : état de la connexion, file locale, conflits à
/// résoudre, rejets, synchronisation manuelle et purge d'historique.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  int _trigger = 0;

  Future<void> _syncNow() async {
    setState(() => _trigger++);
    try {
      await ref.read(syncNowProvider(_trigger).future);
    } catch (_) {
      // L'erreur est exposée dans l'état de synchronisation (carte ÉTAT).
    }
  }

  Future<void> _purge() async {
    final ok = await lhConfirm(
      context,
      title: 'Purger l\'historique synchronisé ?',
      message:
          'Les opérations déjà synchronisées seront retirées de l\'historique local. Les données ne sont pas modifiées.',
      confirmLabel: 'Purger',
    );
    if (!ok) return;
    await ref.read(syncControllerProvider).purgeHistory();
    if (mounted) lhToast(context, 'Historique synchronisé purgé.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final stateAsync = ref.watch(syncStateProvider);
    final conflictsAsync = ref.watch(conflictListProvider);
    final rejectionsAsync = ref.watch(rejectedListProvider);
    final pendingOps = ref.watch(pendingOpCountProvider).valueOrNull ?? 0;

    if (!session.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Synchronisation')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          message: 'Créez un compte pour activer la synchronisation',
          hint:
              'Vos données restent sur cet appareil — la sauvegarde en ligne est optionnelle.',
          action: FilledButton.icon(
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Activer la synchronisation'),
          ),
        ),
      );
    }

    final state = stateAsync.valueOrNull;
    final running = state?.running ??
        ref.watch(syncNowProvider(_trigger)).isLoading;
    final conflicts = conflictsAsync.valueOrNull ?? const <dbm.SyncOperation>[];
    final rejections = rejectionsAsync.valueOrNull ?? const <dbm.SyncOperation>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── ÉTAT ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: LHCard(
              accent: state != null && state.connected
                  ? (state.conflicts > 0 ? LHColors.alerte : null)
                  : LHColors.neutre,
              child: Column(children: [
                Row(children: [
                  Icon(
                    state == null || !state.connected
                        ? Icons.cloud_off_outlined
                        : running
                            ? Icons.sync_rounded
                            : Icons.cloud_done_outlined,
                    color: state != null && state.connected
                        ? LHColors.emeraudeClair
                        : LHColors.neutre,
                  ),
                  const SizedBox(width: LHSpacing.md),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            running
                                ? 'Synchronisation en cours…'
                                : state == null || !state.connected
                                    ? 'Compte déconnecté'
                                    : 'Connecté au serveur',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            state?.lastSyncAt == null
                                ? 'Jamais synchronisé'
                                : 'Dernière synchronisation ${fmt.timeAgo(state!.lastSyncAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                          ),
                        ]),
                  ),
                  if (state?.serverSeq != null)
                    Text('séq. ${state!.serverSeq}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ]),
                if (state?.lastError != null) ...[
                  const SizedBox(height: LHSpacing.md),
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: LHColors.erreur, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(state!.lastError!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: LHColors.erreur)),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
          // ── FILE ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: _CountTile(
                label: 'En attente',
                value: '$pendingOps',
                color: pendingOps > 0 ? LHColors.or : LHColors.neutre,
              )),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                  child: _CountTile(
                label: 'Conflits',
                value: '${state?.conflicts ?? conflicts.length}',
                color: conflicts.isNotEmpty ? LHColors.alerte : LHColors.neutre,
              )),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                  child: _CountTile(
                label: 'Rejets',
                value: '${state?.rejected ?? rejections.length}',
                color: rejections.isNotEmpty ? LHColors.erreur : LHColors.neutre,
              )),
            ]),
          ),
          const SizedBox(height: LHSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: running ? null : _syncNow,
              icon: running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Synchroniser maintenant'),
            ),
          ),
          // ── CONFLITS ──
          if (conflicts.isNotEmpty) ...[
            SectionHeader('Conflits à résoudre',
                overline: 'Divergence serveur'),
            for (final op in conflicts)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LHCard(
                  accent: LHColors.alerte,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            _opIcon(op.op),
                            size: 18,
                            color: LHColors.alerte,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_resourceLabel(op.resourceType)} · ${op.op}',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Cette ressource a divergé côté serveur. Choisissez la version à conserver.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: LHSpacing.md),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(syncControllerProvider)
                                    .keepLocalVersion(op.id);
                                if (mounted) {
                                  lhToast(this.context,
                                      'Votre version sera renvoyée au serveur.');
                                }
                              },
                              icon: const Icon(Icons.upload_rounded,
                                  size: 16),
                              label: const Text('Garder ma version'),
                            ),
                          ),
                          const SizedBox(width: LHSpacing.sm),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final ok = await ref
                                    .read(syncControllerProvider)
                                    .takeServerVersion(op.id);
                                if (!mounted) return;
                                lhToast(
                                    this.context,
                                    ok
                                        ? 'Version serveur appliquée.'
                                        : 'Version serveur introuvable — réessayez plus tard.');
                              },
                              icon: const Icon(Icons.download_rounded,
                                  size: 16),
                              label: const Text('Version serveur'),
                            ),
                          ),
                        ]),
                      ]),
                ),
              ),
          ],
          // ── REJETS ──
          if (rejections.isNotEmpty) ...[
            SectionHeader('Rejets du serveur', overline: 'Non appliqué'),
            for (final op in rejections)
              ListTile(
                dense: true,
                leading: Icon(_opIcon(op.op),
                    size: 20, color: LHColors.erreur),
                title: Text('${_resourceLabel(op.resourceType)} · ${op.op}'),
                subtitle: Text(op.lastError ?? 'Rejetée par le serveur'),
              ),
          ],
          // ── HISTORIQUE ──
          SectionHeader('Maintenance', overline: 'Historique local'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _purge,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Purger l\'historique synchronisé'),
            ),
          ),
          const SizedBox(height: LHSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Les opérations synchronisées sont automatiquement purgées après 7 jours.',
              style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _opIcon(String op) => switch (op) {
        'CREATE' => Icons.add_circle_outline,
        'DELETE' => Icons.remove_circle_outline,
        _ => Icons.edit_outlined,
      };

  static String _resourceLabel(String type) => switch (type) {
        'Task' => 'Tâche',
        'TaskList' => 'Liste de tâches',
        'TaskDependency' => 'Dépendance de tâche',
        'Calendar' => 'Calendrier',
        'CalendarEvent' => 'Événement',
        'EventException' => 'Exception d\'événement',
        'RecurrenceRule' => 'Règle de récurrence',
        'Space' => 'Espace',
        'SpaceMember' => 'Membre d\'espace',
        'FinancialAccount' => 'Compte financier',
        'FinancialCategory' => 'Catégorie financière',
        'FinancialTransaction' => 'Transaction',
        'Transfer' => 'Transfert',
        'TransactionAllocation' => 'Allocation budgétaire',
        'Budget' => 'Budget',
        'BudgetAdjustment' => 'Ajustement de budget',
        'BudgetCarryover' => 'Report de budget',
        'FinancialDueItem' => 'Échéance',
        'AccountReconciliation' => 'Rapprochement',
        'Folder' => 'Dossier',
        'Note' => 'Note',
        'NoteVersion' => 'Version de note',
        'Project' => 'Projet',
        'ProjectMember' => 'Membre de projet',
        'ProjectStage' => 'Étape de projet',
        'ProjectMilestone' => 'Jalon de projet',
        'ProjectTaskLink' => 'Lien projet-tâche',
        'Goal' => 'Objectif',
        'GoalMetric' => 'Indicateur',
        'GoalProgressEntry' => 'Progression d\'objectif',
        'GoalProjectLink' => 'Lien objectif-projet',
        'Habit' => 'Habitude',
        'HabitSchedule' => 'Planification d\'habitude',
        'HabitOccurrence' => 'Occurrence d\'habitude',
        'Routine' => 'Routine',
        'RoutineStep' => 'Étape de routine',
        'RoutineOccurrence' => 'Occurrence de routine',
        'WellbeingEntry' => 'Entrée bien-être',
        'DailyReview' => 'Bilan quotidien',
        'CareerProfile' => 'Profil carrière',
        'Skill' => 'Compétence',
        'UserSkill' => 'Compétence (profil)',
        'LearningPath' => 'Parcours d\'apprentissage',
        'LearningPathStep' => 'Étape de parcours',
        'ProfessionalExperience' => 'Expérience',
        'Certification' => 'Certification',
        'PortfolioItem' => 'Réalisation',
        'Contact' => 'Contact',
        'ContactPoint' => 'Coordonnée',
        'ContactInteraction' => 'Interaction',
        'ContactLink' => 'Lien de contact',
        'Conversation' => 'Conversation',
        'ConversationMember' => 'Membre de conversation',
        'Message' => 'Message',
        'MessageReaction' => 'Réaction',
        _ => type,
      };
}

/// Petite tuile de compteur (file locale).
class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(LHRadius.md),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(children: [
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/push/push_service.dart';
import '../../core/theme/tokens.dart';
import 'briefing.dart' show aiBriefingProvider;
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;

/// Préférences HELM AI (D17.2 §7.2 + D17.6 Phase 3) — autonomie, seuil
/// d'alerte, périmètre de contexte, consentements granulaires, briefing
/// quotidien et transparence d'usage.
///
/// Confidentialité par conception :
/// - les périmètres sensibles (journal de bien-être, messagerie, notes)
///   exigent UNE DOUBLE CLÉ : activation dans le périmètre de contexte ET
///   consentement explicite dédié — refusés par défaut sinon ;
/// - désactiver un module ici signifie qu'il n'est NI lu NI transmis au
///   modèle lors des demandes ; le retrait d'un consentement est effectif
///   immédiatement (le serveur relit les consentements à chaque demande).
class AiPreferencesScreen extends ConsumerStatefulWidget {
  const AiPreferencesScreen({super.key});

  @override
  ConsumerState<AiPreferencesScreen> createState() =>
      _AiPreferencesScreenState();
}

class _AiPreferencesScreenState extends ConsumerState<AiPreferencesScreen> {
  LhAiPreferences? _prefs;
  LhAiUsage? _usage;
  List<LhAiConsent> _consents = [];
  bool _loading = true;
  bool _saving = false;
  bool _pushBusy = false; // activation / désactivation des notifications
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final prefs = await client.aiGetPreferences();
      LhAiUsage? usage;
      List<LhAiConsent> consents = [];
      try {
        usage = await client.aiUsage();
      } catch (_) {
        usage = null; // transparence best-effort
      }
      try {
        consents = await client.aiGetConsents();
      } catch (_) {
        consents = []; // consentements best-effort (Phase 3)
      }
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _usage = usage;
        _consents = consents;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = await ref.read(apiClientProvider).aiUpdatePreferences(patch);
      if (!mounted) return;
      setState(() => _prefs = prefs);
      // Le briefing dépend des préférences : la carte cockpit se réévalue.
      if (patch.containsKey('dailyBriefing')) {
        ref.invalidate(aiBriefingProvider);
      }
      // Les notifications du briefing suivent l'heure et l'état du briefing.
      if (patch.containsKey('dailyBriefing') ||
          patch.containsKey('briefingHour')) {
        ref.read(pushProvider.notifier).reschedule(
          (patch['briefingHour'] ?? prefs.briefingHour) as int,
          active: (patch['dailyBriefing'] ?? prefs.dailyBriefing) as bool,
        );
      }
    } catch (e) {
      if (mounted) lhToast(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LhAppBar(title: 'Préférences HELM AI', showActions: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(LHSpacing.screen),
                    children: [
                      _intro(context),
                      const SizedBox(height: LHSpacing.lg),
                      _autonomyCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _alertsCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _scopeCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _consentsCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _briefingCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _pushCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _usageCard(context),
                      const SizedBox(height: LHSpacing.md),
                      _privacyCard(context),
                      const SizedBox(height: LHSpacing.xl),
                    ],
                  ),
                ),
    );
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Réglez ce que HELM AI peut consulter et à quel point elle peut agir. '
      'Chaque couleur garde son sens : le bleu pour les interactions, '
      'l\'orange pour l\'attention, le vert pour les réussites.',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
    );
  }

  /// Niveau d'autonomie (D17 §17.6) — SUGGEST / PREPARE / ASSIST.
  /// AUTOMATE n'existe pas en V1 : l'IA ne fait jamais rien seule.
  Widget _autonomyCard(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = _prefs!;
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Niveau d\'autonomie', overline: 'Ce que l\'IA peut faire'),
        const SizedBox(height: LHSpacing.sm),
        _AutonomyOption(
          value: 'SUGGEST',
          groupValue: prefs.autonomyLevel,
          title: 'Suggérer',
          subtitle: 'HELM AI conseille et explique, sans préparer d\'action.',
          icon: Icons.lightbulb_outline_rounded,
          color: LHColors.electrique,
          enabled: !_saving,
          onChanged: (v) => _patch({'autonomyLevel': v}),
        ),
        _AutonomyOption(
          value: 'PREPARE',
          groupValue: prefs.autonomyLevel,
          title: 'Préparer',
          subtitle: 'HELM AI propose des brouillons prêts à confirmer '
              '(tâche, report d\'événement, correction).',
          icon: Icons.edit_note_rounded,
          color: LHColors.orDeep,
          enabled: !_saving,
          onChanged: (v) => _patch({'autonomyLevel': v}),
        ),
        _AutonomyOption(
          value: 'ASSIST',
          groupValue: prefs.autonomyLevel,
          title: 'Assister',
          subtitle: 'Brouillons enrichis (montants, dates, priorités) avec '
              'vérifications supplémentaires avant confirmation.',
          icon: Icons.support_agent_rounded,
          color: LHColors.vertProfond,
          enabled: !_saving,
          onChanged: (v) => _patch({'autonomyLevel': v}),
        ),
        const SizedBox(height: LHSpacing.sm),
        Text(
          'Dans tous les cas, HELM AI n\'exécute JAMAIS sans votre confirmation '
          'explicite.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: LHColors.orDeep, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  /// Seuil d'alertes à partir duquel HELM AI attire l'attention.
  Widget _alertsCard(BuildContext context) {
    final prefs = _prefs!;
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Seuil d\'alertes', overline: 'Notifications'),
        const SizedBox(height: LHSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'INFORMATION',
                label: Text('Tout'),
                icon: Icon(Icons.info_outline_rounded, size: 16)),
            ButtonSegment(
                value: 'NORMAL',
                label: Text('Normal'),
                icon: Icon(Icons.notifications_outlined, size: 16)),
            ButtonSegment(
                value: 'IMPORTANT',
                label: Text('Important'),
                icon: Icon(Icons.warning_amber_rounded, size: 16)),
          ],
          selected: {prefs.alertThreshold},
          onSelectionChanged: _saving
              ? null
              : (s) => _patch({'alertThreshold': s.first}),
        ),
        const SizedBox(height: LHSpacing.sm),
        Text(
          'Les alertes critiques (sécurité, données) sont toujours affichées : '
          'elles relèvent des règles métier, jamais du modèle.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  /// Périmètre de contexte — modules transmis au modèle.
  Widget _scopeCard(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = _prefs!;
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Périmètre de contexte',
            overline: 'Ce que l\'IA peut consulter'),
        const SizedBox(height: LHSpacing.sm),
        _ScopeSwitch(
          label: 'Finances, budgets et échéances',
          icon: Icons.account_balance_wallet_outlined,
          value: prefs.scope('finance'),
          enabled: !_saving,
          onChanged: (v) => _patch({
            'contextScope': {...prefs.contextScope, 'finance': v},
          }),
        ),
        _ScopeSwitch(
          label: 'Tâches et priorités',
          icon: Icons.checklist_rounded,
          value: prefs.scope('tasks'),
          enabled: !_saving,
          onChanged: (v) => _patch({
            'contextScope': {...prefs.contextScope, 'tasks': v},
          }),
        ),
        _ScopeSwitch(
          label: 'Agenda et événements',
          icon: Icons.event_outlined,
          value: prefs.scope('agenda'),
          enabled: !_saving,
          onChanged: (v) => _patch({
            'contextScope': {...prefs.contextScope, 'agenda': v},
          }),
        ),
        _ScopeSwitch(
          label: 'Projets et objectifs',
          icon: Icons.flag_outlined,
          value: prefs.scope('projects'),
          enabled: !_saving,
          onChanged: (v) => _patch({
            'contextScope': {...prefs.contextScope, 'projects': v},
          }),
        ),
        _ScopeSwitch(
          label: 'Notes (extraits titrés lors de recherches)',
          icon: Icons.sticky_note_2_outlined,
          value: prefs.scope('notes'),
          enabled: !_saving,
          onChanged: (v) => _patch({
            'contextScope': {...prefs.contextScope, 'notes': v},
          }),
        ),
        const Divider(height: LHSpacing.lg),
        Row(children: [
          Icon(Icons.shield_outlined,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Les périmètres sensibles (bien-être, messagerie, notes) exigent '
              'une double clé : activation ici ET consentement explicite '
              'ci-dessous.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Consentements granulaires (D17.6 — Phase 3) — chaque périmètre
  /// sensible est REFUSÉ par défaut ; l'octroi passe par un dialogue
  /// explicite, le retrait est immédiat et sans friction.
  Widget _consentsCard(BuildContext context) {
    final theme = Theme.of(context);
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Consentements sensibles',
            overline: 'Double clé — refusés par défaut'),
        const SizedBox(height: LHSpacing.sm),
        Text(
          'Ces données ne sont transmises à HELM AI que si vous l\'autorisez '
          'explicitement, en plus de l\'activation du module ci-dessus. '
          'Chaque décision est journalisée ; le retrait est immédiat.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: LHSpacing.sm),
        if (_consents.isEmpty)
          Row(children: [
            Icon(Icons.lock_outline_rounded,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Journal de bien-être, messagerie et contenu des notes : '
                'jamais transmis.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ])
        else
          for (final c in _consents)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.label),
              subtitle: Text(
                c.granted
                    ? '${_consentSummary(c)}\nAutorisé${c.grantedAt != null ? ' le ${c.grantedAt!.day}/${c.grantedAt!.month}/${c.grantedAt!.year}' : ''} — révocable à tout moment.'
                    : c.description,
                style: TextStyle(height: 1.35),
              ),
              isThreeLine: true,
              value: c.granted,
              onChanged: _saving
                  ? null
                  : (v) => v
                      ? _askConsent(c)
                      : _setConsent(c, false),
            ),
        if (_consents.isNotEmpty) ...[
          const Divider(height: LHSpacing.lg),
          Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Le périmètre reste appliqué à chaque demande : '
                'un module désactivé dans le périmètre de contexte reste muet, '
                'même avec un consentement accordé.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  String _consentSummary(LhAiConsent c) => c.description;

  /// Dialogue d'octroi explicite — l'utilisateur voit EXACTEMENT ce qui
  /// sera transmis avant d'autoriser (jamais d'octroi implicite).
  Future<void> _askConsent(LhAiConsent c) async {
    final theme = Theme.of(context);
    final granted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Autoriser « ${c.label} »'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ce qui sera transmis à HELM AI :',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(c.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
          Text(
            'Vous pouvez retirer cette autorisation à tout moment, effet '
            'immédiat. Cette décision est journalisée (qui, quand, quoi — '
            'jamais le contenu lui-même).',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.45),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('J\'autorise'),
          ),
        ],
      ),
    );
    if (granted == true) _setConsent(c, true);
  }

  Future<void> _setConsent(LhAiConsent c, bool granted) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.aiSetConsent(c.scope, granted);
      final consents = await client.aiGetConsents();
      if (!mounted) return;
      setState(() => _consents = consents);
    } catch (e) {
      if (mounted) lhToast(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _briefingCard(BuildContext context) {
    final prefs = _prefs!;
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Briefing quotidien'),
          subtitle: const Text(
              'Un résumé du jour : échéances, agenda, budget — dès que '
              'l\'assistant est disponible.'),
          value: prefs.dailyBriefing,
          onChanged: _saving
              ? null
              : (v) => _patch({'dailyBriefing': v, 'briefingHour': prefs.briefingHour}),
        ),
        if (prefs.dailyBriefing)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text('Heure : ${prefs.briefingHour}h00'),
            subtitle: Slider(
              value: prefs.briefingHour.toDouble(),
              min: 4,
              max: 11,
              divisions: 7,
              label: '${prefs.briefingHour}h',
              onChanged: _saving
                  ? null
                  : (v) => _patch(
                      {'briefingHour': v.round(), 'dailyBriefing': true}),
            ),
          ),
      ]),
    );
  }

  /// Notifications natives du briefing (D17.6) — canal actif, permission,
  /// test immédiat. Deux canaux, une promesse : prévenir quand le briefing
  /// est prêt. Push serveur (FCM) dès qu'un projet Firebase est branché ;
  /// sinon repli local quotidien — jamais de fausse promesse.
  Widget _pushCard(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = _prefs!;
    final push = ref.watch(pushProvider);

    if (!push.supported) {
      // Web — honnête : pas de notifications natives sur le web.
      return LHCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('Notifications du briefing',
              overline: 'Appareil'),
          const SizedBox(height: LHSpacing.md),
          Row(children: [
            const Icon(Icons.notifications_off_outlined,
                color: LHColors.ardoise),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Text(
                'Les notifications natives ne sont pas disponibles sur le web. '
                'Le briefing reste consultable dans l\'application, même hors '
                'connexion.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ]),
        ]),
      );
    }

    final (badge, badgeColor, badgeIcon) = switch (push.channel) {
      PushChannel.fcm => (
        'Alerte automatique active',
        LHColors.vertSucces,
        Icons.cloud_done_outlined
      ),
      PushChannel.local => (
        'Notification locale programmée',
        LHColors.electrique,
        Icons.schedule_outlined
      ),
      PushChannel.denied => (
        'Permission refusée',
        LHColors.orange,
        Icons.notifications_off_outlined
      ),
      PushChannel.off => (
        'Désactivées',
        LHColors.ardoise,
        Icons.notifications_none_outlined
      ),
    };

    final heureNote = push.channel == PushChannel.fcm
        ? 'Notification dès que le briefing est généré (autour de '
            '${prefs.briefingHour}h00).'
        : 'Notification quotidienne à ${prefs.briefingHour}h15 — votre '
            'briefing est alors déjà prêt.';

    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Me notifier quand le briefing est prêt'),
          subtitle: const Text(
              'Notification native sur cet appareil — rien n\'est envoyé '
              'tant que vous ne l\'activez pas.'),
          value: push.enabled,
          onChanged: _pushBusy
              ? null
              : (v) async {
                  setState(() => _pushBusy = true);
                  final notifier = ref.read(pushProvider.notifier);
                  if (v) {
                    await notifier.enable();
                  } else {
                    await notifier.disable();
                  }
                  if (mounted) setState(() => _pushBusy = false);
                },
        ),
        const SizedBox(height: LHSpacing.sm),
        Row(children: [
          Icon(badgeIcon, color: badgeColor, size: 20),
          const SizedBox(width: LHSpacing.sm),
          Expanded(
            child: Text(badge,
                style: theme.textTheme.labelLarge?.copyWith(
                    color: badgeColor, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          push.enabled ? heureNote : 'Activez pour recevoir la notification.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (push.enabled && !prefs.dailyBriefing) ...[
          const SizedBox(height: LHSpacing.sm),
          Text(
            'Attention : le briefing quotidien est désactivé ci-dessus — '
            'aucune notification ne sera envoyée tant qu\'il est inactif.',
            style: theme.textTheme.bodySmall?.copyWith(color: LHColors.orange),
          ),
        ],
        if (push.enabled && push.channel != PushChannel.denied) ...[
          const SizedBox(height: LHSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pushBusy
                  ? null
                  : () async {
                      await ref
                          .read(pushProvider.notifier)
                          .testNotification();
                      if (!context.mounted) return;
                      lhToast(context,
                          'Notification de test envoyée — repliez l\'app pour la voir.');
                    },
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Notification de test'),
            ),
          ),
        ],
      ]),
    );
  }

  /// Transparence : compteurs d'usage sur 24 h (D17.2 §7.5).
  Widget _usageCard(BuildContext context) {
    final theme = Theme.of(context);
    final usage = _usage;
    if (usage == null) return const SizedBox.shrink();
    final ratio = usage.messageQuota > 0
        ? (usage.messages / usage.messageQuota).clamp(0.0, 1.0)
        : 0.0;
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Usage (24 heures)', overline: 'Transparence'),
        const SizedBox(height: LHSpacing.md),
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${usage.messages} / ${usage.messageQuota} messages',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(LHRadius.full),
                    child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        color: ratio > 0.8 ? LHColors.orange : LHColors.electrique),
                  ),
                ]),
          ),
          const SizedBox(width: LHSpacing.lg),
          _usageStat(context, '${usage.actionsConfirmed}',
              'actions\nconfirmées', LHColors.vertSucces),
          const SizedBox(width: LHSpacing.md),
          _usageStat(context,
              usage.averageLatencyMs > 0 ? '${(usage.averageLatencyMs / 1000).toStringAsFixed(1)}s' : '—',
              'réponse\nmoyenne', LHColors.electrique),
        ]),
      ]),
    );
  }

  Widget _usageStat(
      BuildContext context, String value, String label, Color color) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: color)),
      Text(label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }

  Widget _privacyCard(BuildContext context) {
    final theme = Theme.of(context);
    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Engagements', overline: 'Confidentialité'),
        const SizedBox(height: LHSpacing.sm),
        for (final (icon, text) in [
          (Icons.visibility_off_outlined,
              'Vos données restent les vôtres : l\'assistant les relit à la '
              'source à chaque demande, sans en garder une copie.'),
          (Icons.verified_user_outlined,
              'L\'IA prépare, vous décidez : aucune écriture sans confirmation '
              'explicite, avec un journal d\'audit complet.'),
          (Icons.block_outlined,
              'Résistance aux manipulations : le contenu de vos notes et '
              'libellés n\'est jamais traité comme des instructions.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: LHSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: LHColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _AutonomyOption extends StatelessWidget {
  const _AutonomyOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: LHSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(LHRadius.md),
        onTap: enabled && !selected ? () => onChanged(value) : null,
        child: Container(
          padding: const EdgeInsets.all(LHSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? theme.brightness == Brightness.dark
                    ? LHColors.orSurface
                    : LHColors.orTint
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(LHRadius.md),
            border: Border.all(
                color: selected
                    ? LHColors.or.withValues(alpha: 0.6)
                    : theme.colorScheme.outline),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? LHColors.orDeep : color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? LHColors.orDeep
                                : theme.colorScheme.onSurface)),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4)),
                  ]),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: LHColors.or, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: LHColors.navy),
      title: Text(label),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LHSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: LHColors.ardoise),
          const SizedBox(height: LHSpacing.md),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: LHSpacing.lg),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/net/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

// ═══════════════════════ BRIEFING QUOTIDIEN (D17.6 — Phase 3) ═══════════════════════

/// Signal « ouvrir la feuille briefing » posé par un tap sur une notification
/// (push FCM ou locale — D17.6). Le cockpit y souscrit ; consommé à l'ouverture.
final briefingOpenRequest = StateProvider<bool>((_) => false);

/// État du briefing côté application.
class BriefingState {
  const BriefingState({
    this.loading = false,
    this.enabled = false,
    this.checked = false, // au moins une vérification serveur effectuée
    this.briefing,
    this.alerts = const [],
    this.offline = false, // dernière récupération impossible — cache affiché
    this.error,
  });
  final bool loading;
  final bool enabled; // l'utilisateur a activé le briefing (préférences IA)
  final bool checked;
  final LhAiBriefing? briefing;
  final List<LhAiAlert> alerts;
  final bool offline;
  final String? error;

  BriefingState copyWith({
    bool? loading,
    bool? enabled,
    bool? checked,
    LhAiBriefing? briefing,
    List<LhAiAlert>? alerts,
    bool? offline,
    String? error,
    bool clearError = false,
  }) =>
      BriefingState(
        loading: loading ?? this.loading,
        enabled: enabled ?? this.enabled,
        checked: checked ?? this.checked,
        briefing: briefing ?? this.briefing,
        alerts: alerts ?? this.alerts,
        offline: offline ?? this.offline,
        error: clearError ? null : (error ?? this.error),
      );
}

class BriefingNotifier extends StateNotifier<BriefingState> {
  BriefingNotifier(this._client) : super(const BriefingState()) {
    _restoreCache();
  }

  final ApiClient _client;
  static const _cacheKey = 'helm_ai.briefing.cache';

  /// Date locale de l'appareil (AAAA-MM-JJ) — une récupération par jour.
  String get _today =>
      DateTime.now().toIso8601String().substring(0, 10);

  /// Restaure le cache hors ligne (le briefing d'aujourd'hui reste lisible
  /// sans réseau — offline-first, D17.6 : le briefing est généré côté serveur
  /// mais consultable en toute circonstance une fois récupéré).
  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map? ?? {});
      final briefing = LhAiBriefing.fromJson(
          Map<String, dynamic>.from(json['briefing'] as Map? ?? {}));
      final alerts = (json['alerts'] as List? ?? [])
          .map((a) => LhAiAlert.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
      state = state.copyWith(
          enabled: true,
          briefing: briefing,
          alerts: alerts,
          offline: briefing.date != _today);
    } catch (_) {
      // cache illisible → ignoré silencieusement
    }
  }

  /// Récupère le briefing du jour (une fois par jour, ou sur demande explicite).
  Future<void> refresh({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.briefing?.date == _today) return; // déjà à jour
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _client.aiGetBriefing();
      if (!res.enabled) {
        state = BriefingState(enabled: false, checked: true); // opt-out
        return;
      }
      state = BriefingState(
        enabled: true,
        checked: true,
        briefing: res.briefing,
        alerts: res.alerts,
      );
      await _persistCache();
    } on LhNetworkException {
      // Hors ligne : on garde le cache (marqué hors ligne si périmé).
      state = state.copyWith(
        loading: false,
        checked: true,
        offline: state.briefing == null || state.briefing!.date != _today,
      );
    } catch (e) {
      state = state.copyWith(
          loading: false,
          checked: true,
          error: e.toString(),
          offline: state.briefing == null);
    }
  }

  Future<void> _persistCache() async {
    final b = state.briefing;
    if (b == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({
        'date': b.date,
        'briefing': b.toJson(),
        'alerts': state.alerts.map(_alertToJson).toList(),
      }));
    } catch (_) {/* cache best-effort */}
  }


  Map<String, dynamic> _alertToJson(LhAiAlert a) => {
        'id': a.id,
        'kind': a.kind,
        'severity': a.severity,
        'title': a.title,
        'body': a.body,
        'status': a.status,
        'dedupKey': a.dedupKey,
        'payload': a.payload,
        'createdAt': a.createdAt.toIso8601String(),
      };

  /// Marque une alerte lue (optimiste, repli silencieux hors ligne).
  Future<void> markRead(LhAiAlert alert) async {
    if (alert.status != 'UNREAD') return;
    state = state.copyWith(
        alerts: [for (final a in state.alerts) a.id == alert.id ? _copy(a, 'READ') : a]);
    try {
      await _client.aiMarkAlertRead(alert.id);
    } catch (_) {/* le statut serveur se réalignera au prochain fetch */}
  }

  /// Ignore une alerte (optimiste).
  Future<void> dismiss(LhAiAlert alert) async {
    state = state.copyWith(
        alerts: [for (final a in state.alerts) a.id == alert.id ? _copy(a, 'DISMISSED') : a]);
    try {
      await _client.aiDismissAlert(alert.id);
    } catch (_) {/* idem */}
  }

  LhAiAlert _copy(LhAiAlert a, String status) => LhAiAlert(
        id: a.id,
        kind: a.kind,
        severity: a.severity,
        title: a.title,
        body: a.body,
        status: status,
        dedupKey: a.dedupKey,
        payload: a.payload,
        createdAt: a.createdAt,
      );
}

final aiBriefingProvider =
    StateNotifierProvider<BriefingNotifier, BriefingState>((ref) {
  final notifier = BriefingNotifier(ref.watch(apiClientProvider));
  // Récupération automatique à l'ouverture (connecté uniquement) — le
  // briefing reste lisible depuis le cache sans réseau.
  final session = ref.read(sessionProvider);
  if (session.isConnected) {
    Future.microtask(() => notifier.refresh());
  }
  return notifier;
});

// ═══════════════════════ CARTE BRIEFING (cockpit) ═══════════════════════

/// « Briefing du jour » — accroche, sections clés et alertes intelligentes.
/// Absente si le briefing n'est pas activé dans les préférences HELM AI.
class BriefingCard extends ConsumerWidget {
  const BriefingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiBriefingProvider);
    // Première visite connectée sans vérification serveur → vérifier une
    // fois (le briefing peut avoir été activé depuis un autre appareil ou
    // pendant la session sans redémarrer l'application).
    if (!state.checked &&
        !state.loading &&
        ref.watch(sessionProvider).isConnected) {
      Future.microtask(
          () => ref.read(aiBriefingProvider.notifier).refresh());
    }
    if (!state.enabled || state.briefing == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final briefing = state.briefing!;
    final unread =
        state.alerts.where((a) => a.status == 'UNREAD').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: LHCard(
        onTap: () => showBriefingSheet(context),
        accent: LHColors.or,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: LHColors.or.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(LHRadius.md),
                ),
                child: const Icon(Icons.wb_twilight_rounded,
                    color: LHColors.or, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Briefing HELM AI',
                          style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: LHColors.or)),
                      const SizedBox(height: 2),
                      Text(briefing.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: LHColors.neutre),
            ]),
            const SizedBox(height: 10),
            Text(briefing.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final chip in _chips(briefing, theme))
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(LHRadius.xl),
                    ),
                    child: Text(chip,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            if (state.offline) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.cloud_off_outlined,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Généré hors connexion — mise à jour au prochain passage en ligne',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ] else if (unread > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.notifications_active_rounded,
                    size: 15, color: LHColors.alerte),
                const SizedBox(width: 6),
                Text('$unread alerte(s) à consulter',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: LHColors.alerte,
                        fontWeight: FontWeight.w700)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  /// Pastilles de synthèse du briefing (max 4, lisibles d'un coup d'œil).
  List<String> _chips(LhAiBriefing b, ThemeData theme) {
    final chips = <String>[];
    final agenda = b.sections['agenda'] as Map?;
    final agendaToday = (agenda?['today'] as List?) ?? [];
    if (agendaToday.isNotEmpty) chips.add('Agenda : ${agendaToday.length}');
    final tasks = b.sections['tasks'] as Map?;
    final overdue = (tasks?['overdueCount'] as num?)?.toInt() ?? 0;
    final dueToday = (tasks?['dueTodayCount'] as num?)?.toInt() ?? 0;
    if (overdue > 0) chips.add('En retard : $overdue');
    if (dueToday > 0) chips.add('Aujourd\'hui : $dueToday');
    final budgets = b.sections['budgets'] as List? ?? [];
    final hot = budgets
        .where((x) => ((x as Map)['consumedPercent'] as num? ?? 0) >= 80)
        .length;
    if (hot > 0) chips.add('Budgets : $hot à surveiller');
    final loans = b.sections['loans'] as List? ?? [];
    if (loans.isNotEmpty) chips.add('Prêts : ${loans.length}');
    final wellbeing = b.sections['wellbeing'] as Map?;
    if (wellbeing?['entriesCount'] != null &&
        (wellbeing?['entriesCount'] as num? ?? 0) > 0) {
      chips.add('Bien-être suivi');
    }
    if (chips.isEmpty) chips.add('Journée sous contrôle');
    return chips.take(4).toList();
  }
}

// ═══════════════════════ FEUILLE DE DÉTAIL ═══════════════════════

/// Briefing complet : accroche, sections détaillées, alertes intelligentes
/// (lecture / ignore), lien vers l'assistant et les préférences.
Future<void> showBriefingSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BriefingSheet(),
  );
}

class _BriefingSheet extends ConsumerWidget {
  const _BriefingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(aiBriefingProvider);
    final briefing = state.briefing;
    if (briefing == null) return const SizedBox.shrink();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(LHRadius.xl)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.wb_twilight_rounded,
                  color: LHColors.or, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Briefing du jour',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            Text('Votre vie, un seul gouvernail — ${briefing.date}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LHColors.or.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(LHRadius.lg),
                border: Border.all(color: LHColors.or.withValues(alpha: 0.35)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(briefing.headline,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(briefing.message,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.5)),
                  ]),
            ),
            const SizedBox(height: 20),
            ..._sections(context, briefing, theme),
            const SizedBox(height: 12),
            _AlertsBlock(alerts: state.alerts),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/assistant');
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Discuter avec HELM AI'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/ai-preferences');
              },
              child: const Text(
                  'Régler le briefing et les alertes (heure, seuil, périmètre)'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(
      BuildContext context, LhAiBriefing b, ThemeData theme) {
    final out = <Widget>[];

    void section(String title, IconData icon, Color color,
        List<Widget> rows) {
      if (rows.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ));
      out.addAll(rows);
    }

    final agenda = b.sections['agenda'] as Map?;
    final agendaToday = (agenda?['today'] as List? ?? []);
    section(
      'Agenda du jour',
      Icons.event_rounded,
      LHColors.electrique,
      [
        for (final e in agendaToday.take(5))
          _row(theme,
              (e as Map)['startTime']?.toString() ?? '',
              (e['title'] ?? 'Événement').toString()),
        if (agendaToday.isEmpty) _empty(theme, 'Aucun événement aujourd\'hui.'),
      ],
    );

    final tasks = b.sections['tasks'] as Map?;
    final topTasks = (tasks?['top'] as List? ?? []);
    section(
      'Tâches prioritaires',
      Icons.checklist_rounded,
      LHColors.navy,
      [
        for (final t in topTasks.take(4))
          _row(
              theme,
              ((t as Map)['overdue'] == true ? '⚠ retard — ' : '') +
                  ((t['priority'] ?? '') as String),
              (t['title'] ?? 'Tâche').toString()),
        if (topTasks.isEmpty) _empty(theme, 'Aucune tâche ouverte — bravo.'),
      ],
    );

    final finance = b.sections['finance'] as Map?;
    if (finance != null) {
      String fmtXof(num v) =>
          '${v.round().toString().replaceAllMapped(RegExp(r'^(\d+)(\d{3})$'), (m) => '${m[1]} ${m[2]}')} FCFA';
      section(
        'Finances du mois',
        Icons.account_balance_wallet_rounded,
        LHColors.vertSucces, [
        _row(theme, 'Recettes', fmtXof((finance['income'] as num? ?? 0))),
        _row(theme, 'Dépenses', fmtXof((finance['expense'] as num? ?? 0))),
        _row(theme, 'Solde', fmtXof((finance['balance'] as num? ?? 0))),
      ]);
    }

    final budgets = (b.sections['budgets'] as List? ?? []);
    section(
      'Budgets actifs',
      Icons.savings_rounded,
      LHColors.or,
      [
        for (final x in budgets.take(4))
          _row(
              theme,
              '${((x as Map)['consumedPercent'] as num? ?? 0)} %',
              '${(x['name'] ?? 'Budget')} — ${(x['remaining'] as num? ?? 0).round()} FCFA restants',
              warn: ((x['consumedPercent'] as num? ?? 0) >= 80)),
        if (budgets.isEmpty) _empty(theme, 'Aucun budget actif sur la période.'),
      ],
    );

    final loans = (b.sections['loans'] as List? ?? []);
    section(
      'Prêts & emprunts',
      Icons.handshake_rounded,
      LHColors.electrique,
      [
        for (final l in loans.take(3))
          _row(
              theme,
              (l as Map)['direction'] == 'LENT' ? 'Prêté' : 'Emprunté',
              '${(l['counterparty'] ?? '')} — ${(l['principalAmount'] as num? ?? 0).round()} FCFA'),
        if (loans.isEmpty) _empty(theme, 'Aucun prêt actif.'),
      ],
    );

    final wellbeing = b.sections['wellbeing'] as Map?;
    if (wellbeing != null && (wellbeing['entriesCount'] as num? ?? 0) > 0) {
      section(
        'Bien-être (consenti)',
        Icons.self_improvement_rounded,
        LHColors.vertSucces, [
        _row(theme, 'Humeur moyenne',
            '${(wellbeing['moodAverage'] as num? ?? 0)}/5 sur 14 jours'),
      ]);
    }

    return out;
  }

  Widget _row(ThemeData theme, String lead, String text, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 92,
          child: Text(lead,
              style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: warn ? LHColors.alerte : theme.colorScheme.primary)),
        ),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
        ),
      ]),
    );
  }

  Widget _empty(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}

/// Bloc des alertes intelligentes (dans la feuille briefing).
class _AlertsBlock extends ConsumerWidget {
  const _AlertsBlock({required this.alerts});
  final List<LhAiAlert> alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visible =
        alerts.where((a) => a.status != 'DISMISSED').toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(aiBriefingProvider.notifier);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.notifications_active_rounded,
            size: 18, color: LHColors.alerte),
        const SizedBox(width: 8),
        Text('Alertes intelligentes',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      for (final a in visible.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(LHRadius.md),
              border: Border.all(
                  color: a.severity == 'IMPORTANT'
                      ? LHColors.alerte.withValues(alpha: 0.55)
                      : Colors.transparent),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                        a.severity == 'IMPORTANT'
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: a.severity == 'IMPORTANT'
                            ? LHColors.alerte
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(a.body,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(height: 1.4)),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (a.status == 'UNREAD')
                      TextButton(
                        onPressed: () => notifier.markRead(a),
                        child: const Text('Marquer lue'),
                      ),
                    TextButton(
                      onPressed: () => notifier.dismiss(a),
                      child: const Text('Ignorer'),
                    ),
                  ]),
                ]),
          ),
        ),
    ]);
  }
}

// ═══════════════════════ ALERTES INTELLIGENTES (centre de notifications) ═══════════════════════

/// Alertes intelligentes serveur — chargées à l'ouverture du centre de
/// notifications (connecté), absentes hors ligne (aucun artifice).
final aiAlertsProvider =
    FutureProvider.autoDispose<List<LhAiAlert>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.isConnected) return [];
  return ref.watch(apiClientProvider).aiListAlerts();
});

/// Section « Alertes intelligentes HELM AI » du centre de notifications —
/// lecture / ignore directes, badge de sévérité, jamais intrusive.
class AiAlertsSection extends ConsumerWidget {
  const AiAlertsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alertsAsync = ref.watch(aiAlertsProvider);
    final alerts =
        alertsAsync.valueOrNull?.where((a) => a.status != 'DISMISSED').toList() ??
            [];
    if (alerts.isEmpty) return const SizedBox.shrink();

    final client = ref.read(apiClientProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: LHColors.or),
          const SizedBox(width: 6),
          Text('Alertes intelligentes HELM AI',
              style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800, color: LHColors.or)),
          const Spacer(),
          TextButton(
            onPressed: () => ref.invalidate(aiAlertsProvider),
            child: const Text('Actualiser'),
          ),
        ]),
      ),
      for (final a in alerts.take(6))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: LHCard(
            accent: a.severity == 'IMPORTANT' ? LHColors.alerte : null,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                        a.severity == 'IMPORTANT'
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: a.severity == 'IMPORTANT'
                            ? LHColors.alerte
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(a.title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    if (a.status == 'UNREAD')
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: LHColors.or, shape: BoxShape.circle),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text(a.body,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(height: 1.4)),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (a.status == 'UNREAD')
                      TextButton(
                        onPressed: () async {
                          try {
                            await client.aiMarkAlertRead(a.id);
                          } catch (_) {}
                          ref.invalidate(aiAlertsProvider);
                        },
                        child: const Text('Marquer lue'),
                      ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await client.aiDismissAlert(a.id);
                        } catch (_) {}
                        ref.invalidate(aiAlertsProvider);
                      },
                      child: const Text('Ignorer'),
                    ),
                  ]),
                ]),
          ),
        ),
      const SizedBox(height: 4),
    ]);
  }
}

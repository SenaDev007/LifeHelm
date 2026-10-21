import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth.dart';
import '../tasks/tasks.dart';
import '../../core/db/database.dart';
import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

/// HELM AI — Assistant central (Dossier 17, Phase 1).
///
/// Assistant conversationnel transversal : comprend la situation de
/// l'utilisateur à partir de ses données synchronisées (finances, tâches,
/// agenda, projets, échéances), répond en français avec des faits vérifiés
/// et peut PROPOSER des actions — jamais exécutées sans confirmation
/// explicite (D17.2 §6 : cycle proposé → confirmé → exécuté).
///
/// Confidentialité (décisions validées D17 §1) :
/// - accès limité par défaut : le journal de bien-être et la messagerie
///   ne sont jamais transmis au modèle ;
/// - indisponibilité explicite : jamais de fausse réponse hors ligne.
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key, this.moduleContext});

  /// Module d'origine pour l'accès contextuel (affichage uniquement —
  /// le contexte ne donne jamais de droits supplémentaires).
  final String? moduleContext;

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  LhAiStatus? _status;
  String? _conversationId;
  List<LhAiMessage> _messages = [];
  bool _sending = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = ref.read(sessionProvider);
    if (!session.isConnected) {
      setState(() => _loading = false);
      return;
    }
    try {
      final status = await ref.read(apiClientProvider).aiStatus();
      if (!mounted) return;
      setState(() => _status = status);
      // Reprend la conversation la plus récente, s'il y en a une.
      final conversations = await ref.read(apiClientProvider).aiListConversations();
      if (!mounted) return;
      if (conversations.isNotEmpty) {
        final conv = await ref
            .read(apiClientProvider)
            .aiGetConversation(conversations.first.id);
        if (!mounted) return;
        setState(() {
          _conversationId = conv?.id;
          _messages = conv?.messages ?? [];
          _loading = false;
        });
        _scrollToEnd();
        return;
      }
    } catch (_) {
      // Serveur injoignable : l'écran reste honnête sur l'état.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newConversation() async {
    try {
      final id = await ref.read(apiClientProvider).aiCreateConversation(
            entryPoint: widget.moduleContext != null
                ? 'MODULE_CONTEXTUAL'
                : 'CENTRAL_ASSISTANT',
            moduleContext: widget.moduleContext,
          );
      setState(() {
        _conversationId = id;
        _messages = [];
      });
    } catch (e) {
      if (mounted) lhToast(context, apiErrorText(e));
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();

    setState(() {
      _sending = true;
      _messages = [..._messages, LhAiMessage(role: 'USER', content: text)];
    });
    _scrollToEnd();

    try {
      var conversationId = _conversationId;
      if (conversationId == null) {
        conversationId = await ref.read(apiClientProvider).aiCreateConversation(
              entryPoint: widget.moduleContext != null
                  ? 'MODULE_CONTEXTUAL'
                  : 'CENTRAL_ASSISTANT',
              moduleContext: widget.moduleContext,
            );
      }
      final answer =
          await ref.read(apiClientProvider).aiSendMessage(conversationId, text);
      if (!mounted) return;
      setState(() {
        _conversationId = conversationId;
        _messages = [
          ..._messages,
          LhAiMessage(
            role: 'ASSISTANT',
            content: answer.answer,
            answerType: answer.answerType,
            structured: {
              'facts': [
                for (final f in answer.facts) {'key': f.key, 'value': f.value}
              ],
              'uncertainties': answer.uncertainties,
              'assumptions': answer.assumptions,
              'safetyFlags': answer.safetyFlags,
              'degraded': answer.degraded,
              'proposedActions': [
                // Actions Phase 2 : on conserve l'intégralité (id serveur,
                // payloadHash, summary, statut) — la confirmation passera
                // par /ai/actions/:id/confirm (D17.2 §6).
                for (final a in answer.proposedActions)
                  {
                    'id': a.id,
                    'actionType': a.actionType,
                    'title': a.title,
                    'summary': a.summary,
                    'payloadHash': a.payloadHash,
                    'status': a.status,
                    'dueDate': a.dueDate,
                    'priority': a.priority,
                  }
              ],
            },
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Le message utilisateur reste ; l'erreur est affichée honnêtement.
        _messages = [
          ..._messages,
          LhAiMessage(
            role: 'ASSISTANT',
            content: apiErrorText(e),
            answerType: 'TEMPORARY_UNAVAILABLE',
          ),
        ];
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ─────────────────────── Actions proposées (D17.2 §6) ───────────────────────

  /// Cycle : la proposition est présentée, l'utilisateur confirme, puis
  /// SEULEMENT l'action est exécutée.
  ///  - action SERVEUR (id + payloadHash) : POST /ai/actions/:id/confirm —
  ///    le serveur écrit le brouillon dans Resource + SyncChange ; le mobile
  ///    le récupère au prochain pull (canal de sync habituel, D01.4).
  ///  - action LOCALE (repli, CREATE_TASK sans id) : création Drift locale
  ///    + journalisation pour la synchronisation (Phase 1).
  Future<void> _applyProposedAction(Map<String, dynamic> action) async {
    final actionId = action['id'] as String?;
    final payloadHash = action['payloadHash'] as String?;
    if (actionId != null && payloadHash != null) {
      await _confirmServerAction(actionId, payloadHash, action);
      return;
    }
    await _applyLocalTask(action);
  }

  /// Confirmation d'une action serveur — idempotence par UUID de tentative.
  Future<void> _confirmServerAction(
      String actionId, String payloadHash, Map<String, dynamic> action) async {
    final actionType = (action['actionType'] as String?) ?? '';
    final title = (action['title'] as String?) ?? 'Action proposée';
    final summary = (action['summary'] as String?) ?? '';

    final ok = await lhConfirm(
      context,
      title: _confirmDialogTitle(actionType),
      message: '« $title »'
          '${summary.isNotEmpty ? '\n$summary' : ''}'
          '\n\nAprès confirmation, HELM AI prépare cette écriture et la '
          'synchronise avec vos appareils. Vous pourrez la modifier ou '
          'l\'annuler dans le module concerné.',
      confirmLabel: 'Confirmer',
    );
    if (!ok || !mounted) return;

    try {
      final detail = await ref.read(apiClientProvider).aiConfirmAction(
            actionId,
            payloadHash,
            const Uuid().v4(), // clé d'idempotence : UNE par tentative
          );
      if (!mounted) return;
      _updateActionStatus(actionId, detail.status);
      lhToast(
        context,
        detail.status == 'SUCCEEDED'
            ? 'Action confirmée — synchronisation en cours.'
            : 'Action : ${detail.status}',
      );
    } catch (e) {
      if (!mounted) return;
      final code = e is LhApiException ? e.code : null;
      _updateActionStatus(actionId, _statusForError(code));
      lhToast(context, _errorText(code, apiErrorText(e)));
    }
  }

  /// Met à jour le statut affiché d'une action dans la bulle.
  void _updateActionStatus(String actionId, String? status) {
    if (status == null) return;
    setState(() {
      _messages = [
        for (final m in _messages)
          (m.role == 'ASSISTANT' && m.structured?['proposedActions'] != null)
              ? LhAiMessage(
                  role: m.role,
                  content: m.content,
                  answerType: m.answerType,
                  structured: {
                    ...m.structured!,
                    'proposedActions': [
                      for (final a
                          in (m.structured!['proposedActions'] as List))
                        if (a is Map && a['id'] == actionId)
                          {...a, 'status': status}
                        else
                          a,
                    ],
                  },
                )
              : m,
      ];
    });
  }

  String _statusForError(String? code) {
    switch (code) {
      case 'AI_ACTION_EXPIRED':
        return 'EXPIRED';
      case 'AI_ACTION_REJECTED':
      case 'AI_ACTION_ALREADY_PROCESSED':
        return 'ALREADY_PROCESSED';
      case 'AI_ACTION_STALE':
        return 'STALE';
      default:
        return 'FAILED';
    }
  }

  String _errorText(String? code, String fallback) {
    switch (code) {
      case 'AI_ACTION_EXPIRED':
        return 'Délai dépassé — la proposition a expiré (15 minutes). '
            'Reformulez votre demande pour obtenir une nouvelle proposition.';
      case 'AI_ACTION_STALE':
        return 'Les données ont changé depuis la proposition. '
            'Demandez une nouvelle proposition à HELM AI.';
      case 'AI_ACTION_ALREADY_PROCESSED':
        return 'Cette action a déjà été traitée.';
      case 'AI_ACTION_REJECTED':
        return 'Cette action a été refusée.';
      case 'AI_TOOL_VALIDATION_FAILED':
        return 'Les paramètres de l\'action ne sont plus valides '
            '(élément supprimé ou modifié). Demandez une nouvelle proposition.';
      default:
        return fallback;
    }
  }

  String _confirmDialogTitle(String actionType) {
    switch (actionType) {
      case 'PROPOSE_EVENT_CHANGE':
        return 'Déplacer cet événement ?';
      case 'PROPOSE_FINANCIAL_CORRECTION':
        return 'Enregistrer cette correction ?';
      default:
        return 'Créer cette tâche ?';
    }
  }

  /// Refus explicite d'une action serveur (traçable côté audit).
  Future<void> _rejectServerAction(Map<String, dynamic> action) async {
    final actionId = action['id'] as String?;
    if (actionId == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .aiCancelAction(actionId, reason: 'Refusé depuis l\'assistant');
      if (!mounted) return;
      _updateActionStatus(actionId, 'CANCELLED');
    } catch (_) {
      _updateActionStatus(actionId, 'CANCELLED');
    }
  }

  /// Repli local (Phase 1) : création directe d'une tâche Drift.
  Future<void> _applyLocalTask(Map<String, dynamic> action) async {
    final title = (action['title'] as String?) ?? '';
    if (title.isEmpty) return;
    final dueDate = action['dueDate'] as String?;
    final priority = (action['priority'] as String?) ?? 'NORMAL';

    final ok = await lhConfirm(
      context,
      title: 'Créer cette tâche ?',
      message: '« $title »'
          '${dueDate != null ? '\nÉchéance : $dueDate' : ''}'
          '\nPriorité : ${_priorityLabel(priority)}'
          '\n\nLa tâche sera créée dans l\'espace actif et synchronisée.',
      confirmLabel: 'Créer la tâche',
    );
    if (!ok || !mounted) return;

    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final task = Task(
      id: 'task_${now.microsecondsSinceEpoch}',
      spaceId: ref.read(activeSpaceIdProvider),
      title: title,
      notes: 'Proposée par HELM AI',
      status: 'TODO',
      priority: priority,
      startDate: null,
      dueDate: dueDate, // date civile ISO yyyy-MM-dd (texte)
      position: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveTask(task);
    if (mounted) {
      lhToast(context, 'Tâche « $title » créée — visible dans Activités.');
    }
  }

  String _priorityLabel(String p) => switch (p) {
        'HIGH' => 'Haute',
        'URGENT' => 'Urgente',
        'LOW' => 'Basse',
        _ => 'Normale',
      };

  // ───────────────────────────────── UI ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [LHColors.navy, LHColors.electrique]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('HELM AI',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              _status == null
                  ? 'Assistant intelligent LifeHelm'
                  : _status!.available
                      ? 'Assistant disponible'
                      : 'Assistant distant indisponible',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Préférences HELM AI',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push('/ai-preferences'),
          ),
          if (_conversationId != null)
            IconButton(
              tooltip: 'Nouvelle conversation',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _newConversation,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !session.isConnected
              ? const _NotConnected()
              : Column(children: [
                  if (_status != null && !_status!.available)
                    _offlineBanner(theme),
                  Expanded(child: _buildConversation(theme)),
                  _buildInputBar(theme),
                ]),
    );
  }

  Widget _offlineBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: LHColors.orange.withValues(alpha: 0.12),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: LHColors.orange, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'HELM AI nécessite une connexion au serveur. Les règles locales '
            'et les rappels de LifeHelm continuent de fonctionner.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ]),
    );
  }

  Widget _buildConversation(ThemeData theme) {
    if (_messages.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: LHSpacing.xl),
        _HeroCard(theme: theme),
        const SizedBox(height: LHSpacing.xl),
        SectionHeader('Suggestions', overline: 'Pour démarrer'),
        ..._suggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LHCard(
                onTap: () => _send(s.$1),
                child: Row(children: [
                  Icon(s.$2, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.$1,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 16, color: LHColors.neutre),
                ]),
              ),
            )),
        const SizedBox(height: LHSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'HELM AI répond à partir de vos données synchronisées (finances, '
            'tâches, agenda, projets, échéances). Le journal de bien-être et '
            'la messagerie restent privés et ne sont jamais analysés.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ),
      ]);
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _messages.length) {
          return const _ThinkingBubble();
        }
        final m = _messages[i];
        return m.role == 'USER'
            ? _UserBubble(text: m.content)
            : _AssistantBubble(
                message: m,
                onApplyAction: _applyProposedAction,
                onRejectAction: _rejectServerAction,
              );
      },
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
              top: BorderSide(color: theme.colorScheme.outline, width: 1)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Posez votre question à HELM AI…',
                prefixIcon: Icon(Icons.auto_awesome_outlined),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            onPressed: _sending ? null : () => _send(),
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: LHColors.navyInk))
                : const Icon(Icons.send_rounded, size: 18),
          ),
        ]),
      ),
    );
  }

  static const List<(String, IconData)> _suggestions = [
    ('Où en suis-je financièrement ce mois-ci ?', Icons.savings_outlined),
    ('Quelles sont mes priorités aujourd\'hui ?', Icons.flag_outlined),
    ('Quels budgets approchent leur seuil d\'alerte ?',
        Icons.warning_amber_outlined),
    ('Mon agenda des 7 prochains jours', Icons.calendar_month_outlined),
    ('Résume l\'avancement de mes projets', Icons.insights_outlined),
    ('Mes échéances financières à venir', Icons.event_available_outlined),
  ];
}

// ══════════════════════════ SOUS-Composants ══════════════════════════

class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LHSpacing.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: LHColors.orTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: LHColors.orDeep, size: 36),
          ),
          const SizedBox(height: LHSpacing.lg),
          Text('HELM AI nécessite un compte',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: LHSpacing.sm),
          Text(
            'Connectez-vous pour activer l\'assistant intelligent : il analyse '
            'vos données synchronisées pour vous aider à piloter vos journées, '
            'vos finances et vos projets.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: LHSpacing.xl),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Se connecter'),
          ),
        ]),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LHColors.navy,
              LHColors.navy.withValues(alpha: 0.82),
            ]),
        borderRadius: BorderRadius.circular(LHRadius.xl),
      ),
      child: Column(children: [
        const Icon(Icons.auto_awesome_rounded, color: LHColors.or, size: 34),
        const SizedBox(height: LHSpacing.md),
        Text(
          'Le cerveau intelligent de votre vie',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: LHSpacing.sm),
        Text(
          'HELM AI comprend votre situation, détecte ce qui mérite votre '
          'attention, conseille et anticipe — en respectant vos données et '
          'vos décisions.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85), height: 1.5),
        ),
      ]),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(LHRadius.lg),
            topRight: Radius.circular(LHRadius.lg),
            bottomLeft: Radius.circular(LHRadius.lg),
            bottomRight: Radius.circular(LHRadius.lg - 6),
          ),
        ),
        child: Text(text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onPrimary)),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(LHRadius.lg),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Text('HELM AI analyse vos données…',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Réponse assistant : texte + faits vérifiés + incertitudes + actions
/// proposées (cycle de confirmation D17.2 §6).
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.onApplyAction,
    required this.onRejectAction,
  });

  final LhAiMessage message;
  final Future<void> Function(Map<String, dynamic>) onApplyAction;
  final Future<void> Function(Map<String, dynamic>) onRejectAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final structured = message.structured;
    final facts = (structured?['facts'] as List? ?? [])
        .map((f) => Map<String, dynamic>.from(f as Map))
        .toList();
    final uncertainties =
        (structured?['uncertainties'] as List? ?? []).cast<String>();
    final actions = (structured?['proposedActions'] as List? ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    final unavailable = message.answerType == 'TEMPORARY_UNAVAILABLE';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 28),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
              color: unavailable
                  ? LHColors.orange.withValues(alpha: 0.5)
                  : theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(LHRadius.lg),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [LHColors.navy, LHColors.electrique]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  unavailable ? 'Indisponible' : 'HELM AI',
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          unavailable ? LHColors.orange : LHColors.navy),
                ),
              ]),
              const SizedBox(height: 10),
              Text(message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in facts)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: LHColors.orTint,
                          borderRadius: BorderRadius.circular(LHRadius.full),
                          border: Border.all(
                              color: LHColors.or.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${f['key']} : ${f['value']}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: LHColors.orDeep,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
              if (uncertainties.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final u in uncertainties)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(u,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic)),
                      ),
                    ]),
                  ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Actions proposées',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final a in actions) _ActionCard(action: a, onApply: onApplyAction, onReject: onRejectAction),
              ],
            ]),
      ),
    );
  }
}

/// Carte d'action proposée — présentation et issue du cycle de
/// confirmation (D17.2 §6) : en attente → confirmée/refusée/expirée.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.action,
    required this.onApply,
    required this.onReject,
  });

  final Map<String, dynamic> action;
  final Future<void> Function(Map<String, dynamic>) onApply;
  final Future<void> Function(Map<String, dynamic>) onReject;

  IconData get _icon {
    switch (action['actionType'] as String? ?? '') {
      case 'PROPOSE_EVENT_CHANGE':
        return Icons.event_rounded;
      case 'PROPOSE_FINANCIAL_CORRECTION':
        return Icons.currency_exchange_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color get _iconColor {
    switch (action['actionType'] as String? ?? '') {
      case 'PROPOSE_EVENT_CHANGE':
        return LHColors.electrique;
      case 'PROPOSE_FINANCIAL_CORRECTION':
        return LHColors.orange;
      default:
        return LHColors.navy;
    }
  }

  String get _statusLabel {
    switch (action['status'] as String? ?? '') {
      case 'SUCCEEDED':
        return 'Confirmée — synchronisée';
      case 'CANCELLED':
        return 'Refusée';
      case 'EXPIRED':
        return 'Expirée';
      case 'ALREADY_PROCESSED':
        return 'Déjà traitée';
      case 'STALE':
        return 'Données changées — à reproposer';
      case 'FAILED':
        return 'Échec';
      default:
        return '';
    }
  }

  Color? get _statusColor {
    switch (action['status'] as String? ?? '') {
      case 'SUCCEEDED':
        return LHColors.vertSucces;
      case 'CANCELLED':
      case 'EXPIRED':
      case 'ALREADY_PROCESSED':
        return themeColors;
      case 'STALE':
      case 'FAILED':
        return LHColors.orange;
      default:
        return null;
    }
  }

  Color get themeColors => const Color(0xFF64748B); // gris ardoise

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = action['status'] as String?;
    final done = status != null && status != 'AWAITING_CONFIRMATION';
    final summary = action['summary'] as String?;
    final statusColor = _statusColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(LHRadius.md),
        border: Border.all(
            color: status == 'SUCCEEDED'
                ? LHColors.vertSucces.withValues(alpha: 0.5)
                : theme.colorScheme.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon, color: done && statusColor != null ? statusColor : _iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action['title'] as String? ?? '',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (summary != null && summary.isNotEmpty)
                    Text(summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  if (!done && action['dueDate'] != null)
                    Text(
                        'Échéance : ${action['dueDate']} · Priorité : ${action['priority'] ?? 'NORMAL'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ]),
          ),
          if (!done) ...[
            if (action['id'] != null)
              TextButton(
                onPressed: () => onReject(action),
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant),
                child: const Text('Refuser'),
              ),
            FilledButton.tonal(
              onPressed: () => onApply(action),
              child: const Text('Confirmer'),
            ),
          ] else
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  status == 'SUCCEEDED'
                      ? Icons.check_circle_rounded
                      : status == 'CANCELLED'
                          ? Icons.cancel_rounded
                          : Icons.schedule_rounded,
                  size: 15,
                  color: statusColor ?? theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Flexible(
                child: Text(_statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor ?? theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
        ]),
      ]),
    );
  }
}

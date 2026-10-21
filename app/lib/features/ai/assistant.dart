import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              'proposedActions': [
                for (final a in answer.proposedActions)
                  {
                    'actionType': a.actionType,
                    'title': a.title,
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

  // ─────────────────────── Action proposée → tâche locale ───────────────────────

  /// Cycle D17.2 §6 : la proposition est présentée, l'utilisateur confirme,
  /// puis SEULEMENT la tâche est créée localement (source de vérité) et
  /// journalisée pour la synchronisation.
  Future<void> _applyProposedAction(Map<String, dynamic> action) async {
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
                      ? 'Assistant disponible — Phase 1'
                      : 'Assistant distant indisponible',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ]),
        actions: [
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
                priorityLabel: _priorityLabel,
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
    required this.priorityLabel,
  });

  final LhAiMessage message;
  final Future<void> Function(Map<String, dynamic>) onApplyAction;
  final String Function(String) priorityLabel;

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
                for (final a in actions)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(LHRadius.md),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a['title'] as String? ?? '',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              if (a['dueDate'] != null)
                                Text(
                                    'Échéance : ${a['dueDate']} · ${priorityLabel(a['priority'] as String? ?? 'NORMAL')}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme
                                            .onSurfaceVariant)),
                            ]),
                      ),
                      TextButton(
                        onPressed: () => onApplyAction(a),
                        child: const Text('Créer'),
                      ),
                    ]),
                  ),
              ],
            ]),
      ),
    );
  }
}

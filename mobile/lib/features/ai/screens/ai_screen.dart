import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/ai_providers.dart';

class AIScreen extends ConsumerStatefulWidget {
  const AIScreen({super.key});

  @override
  ConsumerState<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends ConsumerState<AIScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this, initialIndex: 0);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: LifeHelmColors.accent),
            SizedBox(width: 8),
            Text('HELM AI'),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Insights', icon: Icon(Icons.lightbulb)),
            Tab(text: 'Chat', icon: Icon(Icons.chat)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                await ref.read(aiRepositoryProvider).refreshInsights();
                ref.invalidate(aiInsightsProvider);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_InsightsTab(), _ChatTab()],
      ),
    );
  }
}

// ---------------- INSIGHTS TAB ----------------
class _InsightsTab extends ConsumerWidget {
  const _InsightsTab();

  Color _severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL': return LifeHelmColors.danger;
      case 'WARNING': return LifeHelmColors.warning;
      case 'SUCCESS': return LifeHelmColors.success;
      case 'INFO':
      default: return LifeHelmColors.info;
    }
  }

  IconData _categoryIcon(String? cat) {
    switch ((cat ?? '').toUpperCase()) {
      case 'FINANCE': return Icons.account_balance_wallet;
      case 'HEALTH': return Icons.favorite;
      case 'ROUTINES': return Icons.today;
      case 'GOALS': return Icons.flag;
      case 'CAREER': return Icons.work;
      case 'RELATIONS': return Icons.people;
      default: return Icons.lightbulb;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(aiInsightsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(aiInsightsProvider),
      child: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
            const SizedBox(height: 16),
            Text('Erreur: $e', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(aiInsightsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
        data: (insights) {
          if (insights.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 64, color: LifeHelmColors.textTertiary),
                    const SizedBox(height: 16),
                    const Text('Aucun insight pour le moment'),
                    const SizedBox(height: 8),
                    const Text('HELM AI analyse tes données en continu', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final ins = insights[i];
              final severity = (ins['severity'] as String?) ?? 'INFO';
              final color = _severityColor(severity);
              final title = ins['title'] as String? ?? 'Insight';
              final message = ins['message'] as String? ?? '';
              final category = ins['category'] as String?;
              final read = (ins['read'] as bool?) ?? false;
              return Card(
                child: InkWell(
                  onTap: () async {
                    final id = ins['id'] as String?;
                    if (id != null && !read) {
                      try {
                        await ref.read(aiRepositoryProvider).markInsightRead(id);
                        ref.invalidate(aiInsightsProvider);
                      } catch (_) {}
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_categoryIcon(category), color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                  ),
                                  if (!read)
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(message, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                              if (category != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${category[0]}${category.substring(1).toLowerCase()}',
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- CHAT TAB ----------------
class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab();

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  String? _conversationId;
  bool _isSending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(content: text, role: 'user'));
      _isSending = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      final repo = ref.read(aiRepositoryProvider);
      if (_conversationId == null) {
        final conv = await repo.createConversation();
        _conversationId = conv['id'] as String?;
      }
      // Streaming simulé : on montre un message "typing" puis on ajoute la réponse après 500ms
      setState(() {
        _messages.add(_ChatMessage(content: '…', role: 'assistant', typing: true));
      });
      _scrollToBottom();

      final reply = await repo.sendMessage(_conversationId!, text);

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _messages.removeLast(); // remove typing indicator
        final content = reply['content'] as String? ?? 'Désolé, je n\'ai pas pu répondre.';
        _messages.add(_ChatMessage(content: content, role: 'assistant'));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        // remove typing indicator if present
        if (_messages.isNotEmpty && _messages.last.typing) {
          _messages.removeLast();
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _messages.isEmpty
          ? _EmptyChat(onSuggestion: (s) {
              _textCtrl.text = s;
              _send();
            })
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? LifeHelmColors.primary : LifeHelmColors.bgCard,
                      border: isUser ? null : Border.all(color: LifeHelmColors.textTertiary.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    child: m.typing
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (i) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: _TypingDot(delay: i * 200),
                            )),
                          )
                        : Text(
                            m.content,
                            style: TextStyle(
                              color: isUser ? Colors.white : LifeHelmColors.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: LifeHelmColors.bgCard,
            border: Border(top: BorderSide(color: LifeHelmColors.textTertiary.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              Expanded(
                child: LifeHelmTextField(
                  controller: _textCtrl,
                  label: '',
                  hint: 'Pose ta question à HELM AI...',
                  maxLines: 3,
                  minLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: LifeHelmColors.primary,
                  minimumSize: const Size(52, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({required this.content, required this.role, this.typing = false});
  final String content;
  final String role;
  final bool typing;
}

class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay});
  final int delay;

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: LifeHelmColors.textTertiary, shape: BoxShape.circle),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion});
  final void Function(String) onSuggestion;

  static const _suggestions = [
    'Comment améliorer mon score financier ?',
    'Quelles habitudes devrais-je suivre ?',
    'Analyse ma dernière semaine',
    'Conseils pour économiser',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: LifeHelmColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: LifeHelmColors.primary, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Discute avec HELM AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Ton conseiller de vie holistique\npossessionne tes données pour t\'aider',
              textAlign: TextAlign.center,
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _suggestions.map((s) {
                return ActionChip(
                  label: Text(s),
                  onPressed: () => onSuggestion(s),
                  backgroundColor: LifeHelmColors.bgCard,
                  side: const BorderSide(color: LifeHelmColors.textTertiary),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

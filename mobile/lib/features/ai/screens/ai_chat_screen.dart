// Écran de chat AI dédié (V2) — variante plein écran de l'onglet Chat de AIScreen.
// Prend un conversationId en param (peut être vide pour créer une nouvelle conversation).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../../ai/providers/ai_providers.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen>
    with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  late String? _conversationId = widget.conversationId.isEmpty ? null : widget.conversationId;
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

  Future<void> _send({String? overrideText}) async {
    final text = (overrideText ?? _textCtrl.text).trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(content: text, role: 'user'));
      _isSending = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      final repo = ref.read(aiRepositoryProvider);
      _conversationId ??= (await repo.createConversation())['id'] as String?;

      // Indicateur de typing
      setState(() {
        _messages.add(_ChatMessage(content: '…', role: 'assistant', typing: true));
      });
      _scrollToBottom();

      final reply = await repo.sendMessage(_conversationId!, text);

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _messages.removeLast(); // remove typing
        final content = reply['content'] as String? ?? 'Désolé, je n\'ai pas pu répondre.';
        _messages.add(_ChatMessage(content: content, role: 'assistant'));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
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
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: LifeHelmColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: LifeHelmColors.accent, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HELM AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    'Ton conseiller de vie',
                    style: TextStyle(fontSize: 11, color: LifeHelmColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _messages.isEmpty
          ? _EmptyChat(onSuggestion: (s) => _send(overrideText: s))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
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
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.80,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser ? LifeHelmColors.primary : LifeHelmColors.bgCard,
                            border: isUser
                                ? null
                                : Border.all(color: LifeHelmColors.textTertiary.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                            ),
                          ),
                          child: m.typing
                              ? _TypingIndicator(text: 'HELM AI réfléchit…')
                              : isUser
                                  ? Text(
                                      m.content,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                                    )
                                  : _MarkdownText(text: m.content),
                        ),
                      );
                    },
                  ),
                ),
                _InputBar(
                  controller: _textCtrl,
                  onSend: () => _send(),
                  isSending: _isSending,
                ),
              ],
            ),
    );
  }
}

// ---------- MESSAGES ----------

class _ChatMessage {
  _ChatMessage({required this.content, required this.role, this.typing = false});
  final String content;
  final String role;
  final bool typing;
}

// ---------- EMPTY STATE ----------

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion});
  final void Function(String) onSuggestion;

  static const _suggestions = [
    {'icon': Icons.savings, 'label': 'Comment améliorer mon épargne ?'},
    {'icon': Icons.bedtime, 'label': 'Analyse mon sommeil'},
    {'icon': Icons.flag, 'label': 'Conseils pour mes objectifs'},
    {'icon': Icons.trending_up, 'label': 'Comment réduire mes dépenses ?'},
    {'icon': Icons.fitness_center, 'label': 'Plan d\'activité de la semaine'},
    {'icon': Icons.today, 'label': 'Quelles habitudes suivre ?'},
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: LifeHelmColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: LifeHelmColors.accent, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Discute avec HELM AI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pose tes questions ou choisis une suggestion ci-dessous. HELM AI analyse tes données pour te donner des conseils personnalisés.',
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
                  label: Text(s['label'] as String),
                  avatar: Icon(s['icon'] as IconData, size: 16, color: LifeHelmColors.accent),
                  onPressed: () => onSuggestion(s['label'] as String),
                  backgroundColor: LifeHelmColors.bgCard,
                  side: const BorderSide(color: LifeHelmColors.textTertiary),
                  labelStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- INPUT BAR ----------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.isSending,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                controller: controller,
                label: '',
                hint: 'Pose ta question à HELM AI...',
                maxLines: 4,
                minLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isSending ? null : onSend,
              icon: isSending
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
    );
  }
}

// ---------- TYPING INDICATOR ----------

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.text});
  final String text;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trois points animés
        ...List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                // Décalage de phase pour chaque point
                final t = (_ctrl.value + i * 0.2) % 1.0;
                final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: LifeHelmColors.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          widget.text,
          style: const TextStyle(
            color: LifeHelmColors.textSecondary,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ---------- MARKDOWN SIMPLE ----------

/// Affiche du markdown simple : **gras** et listes (- item ou * item).
class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) {
        if (b.isList) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: b.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(fontSize: 14, color: LifeHelmColors.accent)),
                      Expanded(child: _RichSpan(text: item)),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: _RichSpan(text: b.text),
        );
      }).toList(),
    );
  }

  List<_Block> _parseBlocks(String src) {
    final lines = src.split('\n');
    final blocks = <_Block>[];
    final buffer = StringBuffer();
    final listBuffer = <String>[];

    void flushText() {
      if (buffer.isNotEmpty) {
        blocks.add(_Block(text: buffer.toString().trim(), isList: false));
        buffer.clear();
      }
    }

    void flushList() {
      if (listBuffer.isNotEmpty) {
        blocks.add(_Block(text: '', isList: true, items: List.from(listBuffer)));
        listBuffer.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushText();
        flushList();
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('• ')) {
        flushText();
        listBuffer.add(trimmed.substring(2).trim());
      } else {
        flushList();
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(trimmed);
      }
    }
    flushText();
    flushList();
    return blocks;
  }
}

class _Block {
  _Block({required this.text, required this.isList, this.items = const []});
  final String text;
  final bool isList;
  final List<String> items;
}

/// Affiche une string avec support du **gras** simple.
class _RichSpan extends StatelessWidget {
  const _RichSpan({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: _buildSpans(text, const TextStyle(fontSize: 14, color: LifeHelmColors.textPrimary, height: 1.4)),
    );
  }

  TextSpan _buildSpans(String src, TextStyle base) {
    final parts = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    var remaining = src;
    while (remaining.isNotEmpty) {
      final match = regex.firstMatch(remaining);
      if (match == null) {
        parts.add(TextSpan(text: remaining, style: base));
        break;
      }
      if (match.start > 0) {
        parts.add(TextSpan(text: remaining.substring(0, match.start), style: base));
      }
      parts.add(TextSpan(
        text: match.group(1),
        style: base.copyWith(fontWeight: FontWeight.w800),
      ));
      remaining = remaining.substring(match.end);
    }
    return TextSpan(children: parts, style: base);
  }
}

import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;

// ═══════════════════════════ LABELS & OUTILS (D12) ═══════════════════════════

/// Nom du membre local (persona « Vous », propriétaire des conversations).
const youMemberName = 'Vous';

/// Palette des couleurs de membres (D12 — simulation locale).
const memberColorHexes = ['#FFD700', '#10A878', '#5B8DD9', '#E8720C', '#8A6DD9'];

/// Réponses simulées des personas — messagerie interne uniquement (D12 §17.1-1).
const simulatedReplies = [
  'Bien noté !',
  'D\'accord, je m\'en occupe',
  'Parfait 👍',
  'Je te confirme ça aujourd\'hui',
  'Merci pour l\'info !',
  'On en reparle ce soir ?',
];

/// Emojis de réaction disponibles (MVP — D12 §17.1-5).
const reactionEmojis = ['❤️', '👍', '😂', '😮', '🙏'];

/// Prénom d'un membre (premier mot du nom affiché).
String memberFirstName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
}

Color hexToColor(String hex) =>
    Color(int.parse(hex.replaceFirst('#', '0xFF')));

/// Heure relative : « 14:32 », « Hier », « lun. », « 24/10/2026 ».
String relativeTime(DateTime d) {
  final diff = fmt.daysBetween(fmt.today(), DateTime(d.year, d.month, d.day));
  if (diff == 0) return fmt.formatTime(d);
  if (diff == -1) return 'Hier';
  if (diff > -7 && diff < 0) return fmt.weekdayShort(d);
  return fmt.formatShort(d);
}

/// Extrait tronqué pour les notifications.
String excerptOf(String body) =>
    body.length <= 60 ? body : '${body.substring(0, 57)}…';

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension MessagingQueries on AppDatabase {
  // —— Consultations ——

  /// Conversations de l'espace, de la plus récente à la plus ancienne.
  Stream<List<Conversation>> watchConversations(String spaceId) =>
      (select(conversations)
            ..where((c) => c.spaceId.equals(spaceId))
            ..orderBy([
              (c) => OrderingTerm(
                  expression: c.lastMessageAt, mode: OrderingMode.desc),
            ]))
          .watch();

  Stream<Conversation?> watchConversation(String id) =>
      (select(conversations)..where((c) => c.id.equals(id)))
          .watchSingleOrNull();

  Future<Conversation?> getConversation(String id) =>
      (select(conversations)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Stream<List<ConversationMember>> watchConvMembers(
          String conversationId) =>
      (select(conversationMembers)
            ..where((m) => m.conversationId.equals(conversationId)))
          .watch();

  Future<List<ConversationMember>> getConvMembers(
          String conversationId) =>
      (select(conversationMembers)
            ..where((m) => m.conversationId.equals(conversationId)))
          .get();

  /// Messages du plus ancien au plus récent (affichage en liste inversée).
  Stream<List<Message>> watchConvMessages(String conversationId) =>
      (select(messages)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([(m) => OrderingTerm(expression: m.sentAt)]))
          .watch();

  /// Réactions de tous les messages d'une conversation (jointure).
  Stream<List<MessageReaction>> watchConvReactions(
      String conversationId) {
    final query = select(messageReactions).join([
      innerJoin(messages, messages.id.equalsExp(messageReactions.messageId)),
    ]);
    query.where(messages.conversationId.equals(conversationId));
    return query.watch().map(
        (rows) => [for (final row in rows) row.readTable(messageReactions)]);
  }

  /// Membres de toutes les conversations d'un espace (pour la liste).
  Stream<List<ConversationMember>> watchSpaceConvMembers(String spaceId) {
    final query = select(conversationMembers).join([
      innerJoin(conversations,
          conversations.id.equalsExp(conversationMembers.conversationId)),
    ]);
    query.where(conversations.spaceId.equals(spaceId));
    return query.watch().map(
        (rows) => [for (final row in rows) row.readTable(conversationMembers)]);
  }

  /// Messages de toutes les conversations d'un espace (pour la liste).
  Stream<List<Message>> watchSpaceConvMessages(String spaceId) {
    final query = select(messages).join([
      innerJoin(conversations,
          conversations.id.equalsExp(messages.conversationId)),
    ]);
    query.where(conversations.spaceId.equals(spaceId));
    return query
        .watch()
        .map((rows) => [for (final row in rows) row.readTable(messages)]);
  }

  // —— Mutations ——

  /// Crée la conversation et ses membres : « Vous » OWNER + les autres
  /// MEMBER avec des couleurs variées.
  Future<Conversation> createConversation({
    required String spaceId,
    required String kind,
    String? title,
    required List<String> memberNames,
  }) async {
    final now = DateTime.now();
    final id = 'conv_${now.microsecondsSinceEpoch}';
    final conv = Conversation(
        id: id,
        spaceId: spaceId,
        title: title,
        kind: kind,
        readReceiptsEnabled: true,
        lastMessageAt: now,
        createdAt: now);
    await into(conversations).insert(conv);
    logOp('Conversation', id, 'CREATE', {'kind': kind, 'title': title});

    await into(conversationMembers).insert(ConversationMember(
        id: '${id}_vous',
        conversationId: id,
        displayName: youMemberName,
        role: 'OWNER',
        colorHex: memberColorHexes[0]));
    logOp('ConversationMember', '${id}_vous', 'CREATE',
        {'name': youMemberName, 'role': 'OWNER'});
    for (final (i, name) in memberNames.indexed) {
      final memberId = '${id}_m$i';
      await into(conversationMembers).insert(ConversationMember(
          id: memberId,
          conversationId: id,
          displayName: name,
          role: 'MEMBER',
          colorHex: memberColorHexes[i % memberColorHexes.length]));
      logOp('ConversationMember', memberId, 'CREATE', {'name': name});
    }
    return conv;
  }

  Future<void> touchConversation(String conversationId) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(lastMessageAt: Value(DateTime.now())));
    logOp('Conversation', conversationId, 'UPDATE', {'lastMessageAt': true});
  }

  /// Accusés de lecture configurables (D12 §17.1-7) — jamais inventés.
  Future<void> setReadReceiptsEnabled(
      String conversationId, bool enabled) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(readReceiptsEnabled: Value(enabled)));
    logOp('Conversation', conversationId, 'UPDATE',
        {'readReceiptsEnabled': enabled});
  }

  Future<void> setMessageStatus(String messageId, String status) async {
    await (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(status: Value(status)));
    logOp('Message', messageId, 'UPDATE', {'status': status});
  }

  /// Modification traçable (D12 §17.1-4).
  Future<void> editMessage(String messageId, String body) async {
    await (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(
            body: Value(body), editedAt: Value(DateTime.now())));
    logOp('Message', messageId, 'UPDATE', {'edited': true});
  }

  /// Suppression pour tous, traçable — le corps n'est plus affiché.
  Future<void> deleteMessageForAll(String messageId) async {
    await (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(deletedAt: Value(DateTime.now())));
    logOp('Message', messageId, 'DELETE', {'forEveryone': true});
  }

  /// Ajoute ou retire la réaction de [memberName] (bascule).
  Future<void> toggleReaction({
    required String messageId,
    required String memberName,
    required String emoji,
  }) async {
    final id = 'rea_${messageId}_${memberName}_$emoji';
    final existing = await (select(messageReactions)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    if (existing != null) {
      await (delete(messageReactions)..where((r) => r.id.equals(id))).go();
      logOp('MessageReaction', id, 'DELETE', {'emoji': emoji});
    } else {
      await into(messageReactions).insert(MessageReaction(
          id: id,
          messageId: messageId,
          memberName: memberName,
          emoji: emoji));
      logOp('MessageReaction', id, 'CREATE', {'emoji': emoji});
    }
  }

  /// À l'ouverture du chat : les messages non supprimés des autres membres
  /// passent READ — uniquement si les accusés de lecture sont activés.
  Future<int> markOthersMessagesRead(String conversationId) async {
    final members = await getConvMembers(conversationId);
    final you =
        members.where((m) => m.displayName == youMemberName).firstOrNull;
    if (you == null) return 0;
    final count = await (update(messages)..where((m) =>
            m.conversationId.equals(conversationId) &
            m.senderMemberId.equals(you.id).not() &
            m.deletedAt.isNull() &
            m.status.equals('READ').not()))
        .write(const MessagesCompanion(status: Value('READ')));
    if (count > 0) {
      logOp('Conversation', conversationId, 'UPDATE', {'markedRead': count});
    }
    return count;
  }

  /// Mes messages DELIVERED passent READ (lecture réelle simulée des autres).
  Future<int> markMyMessagesRead(String conversationId) async {
    final members = await getConvMembers(conversationId);
    final you =
        members.where((m) => m.displayName == youMemberName).firstOrNull;
    if (you == null) return 0;
    final count = await (update(messages)..where((m) =>
            m.conversationId.equals(conversationId) &
            m.senderMemberId.equals(you.id) &
            m.deletedAt.isNull() &
            m.status.equals('DELIVERED')))
        .write(const MessagesCompanion(status: Value('READ')));
    if (count > 0) {
      logOp('Conversation', conversationId, 'UPDATE', {'mineRead': count});
    }
    return count;
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final conversationsProvider =
    StreamProvider.family<List<Conversation>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchConversations(spaceId));

final spaceConvMembersProvider =
    StreamProvider.family<List<ConversationMember>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchSpaceConvMembers(spaceId));

final spaceConvMessagesProvider =
    StreamProvider.family<List<Message>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchSpaceConvMessages(spaceId));

final conversationProvider = StreamProvider.family<Conversation?, String>(
    (ref, id) => ref.watch(dbProvider).watchConversation(id));

final convMembersProvider =
    StreamProvider.family<List<ConversationMember>, String>(
        (ref, id) => ref.watch(dbProvider).watchConvMembers(id));

final convMessagesProvider = StreamProvider.family<List<Message>, String>(
    (ref, id) => ref.watch(dbProvider).watchConvMessages(id));

final convReactionsProvider =
    StreamProvider.family<List<MessageReaction>, String>(
        (ref, id) => ref.watch(dbProvider).watchConvReactions(id));

// ═══════════════════════════ ÉCRAN : LISTE ═══════════════════════════

/// Messagerie interne de l'espace actif — conversations directes et groupes
/// (D12). Simulation locale : les autres membres sont des personas.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final convsAsync = ref.watch(conversationsProvider(spaceId));
    final membersAsync = ref.watch(spaceConvMembersProvider(spaceId));
    final messagesAsync = ref.watch(spaceConvMessagesProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Messages'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewConversationSheet(context, ref, spaceId),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle conversation'),
      ),
      body: convsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (convs) {
          final members =
              membersAsync.valueOrNull ?? <ConversationMember>[];
          final messages = messagesAsync.valueOrNull ?? <Message>[];
          if (convs.isEmpty) {
            return EmptyState(
              illustration: 'assets/illustrations/messaging.png',
              icon: Icons.forum_outlined,
              message: 'Aucune conversation',
              hint:
                  'Démarrez une conversation directe ou créez un groupe pour '
                  'cet espace.',
              action: FilledButton.tonal(
                onPressed: () =>
                    _showNewConversationSheet(context, ref, spaceId),
                child: const Text('Nouvelle conversation'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 96),
            itemCount: convs.length,
            itemBuilder: (context, i) => _ConversationTile(
              conversation: convs[i],
              members: members
                  .where((m) => m.conversationId == convs[i].id)
                  .toList(),
              messages: messages
                  .where((m) => m.conversationId == convs[i].id)
                  .toList(),
            ),
          );
        },
      ),
    );
  }

  // —— Création (bottom sheet) ——

  Future<void> _showNewConversationSheet(
      BuildContext context, WidgetRef ref, String spaceId) {
    final correspondentCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final memberCtrl = TextEditingController();
    final names = <String>[];
    var kind = 'DIRECT';

    Future<void> create(BuildContext sheetCtx) async {
      final db = ref.read(dbProvider);
      final navigator = Navigator.of(sheetCtx);
      Conversation conv;
      if (kind == 'DIRECT') {
        final name = correspondentCtrl.text.trim();
        if (name.isEmpty) {
          lhToast(sheetCtx, 'Indiquez le nom du correspondant.');
          return;
        }
        conv = await db.createConversation(
            spaceId: spaceId, kind: 'DIRECT', memberNames: [name]);
      } else {
        final title = titleCtrl.text.trim();
        if (title.isEmpty) {
          lhToast(sheetCtx, 'Indiquez un titre de groupe.');
          return;
        }
        conv = await db.createConversation(
            spaceId: spaceId,
            kind: 'GROUP',
            title: title,
            memberNames: names);
      }
      navigator.pop();
      if (context.mounted) context.push('/chat/${conv.id}');
    }

    void addMember(void Function(void Function()) setSheet) {
      final n = memberCtrl.text.trim();
      if (n.isEmpty) return;
      setSheet(() {
        if (!names.contains(n)) names.add(n);
      });
      memberCtrl.clear();
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LHSpacing.screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nouvelle conversation',
                    style: Theme.of(sheetCtx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: LHSpacing.lg),
                  LhSegmented<String>(
                    value: kind,
                    items: const {'DIRECT': 'Directe', 'GROUP': 'Groupe'},
                    onChanged: (v) => setSheet(() => kind = v),
                  ),
                  const SizedBox(height: LHSpacing.lg),
                  if (kind == 'DIRECT')
                    TextField(
                      controller: correspondentCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nom du correspondant *'),
                    )
                  else ...[
                    TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Titre du groupe *'),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    if (names.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: LHSpacing.sm),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final n in names)
                              InputChip(
                                label: Text(n),
                                onDeleted: () =>
                                    setSheet(() => names.remove(n)),
                              ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: memberCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                labelText: 'Nom du membre'),
                            onSubmitted: (_) => addMember(setSheet),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ajouter le membre',
                          icon: const Icon(Icons.person_add_alt),
                          onPressed: () => addMember(setSheet),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: LHSpacing.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('Annuler'),
                      ),
                      const SizedBox(width: LHSpacing.sm),
                      FilledButton(
                        onPressed: () => create(sheetCtx),
                        child: const Text('Créer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      correspondentCtrl.dispose();
      titleCtrl.dispose();
      memberCtrl.dispose();
    });
  }
}

/// Ligne de conversation : avatar, titre, extrait, heure relative, non-lus.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.members,
    required this.messages,
  });

  final Conversation conversation;
  final List<ConversationMember> members;
  final List<Message> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others =
        members.where((m) => m.displayName != youMemberName).toList();
    final you =
        members.where((m) => m.displayName == youMemberName).firstOrNull;

    Message? last;
    for (final m in messages) {
      if (last == null || !m.sentAt.isBefore(last.sentAt)) last = m;
    }

    // Pastille non-lus : messages des autres membres non lus (hors supprimés).
    var unread = 0;
    if (you != null) {
      for (final m in messages) {
        if (m.senderMemberId != you.id &&
            m.deletedAt == null &&
            m.status != 'READ') {
          unread++;
        }
      }
    }

    final title = conversation.kind == 'GROUP'
        ? (conversation.title ?? 'Groupe')
        : (others.firstOrNull != null
            ? memberFirstName(others.first.displayName)
            : 'Conversation');
    final excerpt = last == null
        ? 'Nouvelle conversation'
        : (last.deletedAt != null ? 'Message supprimé' : last.body);
    final time = relativeTime(last?.sentAt ?? conversation.lastMessageAt);

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: LHSpacing.lg, vertical: 4),
      child: LHCard(
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: 10),
        onTap: () => context.push('/chat/${conversation.id}'),
        child: Row(
          children: [
            _conversationAvatar(others),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LHSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (unread > 0) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: LHColors.or,
                      borderRadius: BorderRadius.circular(LHRadius.full),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: LHColors.noir),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationAvatar(List<ConversationMember> others) {
    if (conversation.kind != 'GROUP') {
      final other = others.firstOrNull;
      return InitialsAvatar(
          name: other?.displayName ?? '?',
          color:
              other == null ? LHColors.neutre : hexToColor(other.colorHex));
    }
    // Groupe : double avatar (deux premiers autres membres).
    if (others.length >= 2) {
      final a = others[0];
      final b = others[1];
      return SizedBox(
        width: 50,
        height: 40,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: InitialsAvatar(
                  name: b.displayName,
                  color: hexToColor(b.colorHex),
                  size: 30),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: InitialsAvatar(
                  name: a.displayName,
                  color: hexToColor(a.colorHex),
                  size: 30),
            ),
          ],
        ),
      );
    }
    if (others.length == 1) {
      return InitialsAvatar(
          name: others[0].displayName,
          color: hexToColor(others[0].colorHex));
    }
    return const InitialsAvatar(name: 'Groupe');
  }
}

// ═══════════════════════════ ÉCRAN : CONVERSATION ═══════════════════════════

/// Conversation : bulles, mentions, réactions, accusés et simulations locales
/// (envoi, remise, lecture, réponses) — D12 §17.2.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final Random _random = Random();

  /// Annule proprement toutes les simulations à la fermeture du chat.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _simulateOpenRead();
  }

  @override
  void dispose() {
    _disposed = true;
    _input.dispose();
    super.dispose();
  }

  // ── Simulations locales (états fidèles aux événements réellement connus) ──

  /// Ouverture du chat : les messages des autres passent READ après 3-6 s,
  /// uniquement si les accusés de lecture sont activés (sinon ils restent
  /// DELIVERED — on n'invente jamais une lecture).
  void _simulateOpenRead() {
    Future.delayed(
        Duration(milliseconds: 3000 + _random.nextInt(3001)), () async {
      if (_disposed || !mounted) return;
      final db = ref.read(dbProvider);
      final conv = await db.getConversation(widget.id);
      if (conv == null || !conv.readReceiptsEnabled) return;
      if (_disposed || !mounted) return;
      await db.markOthersMessagesRead(widget.id);
    });
  }

  /// Envoi : PENDING → SENT (+600 ms) → DELIVERED (+1,8 s), uniquement si le
  /// chat reste ouvert.
  void _simulateDelivery(String messageId) {
    Future.delayed(const Duration(milliseconds: 600), () async {
      if (_disposed || !mounted) return;
      await ref.read(dbProvider).setMessageStatus(messageId, 'SENT');
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (_disposed || !mounted) return;
        await ref
            .read(dbProvider)
            .setMessageStatus(messageId, 'DELIVERED');
      });
    });
  }

  /// Lecture simulée de mes messages : READ avec 70 % de chance après 4-7 s
  /// (sinon ils restent DELIVERED) — jamais sans accusés activés.
  void _simulateMyRead() {
    Future.delayed(
        Duration(milliseconds: 4000 + _random.nextInt(3001)), () async {
      if (_disposed || !mounted) return;
      final db = ref.read(dbProvider);
      final conv = await db.getConversation(widget.id);
      if (conv == null || !conv.readReceiptsEnabled) return;
      if (_random.nextDouble() >= 0.7) return;
      if (_disposed || !mounted) return;
      await db.markMyMessagesRead(widget.id);
    });
  }

  /// Réponse simulée : 40 % de chance qu'un membre réponde après 3-7 s,
  /// avec notification in-app et horodatage de conversation.
  void _simulateReply() {
    if (_random.nextDouble() >= 0.4) return;
    Future.delayed(
        Duration(milliseconds: 3000 + _random.nextInt(4001)), () async {
      if (_disposed || !mounted) return;
      final db = ref.read(dbProvider);
      final conv = await db.getConversation(widget.id);
      if (conv == null) return;
      final members = await db.getConvMembers(widget.id);
      final others =
          members.where((m) => m.displayName != youMemberName).toList();
      if (others.isEmpty) return;
      final sender = others[_random.nextInt(others.length)];
      final body = simulatedReplies[_random.nextInt(simulatedReplies.length)];
      final id = 'msg_${DateTime.now().microsecondsSinceEpoch}';
      await db.into(db.messages).insert(Message(
          id: id,
          conversationId: widget.id,
          senderMemberId: sender.id,
          body: body,
          status: !_disposed && mounted ? 'READ' : 'DELIVERED',
          sentAt: DateTime.now()));
      db.logOp('Message', id, 'CREATE',
          {'sender': sender.displayName, 'simulated': true});
      await db.touchConversation(widget.id);
      await db.pushNotification(
          spaceId: conv.spaceId,
          category: 'MESSAGE',
          priority: 'NORMAL',
          title: '${memberFirstName(sender.displayName)} vous a répondu',
          body: excerptOf(body),
          resourceType: 'CONVERSATION',
          resourceId: widget.id);
    });
  }

  // ── Actions ──

  /// Envoi : insertion PENDING puis timers de remise, lecture et réponse.
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final db = ref.read(dbProvider);
    final members = await db.getConvMembers(widget.id);
    final you =
        members.where((m) => m.displayName == youMemberName).firstOrNull;
    if (you == null) return;
    final id = 'msg_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.messages).insert(Message(
        id: id,
        conversationId: widget.id,
        senderMemberId: you.id,
        body: text,
        status: 'PENDING',
        sentAt: DateTime.now()));
    db.logOp('Message', id, 'CREATE', {'conversationId': widget.id});
    await db.touchConversation(widget.id);
    _input.clear();
    _simulateDelivery(id);
    _simulateMyRead();
    _simulateReply();
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    await ref.read(dbProvider).toggleReaction(
        messageId: messageId, memberName: youMemberName, emoji: emoji);
  }

  /// Long-press sur une bulle : réagir, modifier (< 15 min, mon message),
  /// supprimer pour tous.
  Future<void> _showMessageActions(
      Message msg, ConversationMember? you) async {
    final canEdit = you != null &&
        msg.senderMemberId == you.id &&
        msg.deletedAt == null &&
        DateTime.now().difference(msg.sentAt) < const Duration(minutes: 15);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(LHSpacing.screen,
                  LHSpacing.md, LHSpacing.screen, LHSpacing.sm),
              child: Text(
                'Réagir',
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final emoji in reactionEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(LHRadius.full),
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleReaction(msg.id, emoji);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child:
                          Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              subtitle: canEdit
                  ? null
                  : const Text(
                      'Disponible moins de 15 minutes après l\'envoi'),
              enabled: canEdit,
              onTap: canEdit
                  ? () {
                      Navigator.pop(ctx);
                      _showEditMessageDialog(msg);
                    }
                  : null,
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: LHColors.erreur),
              title: const Text('Supprimer pour tous'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteMessage(msg);
              },
            ),
            const SizedBox(height: LHSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditMessageDialog(Message msg) {
    final ctrl = TextEditingController(text: msg.body);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty || text == msg.body) return;
              ref.read(dbProvider).editMessage(msg.id, text);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _confirmDeleteMessage(Message msg) async {
    final ok = await lhConfirm(
      context,
      title: 'Supprimer pour tous ?',
      message:
          'Le message sera remplacé par « Message supprimé » pour tous les '
          'participants. La suppression reste traçable.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(dbProvider).deleteMessageForAll(msg.id);
  }

  Future<void> _showMembersSheet(List<ConversationMember> members) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(LHSpacing.screen,
                  LHSpacing.md, LHSpacing.screen, LHSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Membres',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
            ),
            for (final m in members)
              ListTile(
                dense: true,
                leading: InitialsAvatar(
                    name: m.displayName,
                    color: hexToColor(m.colorHex),
                    size: 36),
                title: Text(m.displayName),
                trailing: Text(
                  m.role == 'OWNER' ? 'Propriétaire' : 'Membre',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: LHSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final convAsync = ref.watch(conversationProvider(widget.id));
    final members =
        ref.watch(convMembersProvider(widget.id)).valueOrNull ??
            <ConversationMember>[];
    final messages =
        ref.watch(convMessagesProvider(widget.id)).valueOrNull ??
            <Message>[];
    final reactions =
        ref.watch(convReactionsProvider(widget.id)).valueOrNull ??
            <MessageReaction>[];

    final conv = convAsync.valueOrNull;
    final you =
        members.where((m) => m.displayName == youMemberName).firstOrNull;
    final others =
        members.where((m) => m.displayName != youMemberName).toList();
    final memberById = {for (final m in members) m.id: m};
    final firstNames = <String>{
      for (final m in members) memberFirstName(m.displayName)
    };
    final isGroup = conv?.kind == 'GROUP';
    final title = conv?.title ??
        (others.firstOrNull != null
            ? memberFirstName(others.first.displayName)
            : 'Conversation');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (isGroup)
              Text(
                '${members.length} participants',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          if (conv != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'receipts') {
                  await ref.read(dbProvider).setReadReceiptsEnabled(
                      widget.id, !conv.readReceiptsEnabled);
                } else if (v == 'members') {
                  await _showMembersSheet(members);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'receipts',
                  child: Row(
                    children: [
                      const Icon(Icons.done_all, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Accusés de lecture')),
                      if (conv.readReceiptsEnabled)
                        const Icon(Icons.check,
                            size: 18, color: LHColors.emeraudeClair),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'members',
                  child: Row(
                    children: [
                      Icon(Icons.group_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Afficher les membres'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: conv == null
          ? (convAsync.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const EmptyState(
                  icon: Icons.forum_outlined,
                  message: 'Conversation introuvable'))
          : Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? EmptyState(
                          icon: Icons.chat_bubble_outline,
                          message: 'Aucun message',
                          hint:
                              'Envoyez le premier message pour démarrer la '
                              'conversation.',
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: LHSpacing.md,
                              vertical: LHSpacing.sm),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            // Indice 0 = message le plus récent (inverse).
                            final msg =
                                messages[messages.length - 1 - i];
                            final prev = i + 1 < messages.length
                                ? messages[messages.length - 2 - i]
                                : null;
                            final isMine = you != null &&
                                msg.senderMemberId == you.id;
                            final firstOfGroup = prev == null ||
                                prev.senderMemberId != msg.senderMemberId;
                            return _MessageView(
                              message: msg,
                              sender: memberById[msg.senderMemberId],
                              isMine: isMine,
                              showSenderHeader:
                                  !isMine && firstOfGroup,
                              firstNames: firstNames,
                              reactions: reactions
                                  .where((r) => r.messageId == msg.id)
                                  .toList(),
                              onLongPress: () =>
                                  _showMessageActions(msg, you),
                              onToggleReaction: (emoji) =>
                                  _toggleReaction(msg.id, emoji),
                            );
                          },
                        ),
                ),
                _inputBar(theme),
              ],
            ),
    );
  }

  Widget _inputBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LHSpacing.md, LHSpacing.sm,
            LHSpacing.xs, LHSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: LHSpacing.lg, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(LHRadius.full),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Envoyer',
              icon: const Icon(Icons.send_rounded),
              color: theme.brightness == Brightness.dark
                  ? LHColors.or
                  : LHColors.orDeep,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle de message : côté (or translucide à droite / surface à gauche),
/// mentions en gras couleur or, réactions, statut de remise (D12 §17.2).
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.sender,
    required this.isMine,
    required this.showSenderHeader,
    required this.firstNames,
    required this.reactions,
    required this.onLongPress,
    required this.onToggleReaction,
  });

  final Message message;
  final ConversationMember? sender;
  final bool isMine;
  final bool showSenderHeader;
  final Set<String> firstNames;
  final List<MessageReaction> reactions;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ConversationMember? member = sender;
    final deleted = message.deletedAt != null;
    final senderColor =
        member == null ? LHColors.neutre : hexToColor(member.colorHex);
    final senderName = member?.displayName ?? 'Membre';

    final grouped = <String, int>{};
    for (final r in reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: deleted
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.10)
              : (isMine
                  ? LHColors.or.withValues(alpha: 0.15)
                  : theme.colorScheme.surface),
          border: Border.all(
            color: deleted
                ? theme.colorScheme.outline.withValues(alpha: 0.5)
                : (isMine
                    ? LHColors.or.withValues(alpha: 0.35)
                    : theme.colorScheme.outline.withValues(alpha: 0.7)),
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(LHRadius.lg),
            topRight: const Radius.circular(LHRadius.lg),
            bottomLeft: Radius.circular(isMine ? LHRadius.lg : 4),
            bottomRight: Radius.circular(isMine ? 4 : LHRadius.lg),
          ),
        ),
        child: deleted
            ? Text(
                'Message supprimé',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant),
              )
            : Text.rich(_body(context)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: LHSpacing.sm),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSenderHeader)
            Padding(
              padding:
                  const EdgeInsets.only(left: LHSpacing.xs, bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InitialsAvatar(
                      name: senderName, color: senderColor, size: 18),
                  const SizedBox(width: 5),
                  Text(
                    memberFirstName(senderName),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: senderColor),
                  ),
                ],
              ),
            ),
          bubble,
          if (isMine && !deleted) _statusLine(theme),
          if (grouped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  top: 3, left: LHSpacing.xs, right: LHSpacing.xs),
              child: Wrap(
                spacing: 4,
                children: [
                  for (final e in grouped.entries)
                    GestureDetector(
                      onTap: () => onToggleReaction(e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(LHRadius.full),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e.key,
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 3),
                            Text(
                              '${e.value}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Statut de mon message — fidèle aux états réellement connus.
  Widget _statusLine(ThemeData theme) {
    final (color, label) = switch (message.status) {
      'PENDING' => (LHColors.neutre, '⏳ Envoi…'),
      'SENT' => (theme.colorScheme.onSurfaceVariant, '✓ Envoyé'),
      'DELIVERED' => (theme.colorScheme.onSurfaceVariant, '✓✓ Remis'),
      'READ' => (LHColors.emeraudeClair, '✓✓ Lu'),
      'FAILED' => (LHColors.erreur, '! Échec'),
      _ => (theme.colorScheme.onSurfaceVariant, message.status),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2, right: LHSpacing.xs),
      child: Text(
        label,
        style:
            theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  /// Corps enrichi : mentions @Prénom en gras couleur or + suffixe
  /// « (modifié) » si le message a été édité.
  TextSpan _body(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final mention = base.copyWith(
        color: theme.brightness == Brightness.dark
            ? LHColors.or
            : LHColors.orDeep,
        fontWeight: FontWeight.w700);

    final spans = <TextSpan>[];
    final regex = RegExp(r'@[\p{L}]+', unicode: true);
    var start = 0;
    for (final match in regex.allMatches(message.body)) {
      if (match.start > start) {
        spans.add(TextSpan(
            text: message.body.substring(start, match.start),
            style: base));
      }
      final token = match.group(0)!;
      final isMention = firstNames
          .any((n) => n.toLowerCase() == token.substring(1).toLowerCase());
      spans.add(
          TextSpan(text: token, style: isMention ? mention : base));
      start = match.end;
    }
    if (start < message.body.length) {
      spans.add(
          TextSpan(text: message.body.substring(start), style: base));
    }
    if (message.editedAt != null) {
      spans.add(TextSpan(
        text: ' (modifié)',
        style: base.copyWith(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant),
      ));
    }
    return TextSpan(children: spans);
  }
}

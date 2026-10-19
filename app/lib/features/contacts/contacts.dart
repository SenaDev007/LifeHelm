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

// ═══════════════════════════ LABELS MÉTIER (D11) ═══════════════════════════

/// Types de coordonnées (ContactPoint) — D11 §16.3.
const contactPointTypes = ['PHONE', 'EMAIL', 'ADDRESS', 'URL'];

String pointTypeLabel(String type) => switch (type) {
      'PHONE' => 'Téléphone',
      'EMAIL' => 'Courriel',
      'ADDRESS' => 'Adresse',
      'URL' => 'Lien',
      _ => type,
    };

IconData pointTypeIcon(String type) => switch (type) {
      'PHONE' => Icons.call_outlined,
      'EMAIL' => Icons.mail_outline,
      'ADDRESS' => Icons.place_outlined,
      'URL' => Icons.link,
      _ => Icons.circle_outlined,
    };

Color pointTypeColor(String type) => switch (type) {
      'PHONE' => LHColors.info,
      'EMAIL' => LHColors.or,
      'ADDRESS' => LHColors.emeraudeClair,
      'URL' => LHColors.alerte,
      _ => LHColors.neutre,
    };

/// Types d'interaction — historique saisi manuellement (D11 §16.1-4) :
/// aucun appel ni message n'est jamais enregistré automatiquement.
const interactionKinds = ['CALL', 'MEETING', 'MESSAGE', 'EMAIL', 'OTHER'];

String interactionKindLabel(String kind) => switch (kind) {
      'CALL' => 'Appel',
      'MEETING' => 'Rencontre',
      'MESSAGE' => 'Message',
      'EMAIL' => 'Courriel',
      _ => 'Autre',
    };

IconData interactionKindIcon(String kind) => switch (kind) {
      'CALL' => Icons.call,
      'MEETING' => Icons.groups_outlined,
      'MESSAGE' => Icons.chat_bubble_outline,
      'EMAIL' => Icons.mail_outline,
      _ => Icons.more_horiz,
    };

Color interactionKindColor(String kind) => switch (kind) {
      'CALL' => LHColors.info,
      'MEETING' => LHColors.or,
      'MESSAGE' => LHColors.emeraudeClair,
      'EMAIL' => LHColors.alerte,
      _ => LHColors.neutre,
    };

/// Nom d'affichage : prénom + nom (personne) ou raison sociale (organisation).
String contactDisplayName(Contact c) {
  if (c.kind == 'ORGANIZATION') {
    final name = c.organizationName?.trim() ?? '';
    return name.isEmpty ? 'Organisation' : name;
  }
  final name = [c.firstName, c.lastName]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');
  return name.isEmpty ? 'Contact' : name;
}

/// Sous-titre : fonction et/ou organisation (personne), secteur (organisation).
String contactSubtitle(Contact c) {
  final job = c.jobTitle?.trim() ?? '';
  if (c.kind == 'ORGANIZATION') return job;
  final org = c.organizationName?.trim() ?? '';
  if (job.isNotEmpty && org.isNotEmpty) return '$job · $org';
  return job.isNotEmpty ? job : org;
}

String? _trimOrNull(String value) {
  final v = value.trim();
  return v.isEmpty ? null : v;
}

int _compareContactNames(Contact a, Contact b) => contactDisplayName(a)
    .toLowerCase()
    .compareTo(contactDisplayName(b).toLowerCase());

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension ContactQueries on AppDatabase {
  /// Carnet isolé par espace (D11 §16.1-2) — trié par nom d'affichage.
  Stream<List<Contact>> watchContacts(String spaceId) =>
      (select(contacts)..where((c) => c.spaceId.equals(spaceId)))
          .watch()
          .map((rows) => rows..sort(_compareContactNames));

  Stream<Contact?> watchContact(String id) =>
      (select(contacts)..where((c) => c.id.equals(id))).watchSingleOrNull();

  Stream<List<ContactPoint>> watchContactPoints(String contactId) =>
      (select(contactPoints)
            ..where((p) => p.contactId.equals(contactId))
            ..orderBy([
              (p) => OrderingTerm(expression: p.type),
              (p) => OrderingTerm(expression: p.value),
            ]))
          .watch();

  Stream<List<ContactInteraction>> watchContactInteractions(
          String contactId) =>
      (select(contactInteractions)
            ..where((i) => i.contactId.equals(contactId))
            ..orderBy([
              (i) =>
                  OrderingTerm(expression: i.dateKey, mode: OrderingMode.desc),
            ]))
          .watch();

  Stream<List<ContactLink>> watchContactLinks(String contactId) =>
      (select(contactLinks)..where((l) => l.contactId.equals(contactId)))
          .watch();

  Future<String> createContact({
    required String spaceId,
    required String kind,
    String? firstName,
    String? lastName,
    String? organizationName,
    String? jobTitle,
  }) async {
    final id = 'ct_${DateTime.now().microsecondsSinceEpoch}';
    await into(contacts).insert(Contact(
        id: id,
        spaceId: spaceId,
        kind: kind,
        firstName: firstName,
        lastName: lastName,
        organizationName: organizationName,
        jobTitle: jobTitle,
        notes: null,
        isFavorite: false,
        createdAt: DateTime.now()));
    logOp('Contact', id, 'CREATE', {'kind': kind});
    return id;
  }

  Future<void> updateContactIdentity(String id,
      {required String? firstName,
      required String? lastName,
      required String? organizationName,
      required String? jobTitle}) async {
    await (update(contacts)..where((c) => c.id.equals(id))).write(
        ContactsCompanion(
            firstName: Value(firstName),
            lastName: Value(lastName),
            organizationName: Value(organizationName),
            jobTitle: Value(jobTitle)));
    logOp('Contact', id, 'UPDATE', {'identity': true});
  }

  Future<void> setContactFavorite(String id, bool favorite) async {
    await (update(contacts)..where((c) => c.id.equals(id)))
        .write(ContactsCompanion(isFavorite: Value(favorite)));
    logOp('Contact', id, 'UPDATE', {'isFavorite': favorite});
  }

  Future<void> setContactNotes(String id, String? notes) async {
    await (update(contacts)..where((c) => c.id.equals(id)))
        .write(ContactsCompanion(notes: Value(notes)));
    logOp('Contact', id, 'UPDATE', {'notes': notes != null});
  }

  /// Supprime le contact et toutes ses données liées
  /// (coordonnées, interactions, liens) — journalisé pour la synchro.
  Future<void> deleteContact(Contact c) async {
    final points = await (select(contactPoints)
          ..where((p) => p.contactId.equals(c.id)))
        .get();
    final interactions = await (select(contactInteractions)
          ..where((i) => i.contactId.equals(c.id)))
        .get();
    final links = await (select(contactLinks)
          ..where((l) => l.contactId.equals(c.id)))
        .get();
    await (delete(contactPoints)..where((p) => p.contactId.equals(c.id))).go();
    await (delete(contactInteractions)
          ..where((i) => i.contactId.equals(c.id)))
        .go();
    await (delete(contactLinks)..where((l) => l.contactId.equals(c.id))).go();
    await (delete(contacts)..where((x) => x.id.equals(c.id))).go();
    for (final p in points) {
      logOp('ContactPoint', p.id, 'DELETE', {});
    }
    for (final i in interactions) {
      logOp('ContactInteraction', i.id, 'DELETE', {});
    }
    for (final l in links) {
      logOp('ContactLink', l.id, 'DELETE', {});
    }
    logOp('Contact', c.id, 'DELETE', {'name': contactDisplayName(c)});
  }

  Future<void> addContactPoint({
    required String contactId,
    required String type,
    required String value,
    String? label,
  }) async {
    final id = 'cpt_${DateTime.now().microsecondsSinceEpoch}';
    await into(contactPoints).insert(ContactPoint(
        id: id, contactId: contactId, type: type, value: value, label: label));
    logOp('ContactPoint', id, 'CREATE', {'type': type, 'contactId': contactId});
  }

  Future<void> deleteContactPoint(String id) async {
    await (delete(contactPoints)..where((p) => p.id.equals(id))).go();
    logOp('ContactPoint', id, 'DELETE', {});
  }

  Future<void> addContactInteraction({
    required String contactId,
    required String dateKey,
    required String kind,
    required String summary,
  }) async {
    final id = 'cit_${DateTime.now().microsecondsSinceEpoch}';
    await into(contactInteractions).insert(ContactInteraction(
        id: id,
        contactId: contactId,
        dateKey: dateKey,
        kind: kind,
        summary: summary));
    logOp('ContactInteraction', id, 'CREATE',
        {'kind': kind, 'dateKey': dateKey});
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final contactsProvider = StreamProvider.family<List<Contact>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchContacts(spaceId));

final contactProvider = StreamProvider.family<Contact?, String>(
    (ref, id) => ref.watch(dbProvider).watchContact(id));

final contactPointsProvider =
    StreamProvider.family<List<ContactPoint>, String>(
        (ref, id) => ref.watch(dbProvider).watchContactPoints(id));

final contactInteractionsProvider =
    StreamProvider.family<List<ContactInteraction>, String>(
        (ref, id) => ref.watch(dbProvider).watchContactInteractions(id));

final contactLinksProvider = StreamProvider.family<List<ContactLink>, String>(
    (ref, id) => ref.watch(dbProvider).watchContactLinks(id));

// ═══════════════════════════ ÉCRAN : LISTE ═══════════════════════════

enum _ContactFilter { all, favorites, persons, organizations }

/// Carnet de contacts de l'espace actif — isolé par espace (D11 §16.1-2).
/// Aucun accès permanent au carnet natif : saisie et import manuels (CDC).
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  _ContactFilter _filter = _ContactFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final space = ref.watch(activeSpaceProvider).valueOrNull;
    final contactsAsync = ref.watch(contactsProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Contacts'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewContactSheet(spaceId),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nouveau contact'),
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (contacts) {
          var visible = contacts.where((c) {
            switch (_filter) {
              case _ContactFilter.all:
                return true;
              case _ContactFilter.favorites:
                return c.isFavorite;
              case _ContactFilter.persons:
                return c.kind == 'PERSON';
              case _ContactFilter.organizations:
                return c.kind == 'ORGANIZATION';
            }
          }).toList();

          final q = _query.toLowerCase();
          if (q.isNotEmpty) {
            visible = visible
                .where((c) => [
                      c.firstName ?? '',
                      c.lastName ?? '',
                      c.organizationName ?? '',
                    ].join(' ').toLowerCase().contains(q))
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mini-ligne d'en-tête : rappel de l'isolation par espace.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, 0),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 13, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      'Carnet : ${space?.name ?? '…'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(LHSpacing.lg, LHSpacing.sm,
                    LHSpacing.lg, LHSpacing.sm),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un nom ou une organisation',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LHSpacing.lg),
                child: LhSegmented<_ContactFilter>(
                  value: _filter,
                  items: const {
                    _ContactFilter.all: 'Tous',
                    _ContactFilter.favorites: 'Favoris',
                    _ContactFilter.persons: 'Personnes',
                    _ContactFilter.organizations: 'Organisations',
                  },
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(height: LHSpacing.sm),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.contacts_outlined,
                        message: 'Aucun contact ici',
                        hint:
                            'Le carnet est isolé par espace. Les contacts se saisissent '
                            'manuellement — aucun accès au carnet du téléphone.',
                        action: FilledButton.tonal(
                          onPressed: () => _showNewContactSheet(spaceId),
                          child: const Text('Nouveau contact'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 96),
                        itemCount: visible.length,
                        itemBuilder: (context, i) =>
                            _ContactTile(contact: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // —— Création (bottom sheet) ——

  Future<void> _showNewContactSheet(String spaceId) {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final orgCtrl = TextEditingController();
    final jobCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    var kind = 'PERSON';

    Future<void> create(BuildContext sheetCtx) async {
      final db = ref.read(dbProvider);
      final navigator = Navigator.of(sheetCtx);
      String id;
      if (kind == 'PERSON') {
        final first = _trimOrNull(firstCtrl.text);
        final last = _trimOrNull(lastCtrl.text);
        if (first == null && last == null) {
          lhToast(sheetCtx, 'Indiquez au moins un prénom ou un nom.');
          return;
        }
        id = await db.createContact(
            spaceId: spaceId,
            kind: 'PERSON',
            firstName: first,
            lastName: last,
            jobTitle: _trimOrNull(jobCtrl.text));
      } else {
        final org = _trimOrNull(orgCtrl.text);
        if (org == null) {
          lhToast(sheetCtx, 'Indiquez le nom de l\'organisation.');
          return;
        }
        id = await db.createContact(
            spaceId: spaceId,
            kind: 'ORGANIZATION',
            organizationName: org,
            jobTitle: _trimOrNull(jobCtrl.text));
      }
      // Coordonnées initiales optionnelles.
      final phone = _trimOrNull(phoneCtrl.text);
      final email = _trimOrNull(emailCtrl.text);
      if (phone != null) {
        await db.addContactPoint(
            contactId: id, type: 'PHONE', value: phone);
      }
      if (email != null) {
        await db.addContactPoint(
            contactId: id, type: 'EMAIL', value: email);
      }
      navigator.pop();
      if (mounted) context.push('/contact/$id');
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
                    'Nouveau contact',
                    style: Theme.of(sheetCtx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: LHSpacing.lg),
                  LhSegmented<String>(
                    value: kind,
                    items: const {
                      'PERSON': 'Personne',
                      'ORGANIZATION': 'Organisation',
                    },
                    onChanged: (v) => setSheet(() => kind = v),
                  ),
                  const SizedBox(height: LHSpacing.lg),
                  if (kind == 'PERSON') ...[
                    TextField(
                      controller: firstCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Prénom *'),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    TextField(
                      controller: lastCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    TextField(
                      controller: jobCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Fonction'),
                    ),
                  ] else ...[
                    TextField(
                      controller: orgCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nom de l\'organisation *'),
                    ),
                    const SizedBox(height: LHSpacing.md),
                    TextField(
                      controller: jobCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Secteur'),
                    ),
                  ],
                  const SizedBox(height: LHSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Coordonnées (optionnel)',
                      style: Theme.of(sheetCtx).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(sheetCtx).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: LHSpacing.sm),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'Téléphone'),
                  ),
                  const SizedBox(height: LHSpacing.md),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Courriel'),
                  ),
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
      firstCtrl.dispose();
      lastCtrl.dispose();
      orgCtrl.dispose();
      jobCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
    });
  }
}

/// Ligne de contact : avatar (initiales ou bâtiment), nom, fonction, favori.
class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = contactSubtitle(contact);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.lg, vertical: 4),
      child: LHCard(
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: 10),
        onTap: () => context.push('/contact/${contact.id}'),
        child: Row(
          children: [
            if (contact.kind == 'ORGANIZATION')
              const _OrgAvatar()
            else
              InitialsAvatar(name: contactDisplayName(contact)),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contactDisplayName(contact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: contact.isFavorite
                  ? 'Retirer des favoris'
                  : 'Ajouter aux favoris',
              icon: Icon(
                contact.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: contact.isFavorite
                    ? LHColors.or
                    : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => ref
                  .read(dbProvider)
                  .setContactFavorite(contact.id, !contact.isFavorite),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastille organisation : icône bâtiment (pas d'initiales).
class _OrgAvatar extends StatelessWidget {
  const _OrgAvatar({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: LHColors.info.withValues(alpha: 0.14),
        border: Border.all(color: LHColors.info.withValues(alpha: 0.55)),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.apartment, size: size * 0.46, color: LHColors.info),
    );
  }
}

// ═══════════════════════════ ÉCRAN : DÉTAIL ═══════════════════════════

/// Fiche contact : coordonnées, interactions saisies manuellement,
/// notes et liens vers les tâches et événements (D11).
class ContactDetailScreen extends ConsumerStatefulWidget {
  const ContactDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ContactDetailScreen> createState() =>
      _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final contactAsync = ref.watch(contactProvider(widget.id));
    final points = ref.watch(contactPointsProvider(widget.id)).valueOrNull ??
        <ContactPoint>[];
    final interactions =
        ref.watch(contactInteractionsProvider(widget.id)).valueOrNull ??
            <ContactInteraction>[];
    final links = ref.watch(contactLinksProvider(widget.id)).valueOrNull ??
        <ContactLink>[];
    final contact = contactAsync.valueOrNull;

    if (contactAsync.isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact')),
        body: const EmptyState(
            icon: Icons.person_off_outlined, message: 'Contact introuvable'),
      );
    }

    final name = contactDisplayName(contact);
    final subtitle = contactSubtitle(contact);
    final taskLinks =
        links.where((l) => l.resourceType == 'TASK').length;
    final eventLinks =
        links.where((l) => l.resourceType == 'EVENT').length;
    final linkParts = <String>[
      if (taskLinks > 0) '$taskLinks tâche${taskLinks > 1 ? 's' : ''}',
      if (eventLinks > 0) '$eventLinks événement${eventLinks > 1 ? 's' : ''}',
    ];
    final linksText = linkParts.isEmpty
        ? 'Aucune tâche ni événement lié pour l\'instant.'
        : '${linkParts.join(' / ')} lié${(taskLinks + eventLinks) > 1 ? 's' : 'e'}';
    final hasNotes = contact.notes != null && contact.notes!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: contact.isFavorite
                ? 'Retirer des favoris'
                : 'Ajouter aux favoris',
            icon: Icon(
              contact.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: contact.isFavorite ? LHColors.or : null,
            ),
            onPressed: () =>
                db.setContactFavorite(contact.id, !contact.isFavorite),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await _showEditDialog(contact);
                  break;
                case 'delete':
                  final ok = await lhConfirm(
                    context,
                    title: 'Supprimer le contact ?',
                    message:
                        '« $name » sera supprimé avec ses coordonnées, interactions '
                        'et liens. La suppression est journalisée pour la synchronisation.',
                    confirmLabel: 'Supprimer',
                    destructive: true,
                  );
                  if (ok) {
                    await db.deleteContact(contact);
                    if (context.mounted) context.pop();
                  }
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        children: [
          // —— En-tête : avatar + nom + fonction/organisation ——
          LHCard(
            child: Row(
              children: [
                if (contact.kind == 'ORGANIZATION')
                  const _OrgAvatar(size: 56)
                else
                  InitialsAvatar(name: name, size: 56),
                const SizedBox(width: LHSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: LHSpacing.sm),
                      StatusChip(
                        label: contact.kind == 'ORGANIZATION'
                            ? 'Organisation'
                            : 'Personne',
                        color: contact.kind == 'ORGANIZATION'
                            ? LHColors.info
                            : LHColors.or,
                        small: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // —— Coordonnées (ContactPoints) ——
          SectionHeader(
            'Coordonnées',
            action: IconButton(
              tooltip: 'Ajouter une coordonnée',
              icon: const Icon(Icons.add),
              onPressed: () => _showAddPointDialog(contact),
            ),
          ),
          if (points.isEmpty)
            _hint('Aucune coordonnée enregistrée.')
          else
            for (final p in points) _pointCard(p),

          // —— Interactions (saisie manuelle uniquement — D11 §16.1-4) ——
          SectionHeader(
            'Interactions',
            overline: 'Saisie manuelle',
            action: IconButton(
              tooltip: 'Ajouter une interaction',
              icon: const Icon(Icons.add),
              onPressed: () => _showAddInteractionDialog(contact),
            ),
          ),
          if (interactions.isEmpty)
            _hint(
                'Aucune interaction. Les appels et messages ne sont jamais '
                'enregistrés automatiquement.')
          else
            _InteractionTimeline(interactions: interactions),

          // —— Notes ——
          SectionHeader(
            'Notes',
            action: IconButton(
              tooltip: 'Modifier les notes',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showNotesDialog(contact),
            ),
          ),
          LHCard(
            child: Text(
              hasNotes ? contact.notes! : 'Aucune note pour l\'instant.',
              style: hasNotes
                  ? theme.textTheme.bodyMedium
                  : theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
            ),
          ),

          // —— Liens (tâches / événements) ——
          SectionHeader('Liens'),
          LHCard(
            child: Row(
              children: [
                Icon(Icons.link, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: LHSpacing.md),
                Expanded(
                  child: Text(
                    linksText,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LHSpacing.xxl),
        ],
      ),
    );
  }

  Widget _hint(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, LHSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _pointCard(ContactPoint p) {
    final theme = Theme.of(context);
    final color = pointTypeColor(p.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: LHSpacing.sm),
      child: LHCard(
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(pointTypeIcon(p.type), size: 17, color: color),
            ),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    p.label == null || p.label!.isEmpty
                        ? pointTypeLabel(p.type)
                        : '${pointTypeLabel(p.type)} · ${p.label!}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Supprimer cette coordonnée',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
              onPressed: () =>
                  ref.read(dbProvider).deleteContactPoint(p.id),
            ),
          ],
        ),
      ),
    );
  }

  // —— Dialogues ——

  Future<void> _showAddPointDialog(Contact contact) {
    final valueCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    var type = 'PHONE';
    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Ajouter une coordonnée'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LhSegmented<String>(
                  value: type,
                  items: const {
                    'PHONE': 'Téléphone',
                    'EMAIL': 'Courriel',
                    'ADDRESS': 'Adresse',
                    'URL': 'Lien',
                  },
                  onChanged: (v) => setDialog(() => type = v),
                ),
                const SizedBox(height: LHSpacing.lg),
                TextField(
                  controller: valueCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Valeur *',
                    hintText: switch (type) {
                      'PHONE' => '+33 6 12 34 56 78',
                      'EMAIL' => 'prenom@exemple.fr',
                      'ADDRESS' => '12 rue des Lilas, Lomé',
                      _ => 'https://…',
                    },
                  ),
                  keyboardType: type == 'PHONE'
                      ? TextInputType.phone
                      : (type == 'EMAIL'
                          ? TextInputType.emailAddress
                          : TextInputType.url),
                ),
                const SizedBox(height: LHSpacing.md),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Libellé (optionnel)',
                      hintText: 'Bureau, portable…'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                final value = valueCtrl.text.trim();
                if (value.isEmpty) {
                  lhToast(ctx, 'La valeur est obligatoire.');
                  return;
                }
                final label = labelCtrl.text.trim();
                Navigator.pop(ctx);
                await ref.read(dbProvider).addContactPoint(
                      contactId: contact.id,
                      type: type,
                      value: value,
                      label: label.isEmpty ? null : label,
                    );
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      valueCtrl.dispose();
      labelCtrl.dispose();
    });
  }

  Future<void> _showAddInteractionDialog(Contact contact) {
    final summaryCtrl = TextEditingController();
    var dateKey = fmt.dateKey(fmt.today()); // défaut : aujourd'hui
    var kind = 'CALL';
    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Ajouter une interaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: fmt.parseKey(dateKey),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      locale: const Locale('fr'),
                    );
                    if (picked != null) {
                      setDialog(() => dateKey = fmt.dateKey(picked));
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Date',
                        prefixIcon: Icon(Icons.event_outlined)),
                    child: Text(fmt.humanDate(fmt.parseKey(dateKey))),
                  ),
                ),
                const SizedBox(height: LHSpacing.md),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in interactionKinds)
                      ChoiceChip(
                        label: Text(interactionKindLabel(k)),
                        selected: kind == k,
                        onSelected: (_) => setDialog(() => kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: LHSpacing.md),
                TextField(
                  controller: summaryCtrl,
                  autofocus: true,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Résumé *',
                      hintText: 'De quoi avez-vous parlé ?'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                final summary = summaryCtrl.text.trim();
                if (summary.isEmpty) {
                  lhToast(ctx, 'Le résumé est obligatoire.');
                  return;
                }
                Navigator.pop(ctx);
                await ref.read(dbProvider).addContactInteraction(
                      contactId: contact.id,
                      dateKey: dateKey,
                      kind: kind,
                      summary: summary,
                    );
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    ).whenComplete(summaryCtrl.dispose);
  }

  Future<void> _showNotesDialog(Contact contact) {
    final ctrl = TextEditingController(text: contact.notes ?? '');
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'Contexte, préférences, historique…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final text = ctrl.text.trim();
              ref.read(dbProvider).setContactNotes(
                  contact.id, text.isEmpty ? null : text);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _showEditDialog(Contact contact) {
    final firstCtrl = TextEditingController(text: contact.firstName ?? '');
    final lastCtrl = TextEditingController(text: contact.lastName ?? '');
    final orgCtrl =
        TextEditingController(text: contact.organizationName ?? '');
    final jobCtrl = TextEditingController(text: contact.jobTitle ?? '');
    final isOrg = contact.kind == 'ORGANIZATION';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOrg
            ? 'Modifier l\'organisation'
            : 'Modifier le contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isOrg) ...[
                TextField(
                  controller: firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: LHSpacing.md),
                TextField(
                  controller: lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: LHSpacing.md),
              ] else ...[
                TextField(
                  controller: orgCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nom de l\'organisation'),
                ),
                const SizedBox(height: LHSpacing.md),
              ],
              TextField(
                controller: jobCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: isOrg ? 'Secteur' : 'Fonction'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (isOrg && orgCtrl.text.trim().isEmpty) {
                lhToast(ctx,
                    'Le nom de l\'organisation est obligatoire.');
                return;
              }
              if (!isOrg &&
                  firstCtrl.text.trim().isEmpty &&
                  lastCtrl.text.trim().isEmpty) {
                lhToast(ctx, 'Indiquez au moins un prénom ou un nom.');
                return;
              }
              Navigator.pop(ctx);
              await ref.read(dbProvider).updateContactIdentity(
                    contact.id,
                    firstName:
                        isOrg ? null : _trimOrNull(firstCtrl.text),
                    lastName: isOrg ? null : _trimOrNull(lastCtrl.text),
                    organizationName: isOrg
                        ? _trimOrNull(orgCtrl.text)
                        : contact.organizationName,
                    jobTitle: _trimOrNull(jobCtrl.text),
                  );
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ).whenComplete(() {
      firstCtrl.dispose();
      lastCtrl.dispose();
      orgCtrl.dispose();
      jobCtrl.dispose();
    });
  }
}

/// Chronologie des interactions (points + ligne verticale).
class _InteractionTimeline extends StatelessWidget {
  const _InteractionTimeline({required this.interactions});

  final List<ContactInteraction> interactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (i, it) in interactions.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsets.only(top: 5, left: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: interactionKindColor(it.kind),
                        ),
                      ),
                      if (i < interactions.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.only(left: 6.5),
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: LHSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: LHSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(interactionKindIcon(it.kind),
                                size: 14,
                                color: interactionKindColor(it.kind)),
                            const SizedBox(width: 5),
                            Text(
                              fmt.humanDate(fmt.parseKey(it.dateKey)),
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: LHSpacing.sm),
                            Text(
                              interactionKindLabel(it.kind),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: interactionKindColor(it.kind),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(it.summary, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

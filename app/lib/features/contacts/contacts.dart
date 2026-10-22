import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fcontacts;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
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
                padding: const EdgeInsets.fromLTRB(
                    LHSpacing.lg, LHSpacing.sm, LHSpacing.lg, LHSpacing.sm),
                child: Row(children: [
                  Expanded(
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
                  const SizedBox(width: LHSpacing.sm),
                  IconButton.outlined(
                    tooltip: 'Importer depuis le téléphone',
                    icon: const Icon(Icons.phone_android),
                    onPressed: () => _importFromPhone(
                        spaceId, contacts),
                  ),
                ]),
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
                        illustration: 'assets/illustrations/contacts.png',
                        icon: Icons.contacts_outlined,
                        message: 'Aucun contact ici',
                        hint:
                            'Créez un contact ou importez-le depuis le carnet '
                            'de votre téléphone.',
                        action: FilledButton.tonal(
                          onPressed: () => _importFromPhone(spaceId, contacts),
                          child: const Text('Importer depuis le téléphone'),
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

  /// La feuille de création est un widget à part entière : ses contrôleurs
  /// ne sont libérés qu'au démontage complet de la feuille (après
  /// l'animation de sortie). L'ancien motif `whenComplete(dispose)` libérait
  /// les contrôleurs pendant l'animation — les champs encore à l'écran
  /// provoquaient alors « TextEditingController used after disposed »
  /// (page d'erreur framework).
  Future<void> _showNewContactSheet(String spaceId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _NewContactSheet(
        spaceId: spaceId,
        onCreated: (id) => context.push('/contact/$id'),
      ),
    );
  }

  // —— Import depuis le carnet du téléphone ——

  /// Demande la permission (à l'initiative de l'utilisateur), lit le carnet
  /// du téléphone une seule fois, puis ouvre la feuille de sélection.
  Future<void> _importFromPhone(String spaceId, List<Contact> existing) async {
    // 1. Permission : demandée uniquement ici, à l'initiative de
    //    l'utilisateur (aucune lecture en arrière-plan).
    bool granted = false;
    try {
      granted = await fcontacts.FlutterContacts.requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    if (!granted) {
      lhToast(context,
          'Accès refusé. Autorisez « Contacts » pour LifeHelm dans les réglages du téléphone, puis réessayez.');
      return;
    }

    // 2. Lecture du carnet (une seule fois, à la demande).
    List<fcontacts.Contact> raw;
    try {
      raw = await fcontacts.FlutterContacts.getContacts(
          withProperties: true, withThumbnail: false);
    } catch (_) {
      if (mounted) {
        lhToast(context, 'Impossible de lire le carnet du téléphone.');
      }
      return;
    }
    if (!mounted) return;
    if (raw.isEmpty) {
      lhToast(context, 'Aucun contact trouvé dans le téléphone.');
      return;
    }

    // 3. Sélection : feuille plein écran, recherche, doublons repérés.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _PhoneImportSheet(
        spaceId: spaceId,
        raw: raw,
        existing: existing,
      ),
    );
  }
}

/// Feuille « Nouveau contact » : personne ou organisation, fonction avec
/// liste des professions, coordonnées initiales. Les contrôleurs vivent
/// dans l'État et ne sont libérés qu'au démontage complet de la feuille.
class _NewContactSheet extends ConsumerStatefulWidget {
  const _NewContactSheet({required this.spaceId, required this.onCreated});

  final String spaceId;
  final void Function(String contactId) onCreated;

  @override
  ConsumerState<_NewContactSheet> createState() => _NewContactSheetState();
}

class _NewContactSheetState extends ConsumerState<_NewContactSheet> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _jobCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  var _kind = 'PERSON';

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _orgCtrl.dispose();
    _jobCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final db = ref.read(dbProvider);
    final navigator = Navigator.of(context);
    String id;
    if (_kind == 'PERSON') {
      final first = _trimOrNull(_firstCtrl.text);
      final last = _trimOrNull(_lastCtrl.text);
      if (first == null && last == null) {
        lhToast(context, 'Indiquez au moins un prénom ou un nom.');
        return;
      }
      id = await db.createContact(
          spaceId: widget.spaceId,
          kind: 'PERSON',
          firstName: first,
          lastName: last,
          jobTitle: _trimOrNull(_jobCtrl.text));
    } else {
      final org = _trimOrNull(_orgCtrl.text);
      if (org == null) {
        lhToast(context, 'Indiquez le nom de l\'organisation.');
        return;
      }
      id = await db.createContact(
          spaceId: widget.spaceId,
          kind: 'ORGANIZATION',
          organizationName: org,
          jobTitle: _trimOrNull(_jobCtrl.text));
    }
    if (!mounted) return;
    // Coordonnées initiales optionnelles.
    final phone = _trimOrNull(_phoneCtrl.text);
    final email = _trimOrNull(_emailCtrl.text);
    if (phone != null) {
      await db.addContactPoint(contactId: id, type: 'PHONE', value: phone);
    }
    if (!mounted) return;
    if (email != null) {
      await db.addContactPoint(contactId: id, type: 'EMAIL', value: email);
    }
    if (!mounted) return;
    navigator.pop();
    // La feuille se ferme ; le parent (toujours monté) ouvre la fiche.
    widget.onCreated(id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LHSpacing.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nouveau contact',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: LHSpacing.lg),
              LhSegmented<String>(
                value: _kind,
                items: const {
                  'PERSON': 'Personne',
                  'ORGANIZATION': 'Organisation',
                },
                onChanged: (v) => setState(() => _kind = v),
              ),
              const SizedBox(height: LHSpacing.lg),
              if (_kind == 'PERSON') ...[
                TextField(
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Prénom *'),
                ),
                const SizedBox(height: LHSpacing.md),
                TextField(
                  controller: _lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: LHSpacing.md),
                LabeledField(
                  label: 'Fonction — liste au choix ou saisie libre',
                  child: ProfessionPickerField(controller: _jobCtrl),
                ),
              ] else ...[
                TextField(
                  controller: _orgCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nom de l\'organisation *'),
                ),
                const SizedBox(height: LHSpacing.md),
                TextField(
                  controller: _jobCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Secteur'),
                ),
              ],
              const SizedBox(height: LHSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Coordonnées (optionnel)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: LHSpacing.sm),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Courriel'),
              ),
              const SizedBox(height: LHSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: LHSpacing.sm),
                  FilledButton(
                    onPressed: _create,
                    child: const Text('Créer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille d'import : sélection des contacts du téléphone à ajouter au
/// carnet. Les doublons (même nom) sont repérés et signalés ; la lecture du
/// carnet n'a lieu qu'à l'ouverture, jamais en arrière-plan.
class _PhoneImportSheet extends ConsumerStatefulWidget {
  const _PhoneImportSheet({
    required this.spaceId,
    required this.raw,
    required this.existing,
  });

  final String spaceId;
  final List<fcontacts.Contact> raw;
  final List<Contact> existing;

  @override
  ConsumerState<_PhoneImportSheet> createState() => _PhoneImportSheetState();
}

class _PhoneImportSheetState extends ConsumerState<_PhoneImportSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<int> _selected = {};
  var _importing = false;

  String _phoneName(fcontacts.Contact c) => c.displayName.trim();

  String? _phoneJob(fcontacts.Contact c) {
    for (final o in c.organizations) {
      final j = o.title.trim();
      if (j.isNotEmpty) return j;
    }
    return null;
  }

  String? _phoneNumber(fcontacts.Contact c) {
    for (final p in c.phones) {
      final n = p.number.trim();
      if (n.isNotEmpty) return n;
    }
    return null;
  }

  String? _phoneEmail(fcontacts.Contact c) {
    for (final e in c.emails) {
      final a = e.address.trim();
      if (a.isNotEmpty) return a;
    }
    return null;
  }

  bool _alreadyInCarnet(fcontacts.Contact c) {
    final target = _phoneName(c).toLowerCase();
    if (target.isEmpty) return false;
    return widget.existing.any(
        (k) => contactDisplayName(k).toLowerCase() == target);
  }

  @override
  void initState() {
    super.initState();
    // Présélection : tous les contacts absents du carnet.
    for (var i = 0; i < widget.raw.length; i++) {
      if (!_alreadyInCarnet(widget.raw[i]) &&
          _phoneName(widget.raw[i]).isNotEmpty) {
        _selected.add(i);
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_selected.isEmpty || _importing) return;
    setState(() => _importing = true);
    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var created = 0;
    for (final i in _selected) {
      final c = widget.raw[i];
      final display = _phoneName(c);
      // Prénom / nom : ceux du carnet du téléphone, sinon premier /
      // dernier mot du nom complet.
      var first = c.name.first.trim();
      var last = c.name.last.trim();
      if (first.isEmpty && last.isEmpty) {
        final parts = display.split(RegExp(r'\s+'));
        first = parts.isNotEmpty ? parts.first : '';
        last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      final id = await db.createContact(
        spaceId: widget.spaceId,
        kind: 'PERSON',
        firstName: first.isEmpty ? null : first,
        lastName: last.isEmpty ? null : last,
        jobTitle: _phoneJob(c),
      );
      final phone = _phoneNumber(c);
      if (phone != null) {
        await db.addContactPoint(contactId: id, type: 'PHONE', value: phone);
      }
      final email = _phoneEmail(c);
      if (email != null) {
        await db.addContactPoint(contactId: id, type: 'EMAIL', value: email);
      }
      created++;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(
              '$created contact${created > 1 ? 's' : ''} importé${created > 1 ? 's' : ''} dans le carnet.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duplicates = widget.raw.where(_alreadyInCarnet).length;
    final visible = widget.raw.where((c) {
      if (_phoneName(c).isEmpty) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return _phoneName(c).toLowerCase().contains(q) ||
          (_phoneJob(c)?.toLowerCase().contains(q) ?? false);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.md, LHSpacing.screen, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.phone_android, color: LHColors.or, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Importer depuis le téléphone',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Fermer',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          Text(
            '${widget.raw.length} contacts trouvés'
            '${duplicates > 0 ? ' · $duplicates déjà dans le carnet' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: LHSpacing.md),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Rechercher un nom…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          Row(children: [
            TextButton(
              onPressed: _selected.length >= widget.raw.length
                  ? null
                  : () => setState(() {
                        for (var i = 0; i < widget.raw.length; i++) {
                          if (_phoneName(widget.raw[i]).isNotEmpty &&
                              !_alreadyInCarnet(widget.raw[i])) {
                            _selected.add(i);
                          }
                        }
                      }),
              child: const Text('Tout cocher'),
            ),
            TextButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => setState(_selected.clear),
              child: const Text('Tout décocher'),
            ),
          ]),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final c = visible[i];
                final idx = widget.raw.indexOf(c);
                final dup = _alreadyInCarnet(c);
                final inSel = _selected.contains(idx);
                final job = _phoneJob(c);
                final phone = _phoneNumber(c);
                return CheckboxListTile(
                  value: inSel,
                  onChanged: dup
                      ? null
                      : (v) => setState(() => v == true
                          ? _selected.add(idx)
                          : _selected.remove(idx)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(_phoneName(c),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    dup
                        ? 'Déjà dans le carnet'
                        : [
                            if (job != null) job,
                            if (phone != null) phone,
                          ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: dup ? theme.colorScheme.onSurfaceVariant : null),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: LHSpacing.sm),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_importing
                    ? 'Import en cours…'
                    : 'Importer (${_selected.length})'),
              ),
            ),
          ),
        ]),
      ),
    );
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

  /// Le dialogue est un widget à part entière : ses contrôleurs ne sont
  /// libérés qu'au démontage complet (l'ancien `whenComplete(dispose)`
  /// provoquait « TextEditingController used after disposed » pendant
  /// l'animation de sortie).
  Future<void> _showAddPointDialog(Contact contact) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _AddPointDialog(contact: contact),
    );
  }

  Future<void> _showAddInteractionDialog(Contact contact) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _AddInteractionDialog(contact: contact),
    );
  }

  Future<void> _showNotesDialog(Contact contact) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _NotesDialog(contact: contact),
    );
  }

  Future<void> _showEditDialog(Contact contact) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _EditContactDialog(contact: contact),
    );
  }
}

/// Dialogue « Ajouter une coordonnée » — contrôleurs possédés par l'État.
class _AddPointDialog extends ConsumerStatefulWidget {
  const _AddPointDialog({required this.contact});

  final Contact contact;

  @override
  ConsumerState<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends ConsumerState<_AddPointDialog> {
  final _valueCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  var _type = 'PHONE';

  @override
  void dispose() {
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _valueCtrl.text.trim();
    if (value.isEmpty) {
      lhToast(context, 'La valeur est obligatoire.');
      return;
    }
    final label = _labelCtrl.text.trim();
    final db = ref.read(dbProvider);
    final contactId = widget.contact.id;
    final type = _type;
    Navigator.of(context).pop();
    await db.addContactPoint(
      contactId: contactId,
      type: type,
      value: value,
      label: label.isEmpty ? null : label,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une coordonnée'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LhSegmented<String>(
              value: _type,
              items: const {
                'PHONE': 'Téléphone',
                'EMAIL': 'Courriel',
                'ADDRESS': 'Adresse',
                'URL': 'Lien',
              },
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: LHSpacing.lg),
            TextField(
              controller: _valueCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Valeur *',
                hintText: switch (_type) {
                  'PHONE' => '+33 6 12 34 56 78',
                  'EMAIL' => 'prenom@exemple.fr',
                  'ADDRESS' => '12 rue des Lilas, Lomé',
                  _ => 'https://…',
                },
              ),
              keyboardType: _type == 'PHONE'
                  ? TextInputType.phone
                  : (_type == 'EMAIL'
                      ? TextInputType.emailAddress
                      : TextInputType.url),
            ),
            const SizedBox(height: LHSpacing.md),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                  labelText: 'Libellé (optionnel)', hintText: 'Bureau, portable…'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Dialogue « Ajouter une interaction » — contrôleurs possédés par l'État.
class _AddInteractionDialog extends ConsumerStatefulWidget {
  const _AddInteractionDialog({required this.contact});

  final Contact contact;

  @override
  ConsumerState<_AddInteractionDialog> createState() =>
      _AddInteractionDialogState();
}

class _AddInteractionDialogState extends ConsumerState<_AddInteractionDialog> {
  final _summaryCtrl = TextEditingController();
  var _dateKey = '';
  var _kind = 'CALL';

  @override
  void initState() {
    super.initState();
    _dateKey = fmt.dateKey(fmt.today()); // défaut : aujourd'hui
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) {
      lhToast(context, 'Le résumé est obligatoire.');
      return;
    }
    final db = ref.read(dbProvider);
    final contactId = widget.contact.id;
    final dateKey = _dateKey;
    final kind = _kind;
    Navigator.of(context).pop();
    await db.addContactInteraction(
      contactId: contactId,
      dateKey: dateKey,
      kind: kind,
      summary: summary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une interaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: fmt.parseKey(_dateKey),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  locale: const Locale('fr'),
                );
                if (picked != null && mounted) {
                  setState(() => _dateKey = fmt.dateKey(picked));
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Date', prefixIcon: Icon(Icons.event_outlined)),
                child: Text(fmt.humanDate(fmt.parseKey(_dateKey))),
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
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: LHSpacing.md),
            TextField(
              controller: _summaryCtrl,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Résumé *', hintText: 'De quoi avez-vous parlé ?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Dialogue « Notes » — contrôleur possédé par l'État.
class _NotesDialog extends ConsumerStatefulWidget {
  const _NotesDialog({required this.contact});

  final Contact contact;

  @override
  ConsumerState<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends ConsumerState<_NotesDialog> {
  late final _ctrl = TextEditingController(text: widget.contact.notes ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    final db = ref.read(dbProvider);
    final contactId = widget.contact.id;
    Navigator.of(context).pop();
    db.setContactNotes(contactId, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: TextField(
        controller: _ctrl,
        maxLines: 6,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
            hintText: 'Contexte, préférences, historique…'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Dialogue « Modifier le contact » — contrôleurs possédés par l'État ;
/// la fonction propose la liste complète des professions (personnes).
class _EditContactDialog extends ConsumerStatefulWidget {
  const _EditContactDialog({required this.contact});

  final Contact contact;

  @override
  ConsumerState<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends ConsumerState<_EditContactDialog> {
  late final _firstCtrl =
      TextEditingController(text: widget.contact.firstName ?? '');
  late final _lastCtrl =
      TextEditingController(text: widget.contact.lastName ?? '');
  late final _orgCtrl =
      TextEditingController(text: widget.contact.organizationName ?? '');
  late final _jobCtrl = TextEditingController(text: widget.contact.jobTitle ?? '');
  late final bool _isOrg = widget.contact.kind == 'ORGANIZATION';

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _orgCtrl.dispose();
    _jobCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isOrg && _orgCtrl.text.trim().isEmpty) {
      lhToast(context, 'Le nom de l\'organisation est obligatoire.');
      return;
    }
    if (!_isOrg &&
        _firstCtrl.text.trim().isEmpty &&
        _lastCtrl.text.trim().isEmpty) {
      lhToast(context, 'Indiquez au moins un prénom ou un nom.');
      return;
    }
    final firstName = _isOrg ? null : _trimOrNull(_firstCtrl.text);
    final lastName = _isOrg ? null : _trimOrNull(_lastCtrl.text);
    final organizationName = _isOrg
        ? _trimOrNull(_orgCtrl.text)
        : widget.contact.organizationName;
    final jobTitle = _trimOrNull(_jobCtrl.text);
    final db = ref.read(dbProvider);
    final contactId = widget.contact.id;
    Navigator.of(context).pop();
    await db.updateContactIdentity(
      contactId,
      firstName: firstName,
      lastName: lastName,
      organizationName: organizationName,
      jobTitle: jobTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isOrg ? 'Modifier l\'organisation' : 'Modifier le contact'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isOrg) ...[
              TextField(
                controller: _firstCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Prénom'),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _lastCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: LHSpacing.md),
            ] else ...[
              TextField(
                controller: _orgCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Nom de l\'organisation'),
              ),
              const SizedBox(height: LHSpacing.md),
            ],
            _isOrg
                ? TextField(
                    controller: _jobCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Secteur'),
                  )
                : LabeledField(
                    label: 'Fonction — liste au choix ou saisie libre',
                    child: ProfessionPickerField(controller: _jobCtrl),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
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

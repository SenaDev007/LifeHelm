import 'dart:async';
import 'dart:convert';

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

// ═══════════════════════════ LABELS MÉTIER (D06) ═══════════════════════════

/// Types de blocs de l'éditeur riche (CDC D06 §11.1-1, §11.3).
const noteBlockTypes = ['h1', 'h2', 'h3', 'p', 'bullet', 'check', 'quote'];

String blockTypeLabel(String t) => switch (t) {
      'h1' => 'Titre 1',
      'h2' => 'Titre 2',
      'h3' => 'Titre 3',
      'p' => 'Paragraphe',
      'bullet' => 'Puce',
      'check' => 'Case à cocher',
      'quote' => 'Citation',
      _ => t,
    };

String blockTypeHint(String t) => switch (t) {
      'h1' => 'Titre principal',
      'h2' => 'Sous-titre',
      'h3' => 'Section',
      'p' => 'Texte',
      'bullet' => 'Élément de liste',
      'check' => 'Élément à cocher',
      'quote' => 'Citation',
      _ => 'Texte',
    };

IconData blockTypeIcon(String t) => switch (t) {
      'h1' => Icons.title,
      'h2' => Icons.text_fields,
      'h3' => Icons.subject,
      'bullet' => Icons.format_list_bulleted,
      'check' => Icons.check_box_outline_blank,
      'quote' => Icons.format_quote,
      _ => Icons.notes,
    };

/// Date relative lisible : « à l'instant », « il y a 3 h », « hier »…
String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'hier';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
  return fmt.formatShort(d);
}

// ═══════════════════════════ BLOCS DE L'ÉDITEUR ═══════════════════════════

/// Bloc éditable : type + texte + état coché. L'identifiant stable permet de
/// conserver le focus lors des déplacements (ValueKey).
class NoteBlock {
  NoteBlock(this.id, this.type, {String text = '', this.checked = false})
      : controller = TextEditingController(text: text);

  final String id;
  final TextEditingController controller;
  String type; // h1 | h2 | h3 | p | bullet | check | quote
  bool checked;

  void dispose() => controller.dispose();
}

/// Analyse le JSON canonique `[{"type":..., "text":..., "checked":...}]`.
List<NoteBlock> parseBlocks(String json) {
  try {
    final list = jsonDecode(json) as List;
    return [
      for (var i = 0; i < list.length; i++)
        NoteBlock('blk_$i${DateTime.now().microsecondsSinceEpoch ~/ 1000}',
            (list[i]['type'] as String?) ?? 'p',
            text: (list[i]['text'] as String?) ?? '',
            checked: (list[i]['checked'] as bool?) ?? false),
    ];
  } catch (_) {
    return [];
  }
}

/// Sérialise les blocs au format canonique.
String encodeBlocks(List<NoteBlock> blocks) => jsonEncode([
      for (final b in blocks)
        if (b.type == 'check')
          {'type': b.type, 'text': b.controller.text, 'checked': b.checked}
        else
          {'type': b.type, 'text': b.controller.text},
    ]);

/// Texte indexable = concaténation des textes des blocs (D06 §11.5).
String plainTextOf(List<NoteBlock> blocks) => [
      for (final b in blocks)
        if (b.controller.text.trim().isNotEmpty) b.controller.text.trim(),
    ].join(' ');

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension NoteQueries on AppDatabase {
  Stream<List<Note>> watchNotes(String spaceId) {
    return (select(notes)
          ..where((n) => n.spaceId.equals(spaceId) & n.trashedAt.isNull())
          ..orderBy([
            (n) => OrderingTerm(expression: n.pinned, mode: OrderingMode.desc),
            (n) =>
                OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<Note>> watchTrashedNotes(String spaceId) {
    return (select(notes)
          ..where((n) => n.spaceId.equals(spaceId) & n.trashedAt.isNotNull())
          ..orderBy([
            (n) =>
                OrderingTerm(expression: n.trashedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<Note?> getNote(String id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Stream<List<Folder>> watchFolders(String spaceId) {
    return (select(folders)
          ..where((f) => f.spaceId.equals(spaceId))
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
        .watch();
  }

  Future<List<NoteVersion>> getNoteVersions(String noteId) {
    return (select(noteVersions)
          ..where((v) => v.noteId.equals(noteId))
          ..orderBy([
            (v) =>
                OrderingTerm(expression: v.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Sauvegarde la note et, si demandé, journalise une version LORSQUE le
  /// contenu diffère de la dernière version (D06 §11.1-3).
  Future<void> saveNote(Note n,
      {bool createVersion = false, bool existed = false}) async {
    await into(notes).insert(n, mode: InsertMode.insertOrReplace);
    logOp('Note', n.id, existed ? 'UPDATE' : 'CREATE', {'title': n.title});

    if (createVersion) {
      final last = await (select(noteVersions)
            ..where((v) => v.noteId.equals(n.id))
            ..orderBy([
              (v) => OrderingTerm(
                  expression: v.createdAt, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      final differs = last == null ||
          last.title != n.title ||
          last.blocksJson != n.blocksJson;
      if (differs) {
        final vid = 'ver_${DateTime.now().microsecondsSinceEpoch}';
        await into(noteVersions).insert(NoteVersion(
            id: vid,
            noteId: n.id,
            title: n.title,
            blocksJson: n.blocksJson,
            plainText: n.plainText,
            label: 'Sauvegarde',
            createdAt: DateTime.now()));
        logOp('NoteVersion', vid, 'CREATE', {'noteId': n.id, 'label': 'Sauvegarde'});
      }
    }
  }

  Future<void> togglePin(String id, bool pinned) async {
    await (update(notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
        pinned: Value(pinned), updatedAt: Value(DateTime.now())));
    logOp('Note', id, 'UPDATE', {'pinned': pinned});
  }

  Future<void> moveNote(String id, String? folderId) async {
    await (update(notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(
            folderId: Value(folderId), updatedAt: Value(DateTime.now())));
    logOp('Note', id, 'UPDATE', {'folderId': folderId});
  }

  /// Corbeille : suppression logique, restauration pendant 30 jours (D06 §11.7).
  Future<void> trashNote(String id) async {
    await (update(notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
        trashedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));
    logOp('Note', id, 'UPDATE', {'trashed': true});
  }

  /// Restaure depuis la corbeille ; si le dossier d'origine a disparu, la
  /// note revient à la racine (aucune référence orpheline).
  Future<void> restoreNote(String id) async {
    final note = await getNote(id);
    if (note == null) return;
    final origin = note.folderId;
    var targetFolder = origin;
    if (origin != null) {
      final folder = await (select(folders)
            ..where((f) => f.id.equals(origin)))
          .getSingleOrNull();
      if (folder == null) targetFolder = null;
    }
    await (update(notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
        trashedAt: const Value(null),
        folderId: Value(targetFolder),
        updatedAt: Value(DateTime.now())));
    logOp('Note', id, 'UPDATE', {'restored': true, 'folderId': targetFolder});
  }

  /// Purge définitive : la note et ses versions disparaissent (D06 §11.7).
  Future<void> purgeNote(String id) async {
    final versions = await (select(noteVersions)
          ..where((v) => v.noteId.equals(id)))
        .get();
    await (delete(noteVersions)..where((v) => v.noteId.equals(id))).go();
    for (final v in versions) {
      logOp('NoteVersion', v.id, 'DELETE', {});
    }
    await (delete(notes)..where((n) => n.id.equals(id))).go();
    logOp('Note', id, 'DELETE', {});
  }

  /// Restaure une version : le contenu est réécrit ET une NOUVELLE version
  /// « Restauration » est créée — les versions intermédiaires sont conservées
  /// (D06 §11.4).
  Future<void> restoreNoteVersion(String noteId, NoteVersion v) async {
    final now = DateTime.now();
    await (update(notes)..where((n) => n.id.equals(noteId))).write(
        NotesCompanion(
            title: Value(v.title),
            blocksJson: Value(v.blocksJson),
            plainText: Value(v.plainText),
            updatedAt: Value(now)));
    final vid = 'ver_${now.microsecondsSinceEpoch}';
    await into(noteVersions).insert(NoteVersion(
        id: vid,
        noteId: noteId,
        title: v.title,
        blocksJson: v.blocksJson,
        plainText: v.plainText,
        label: 'Restauration',
        createdAt: now));
    logOp('Note', noteId, 'UPDATE', {'restoredVersion': v.label ?? v.id});
    logOp('NoteVersion', vid, 'CREATE',
        {'noteId': noteId, 'label': 'Restauration'});
  }

  // —— Dossiers hiérarchiques : cycles impossibles par construction ——
  Future<Folder> createFolder(String spaceId, String name,
      {String? parentId}) async {
    final f = Folder(
      id: 'folder_${DateTime.now().microsecondsSinceEpoch}',
      spaceId: spaceId,
      parentId: parentId,
      name: name,
      createdAt: DateTime.now(),
    );
    await into(folders).insert(f);
    logOp('Folder', f.id, 'CREATE', {'name': name, 'parentId': parentId});
    return f;
  }

  Future<void> renameFolder(String id, String name) async {
    await (update(folders)..where((f) => f.id.equals(id)))
        .write(FoldersCompanion(name: Value(name)));
    logOp('Folder', id, 'UPDATE', {'name': name});
  }

  /// Suppression refusée si le dossier n'est pas vide — aucune suppression
  /// implicite du contenu (D06 §11.4).
  Future<bool> deleteFolder(String id) async {
    final children =
        await (select(folders)..where((f) => f.parentId.equals(id))).get();
    final notesInside =
        await (select(notes)..where((n) => n.folderId.equals(id))).get();
    if (children.isNotEmpty || notesInside.isNotEmpty) return false;
    await (delete(folders)..where((f) => f.id.equals(id))).go();
    logOp('Folder', id, 'DELETE', {});
    return true;
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final foldersProvider =
    StreamProvider.family<List<Folder>, String>((ref, spaceId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.folders)
        ..where((f) => f.spaceId.equals(spaceId))
        ..orderBy([(f) => OrderingTerm(expression: f.name)]))
      .watch();
});

final notesProvider =
    StreamProvider.family<List<Note>, String>((ref, spaceId) =>
        ref.watch(dbProvider).watchNotes(spaceId));

final trashedNotesProvider =
    StreamProvider.family<List<Note>, String>((ref, spaceId) =>
        ref.watch(dbProvider).watchTrashedNotes(spaceId));

// ═══════════════════════════ ÉCRAN : LISTE (D06) ═══════════════════════════

/// Notes de l'espace actif — navigation de dossiers interne (le dossier
/// courant est un état local, pas une sous-route).
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _currentFolderId; // null = racine
  String _search = '';

  /// Chemin complet du dossier courant (ancêtres inclus), borné pour se
  /// protéger d'une éventuelle corruption de hiérarchie.
  List<Folder> _folderPath(String? folderId, List<Folder> all) {
    final path = <Folder>[];
    var cursor = folderId == null
        ? null
        : all.where((f) => f.id == folderId).firstOrNull;
    var guard = 0;
    while (cursor != null && guard++ < 50) {
      path.insert(0, cursor);
      final pid = cursor.parentId;
      cursor = pid == null ? null : all.where((f) => f.id == pid).firstOrNull;
    }
    return path;
  }

  Future<void> _newFolder() async {
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            _currentFolderId == null ? 'Nouveau dossier' : 'Nouveau sous-dossier'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nom du dossier'),
          onSubmitted: (v) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty) return;
    await db.createFolder(spaceId, name, parentId: _currentFolderId);
    if (mounted) lhToast(context, 'Dossier « $name » créé');
  }

  Future<void> _renameFolder(Folder f) async {
    final db = ref.read(dbProvider);
    final ctrl = TextEditingController(text: f.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le dossier'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nouveau nom'),
          onSubmitted: (v) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Renommer')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty || name == f.name) return;
    await db.renameFolder(f.id, name);
    if (mounted) lhToast(context, 'Dossier renommé');
  }

  Future<void> _deleteFolder(Folder f) async {
    final db = ref.read(dbProvider);
    final empty = await db.deleteFolder(f.id);
    if (!mounted) return;
    lhToast(
        context,
        empty
            ? 'Dossier « ${f.name} » supprimé'
            : 'Le dossier doit être vide (aucune note ni sous-dossier).');
  }

  void _openNote(String? id, {String? folderId}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(id: id, folderId: folderId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final folders = ref.watch(foldersProvider(spaceId)).valueOrNull ?? [];
    final notes = ref.watch(notesProvider(spaceId)).valueOrNull ?? [];

    final searching = _search.trim().isNotEmpty;
    final q = _search.trim().toLowerCase();

    // Sous-dossiers du dossier courant (masqués pendant la recherche).
    final subfolders = searching
        ? <Folder>[]
        : (folders
            .where((f) => f.parentId == _currentFolderId)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)));

    // Notes visibles : pendant la recherche on explore tout l'espace
    // (titre + texte indexable) ; sinon le dossier courant.
    final visible = searching
        ? notes
            .where((n) =>
                n.title.toLowerCase().contains(q) ||
                n.plainText.toLowerCase().contains(q))
            .toList()
        : notes
            .where((n) => _currentFolderId == null
                ? n.folderId == null
                : n.folderId == _currentFolderId)
            .toList();

    final currentName = _currentFolderId == null
        ? 'Notes'
        : (_folderPath(_currentFolderId, folders).lastOrNull?.name ?? 'Notes');

    return Scaffold(
      appBar: AppBar(
        title: Text(currentName),
        leading: _currentFolderId == null
            ? null
            : IconButton(
                tooltip: 'Dossier parent',
                icon: const Icon(Icons.arrow_upward),
                onPressed: () {
                  final path = _folderPath(_currentFolderId, folders);
                  setState(() => _currentFolderId =
                      path.length < 2 ? null : path[path.length - 2].id);
                },
              ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (v) {
              switch (v) {
                case 'trash':
                  context.push('/notes/trash');
                  break;
                case 'newFolder':
                  _newFolder();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'trash', child: Text('Corbeille')),
              PopupMenuItem(value: 'newFolder', child: Text('Nouveau dossier')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNote(null, folderId: _currentFolderId),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle note'),
      ),
      body: Column(children: [
        // Recherche locale (titre + texte indexable).
        Padding(
          padding: const EdgeInsets.fromLTRB(
              LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, LHSpacing.sm),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _search = ''),
                    )
                  : null,
              hintText: 'Rechercher dans les notes…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LHRadius.xl)),
              isDense: true,
            ),
          ),
        ),
        // Fil d'Ariane (hiérarchie de dossiers).
        if (!searching && _currentFolderId != null)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
              children: [
                _crumb('Notes', theme,
                    onTap: () => setState(() => _currentFolderId = null)),
                for (final f in _folderPath(_currentFolderId, folders))
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Row(children: [
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                      _crumb(f.name, theme,
                          onTap: f.id == _currentFolderId
                              ? null
                              : () => setState(() => _currentFolderId = f.id),
                          current: f.id == _currentFolderId),
                    ]),
                  ),
              ],
            ),
          ),
        Expanded(
          child: (subfolders.isEmpty && visible.isEmpty)
              ? EmptyState(
                  illustration: 'assets/illustrations/notes.png',
                  icon: Icons.sticky_note_2_outlined,
                  message: searching
                      ? 'Aucun résultat'
                      : 'Aucune note ici',
                  hint: searching
                      ? 'Essayez d\'autres mots-clés.'
                      : 'Créez votre première note ou un dossier pour organiser vos idées.',
                  action: FilledButton.tonal(
                    onPressed: () => _openNote(null, folderId: _currentFolderId),
                    child: const Text('Nouvelle note'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 96),
                  children: [
                    if (subfolders.isNotEmpty) ...[
                      _sectionLabel(
                          'DOSSIERS${subfolders.isNotEmpty ? ' (${subfolders.length})' : ''}',
                          theme),
                      for (final f in subfolders)
                        _FolderTile(
                          folder: f,
                          noteCount:
                              notes.where((n) => n.folderId == f.id).length,
                          onOpen: () =>
                              setState(() => _currentFolderId = f.id),
                          onRename: () => _renameFolder(f),
                          onDelete: () => _deleteFolder(f),
                        ),
                      const SizedBox(height: LHSpacing.md),
                    ],
                    if (visible.isNotEmpty) ...[
                      _sectionLabel(
                          searching
                              ? 'RÉSULTATS (${visible.length})'
                              : 'NOTES (${visible.length})',
                          theme),
                      for (final n in visible)
                        _NoteTile(
                          note: n,
                          folderName: n.folderId == null
                              ? null
                              : folders
                                  .where((f) => f.id == n.folderId)
                                  .firstOrNull
                                  ?.name,
                          showFolder: searching,
                          onOpen: () => _openNote(n.id),
                        ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _crumb(String label, ThemeData theme,
      {VoidCallback? onTap, bool current = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(LHRadius.full),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: current
                ? LHColors.or.withValues(alpha: 0.16)
                : theme.colorScheme.outline.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(LHRadius.full),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: current
                  ? LHColors.or
                  : (onTap == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, LHSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.noteCount,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final Folder folder;
  final int noteCount;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.screen, vertical: 4),
      child: LHCard(
        onTap: onOpen,
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: LHSpacing.sm + 2),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: LHColors.or.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(LHRadius.md),
            ),
            child: const Icon(Icons.folder_outlined,
                color: LHColors.or, size: 22),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    noteCount == 0
                        ? 'Vide'
                        : '$noteCount note${noteCount > 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options du dossier',
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  onRename();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ]),
      ),
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({
    required this.note,
    required this.folderName,
    required this.onOpen,
    this.showFolder = false,
  });

  final Note note;
  final String? folderName;
  final VoidCallback onOpen;
  final bool showFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final preview = note.plainText.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.screen, vertical: 4),
      child: LHCard(
        onTap: onOpen,
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: LHSpacing.sm + 2),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (note.pinned ? LHColors.or : theme.colorScheme.outline)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(LHRadius.md),
            ),
            child: Icon(
                note.pinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
                color: note.pinned ? LHColors.or : null,
                size: 20),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (note.pinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.push_pin,
                            size: 13, color: LHColors.or.withValues(alpha: 0.8)),
                      ),
                  ]),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 2),
                  Wrap(spacing: 6, runSpacing: 2, children: [
                    Text(
                      'Modifiée ${relativeTime(note.updatedAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (showFolder && folderName != null)
                      Text(
                        '· $folderName',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ]),
                ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options de la note',
            onSelected: (v) async {
              switch (v) {
                case 'pin':
                  await db.togglePin(note.id, !note.pinned);
                  break;
                case 'trash':
                  await db.trashNote(note.id);
                  if (context.mounted) {
                    lhToast(context,
                        'Note déplacée vers la corbeille (purge après 30 jours)');
                  }
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'pin',
                  child:
                      Text(note.pinned ? 'Détacher' : 'Épingler')),
              const PopupMenuItem(
                  value: 'trash', child: Text('Mettre à la corbeille')),
            ],
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : ÉDITEUR PAR BLOCS (D06 §11.3) ═══════════════════════════

/// Création / édition d'une note — éditeur riche par blocs, versions,
/// épinglage, déplacement, corbeille (D06 §11.1).
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.id, this.folderId});

  final String? id;
  final String? folderId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final List<NoteBlock> _blocks = [];
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  String? _noteId; // id effectif : créé au premier enregistrement
  String? _folderId;
  bool _pinned = false;
  bool _loaded = false;
  bool _loading = true; // neutralise les écouteurs pendant le chargement
  Timer? _autosave;
  int _seq = 0; // générateur d'identifiants de blocs

  // Capturés au premier build : la sauvegarde de rattrapage (dispose) ne
  // peut plus utiliser `ref` — Riverpod l'interdit après le démontage.
  AppDatabase? _db;
  String? _spaceId;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    if (_dirty.value && _db != null) {
      _save(silent: true); // sauvegarde de rattrapage, sans version
    }
    for (final b in _blocks) {
      b.dispose();
    }
    _title.dispose();
    _dirty.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    _noteId = widget.id;
    _db = ref.read(dbProvider);
    _spaceId = ref.read(activeSpaceIdProvider);
    if (widget.id != null) {
      final n = await _db!.getNote(widget.id!);
      if (n != null) {
        _title.text = n.title;
        _folderId = n.folderId;
        _pinned = n.pinned;
        final parsed = parseBlocks(n.blocksJson);
        _blocks.addAll(parsed.isEmpty ? [_newBlock('p')] : parsed);
      }
    } else {
      _folderId = widget.folderId;
      _blocks.add(_newBlock('p'));
    }
    for (final b in _blocks) {
      b.controller.addListener(_onChanged);
    }
    _dirty.value = false; // le remplissage initial n'est pas une modification
    _autosave?.cancel();
    _loading = false;
    if (mounted) setState(() {});
  }

  NoteBlock _newBlock(String type, {String text = ''}) =>
      NoteBlock('blk_${DateTime.now().microsecondsSinceEpoch}_${_seq++}', type,
          text: text);

  // —— Édition des blocs ——

  void _onChanged() {
    if (!_loaded || _loading) return;
    _dirty.value = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 3), () {
      if (mounted) _save(silent: true);
    });
  }

  void _addBlock(String type) {
    final b = _newBlock(type);
    b.controller.addListener(_onChanged);
    setState(() => _blocks.add(b));
    _onChanged();
  }

  void _removeBlock(int i) {
    setState(() {
      _blocks[i].controller.removeListener(_onChanged);
      _blocks[i].dispose();
      _blocks.removeAt(i);
    });
    _onChanged();
  }

  void _moveBlock(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _blocks.length) return;
    setState(() {
      final b = _blocks.removeAt(i);
      _blocks.insert(j, b);
    });
    _onChanged();
  }

  void _setBlockType(int i, String type) {
    if (_blocks[i].type == type) return;
    setState(() => _blocks[i].type = type);
    _onChanged();
  }

  void _toggleChecked(int i) {
    setState(() => _blocks[i].checked = !_blocks[i].checked);
    _onChanged();
  }

  // —— Sauvegarde (D06 §11.1-3) ——

  Future<void> _save({bool silent = false}) async {
    final db = _db;
    final spaceId = _spaceId;
    if (db == null || spaceId == null) return;
    final title = _title.text.trim();
    final blocksJson = encodeBlocks(_blocks);
    final plainText = plainTextOf(_blocks);
    final hasContent = title.isNotEmpty || plainText.isNotEmpty;
    if (!hasContent) {
      if (!silent && mounted) lhToast(context, 'La note est vide.');
      return;
    }
    final now = DateTime.now();
    final existing = _noteId == null ? null : await db.getNote(_noteId!);
    final id = existing?.id ?? 'note_${now.microsecondsSinceEpoch}';
    final note = Note(
      id: id,
      spaceId: existing?.spaceId ?? spaceId,
      folderId: existing?.folderId ?? _folderId,
      title: title.isEmpty ? 'Sans titre' : title,
      blocksJson: blocksJson,
      plainText: plainText,
      pinned: existing?.pinned ?? _pinned,
      trashedAt: existing?.trashedAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveNote(note,
        createVersion: !silent, existed: existing != null);
    _noteId = id;
    _dirty.value = false;
    if (!silent) {
      if (!mounted) return;
      lhToast(context, 'Note enregistrée');
      Navigator.of(context).pop();
    }
  }

  // —— Menu ——

  Future<void> _togglePin() async {
    setState(() => _pinned = !_pinned);
    final db = ref.read(dbProvider);
    if (_noteId != null) await db.togglePin(_noteId!, _pinned);
    if (mounted) {
      lhToast(context, _pinned ? 'Note épinglée' : 'Note détachée');
    }
  }

  Future<void> _showMoveSheet() async {
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final folders = await (db.select(db.folders)
          ..where((f) => f.spaceId.equals(spaceId))
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
        .get();
    if (!mounted) return;
    var selected = _folderId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  LHSpacing.screen, 0, LHSpacing.screen, LHSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Déplacer la note',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: LHSpacing.sm),
                children: [
                  _folderOption(
                    ctx,
                    label: 'Racine (aucun dossier)',
                    icon: Icons.home_outlined,
                    selected: selected == null,
                    onTap: () => setSheet(() => selected = null),
                  ),
                  for (final f in folders)
                    _folderOption(
                      ctx,
                      label: f.name,
                      icon: Icons.folder_outlined,
                      indent: _folderIndent(f, folders),
                      selected: selected == f.id,
                      onTap: () => setSheet(() => selected = f.id),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  LHSpacing.screen, 0, LHSpacing.screen, LHSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _applyMove(selected);
                  },
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Déplacer'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  double _folderIndent(Folder f, List<Folder> all) {
    var depth = 0;
    var pid = f.parentId;
    var guard = 0;
    while (pid != null && guard++ < 50) {
      depth++;
      pid = all.where((x) => x.id == pid).firstOrNull?.parentId;
    }
    return (depth * 16).toDouble();
  }

  Widget _folderOption(BuildContext ctx,
      {required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      double indent = 0}) {
    final theme = Theme.of(ctx);
    return ListTile(
      dense: true,
      contentPadding:
          EdgeInsets.symmetric(horizontal: LHSpacing.screen - 8 + indent),
      leading: Icon(icon,
          size: 20,
          color: selected ? LHColors.or : theme.colorScheme.onSurfaceVariant),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: LHColors.or, size: 20)
          : null,
      onTap: onTap,
    );
  }

  Future<void> _applyMove(String? folderId) async {
    setState(() => _folderId = folderId);
    final db = ref.read(dbProvider);
    if (_noteId != null) await db.moveNote(_noteId!, folderId);
    if (mounted) lhToast(context, 'Note déplacée');
  }

  Future<void> _trash() async {
    final db = ref.read(dbProvider);
    if (_noteId != null) await db.trashNote(_noteId!);
    _dirty.value = false; // pas de sauvegarde fantôme après la corbeille
    if (mounted) Navigator.of(context).pop();
  }

  // —— Historique des versions (D06 §11.4) ——

  Future<void> _showVersions() async {
    final db = ref.read(dbProvider);
    final versions = await db.getNoteVersions(_noteId!);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LHSpacing.screen, 0,
                LHSpacing.screen, LHSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Historique des versions',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          Expanded(
            child: versions.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    message: 'Aucune version',
                    hint:
                        'Enregistrez la note pour créer une première version.',
                  )
                : ListView.builder(
                    itemCount: versions.length,
                    itemBuilder: (ctx, i) {
                      final v = versions[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 20),
                        title: Text(v.label ?? 'Sans libellé',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${fmt.formatLong(v.createdAt)} · ${fmt.formatTime(v.createdAt)}'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () {
                          Navigator.pop(ctx);
                          _previewVersion(v);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Future<void> _previewVersion(NoteVersion v) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(v.title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: _StaticBlocks(v.blocksJson)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _restoreVersion(v);
            },
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: const Text('Restaurer'),
          ),
        ],
      ),
    );
  }

  /// Restaure le contenu : réécrit la note, crée une version « Restauration »
  /// et recharge l'éditeur — l'historique n'est jamais tronqué (D06 §11.4).
  Future<void> _restoreVersion(NoteVersion v) async {
    final db = ref.read(dbProvider);
    await db.restoreNoteVersion(_noteId!, v);
    _loading = true; // les écouteurs ne doivent pas replanifier d'autosave
    setState(() {
      for (final b in _blocks) {
        b.controller.removeListener(_onChanged);
        b.dispose();
      }
      _blocks.clear();
      final parsed = parseBlocks(v.blocksJson);
      _blocks.addAll(parsed.isEmpty ? [_newBlock('p')] : parsed);
      for (final b in _blocks) {
        b.controller.addListener(_onChanged);
      }
      _title.text = v.title;
    });
    _autosave?.cancel();
    _loading = false;
    _dirty.value = false;
    if (mounted) {
      lhToast(context,
          'Version restaurée — une nouvelle version « Restauration » a été créée');
    }
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    final isNew = _noteId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvelle note' : 'Modifier la note'),
        actions: [
          TextButton(
            onPressed: () => _save(),
            child: const Text('Enregistrer'),
          ),
          if (!isNew)
            PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (v) {
                switch (v) {
                  case 'versions':
                    _showVersions();
                    break;
                  case 'move':
                    _showMoveSheet();
                    break;
                  case 'pin':
                    _togglePin();
                    break;
                  case 'trash':
                    _trash();
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'versions',
                    child: Text('Historique des versions')),
                const PopupMenuItem(value: 'move', child: Text('Déplacer')),
                PopupMenuItem(
                    value: 'pin',
                    child: Text(_pinned ? 'Détacher' : 'Épingler')),
                const PopupMenuItem(
                    value: 'trash', child: Text('Mettre à la corbeille')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, 120),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // État de sauvegarde visible (D06 §11.3).
              ValueListenableBuilder<bool>(
                valueListenable: _dirty,
                builder: (context, dirty, _) => Text(
                  dirty
                      ? 'Modifications en cours — enregistrement automatique…'
                      : 'Enregistré',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: dirty
                          ? LHColors.alerte
                          : LHColors.emeraudeClair),
                ),
              ),
              const SizedBox(height: LHSpacing.sm),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: LHFonts.titres),
                decoration: const InputDecoration(
                    hintText: 'Titre de la note', border: InputBorder.none),
                autofocus: isNew,
              ),
              const Divider(height: 1),
              const SizedBox(height: LHSpacing.sm),
              for (final (i, b) in _blocks.indexed)
                _blockTile(i, b, theme),
              const SizedBox(height: LHSpacing.md),
              // Barre d'outils rapide : ajoute un bloc du type choisi.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in noteBlockTypes)
                    ActionChip(
                      label: Text(_quickLabel(t)),
                      onPressed: () => _addBlock(t),
                    ),
                ],
              ),
              const SizedBox(height: LHSpacing.md),
              OutlinedButton.icon(
                onPressed: () => _addBlock('p'),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un bloc'),
              ),
            ]),
      ),
    );
  }

  String _quickLabel(String t) => switch (t) {
        'h1' => 'H1',
        'h2' => 'H2',
        'h3' => 'H3',
        'p' => '¶',
        'bullet' => '•',
        'check' => '✓',
        'quote' => '❝',
        _ => '+',
      };

  Widget _blockTile(int i, NoteBlock b, ThemeData theme) {
    final style = _blockTextStyle(b.type, theme);
    final field = TextField(
      controller: b.controller,
      style: style,
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: blockTypeHint(b.type),
        border: InputBorder.none,
        isDense: true,
        prefixText: b.type == 'bullet' ? '•  ' : null,
        prefixStyle: style,
      ),
    );

    return Padding(
      key: ValueKey(b.id),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sélecteur de type de bloc.
          PopupMenuButton<String>(
            tooltip: 'Type de bloc',
            onSelected: (t) => _setBlockType(i, t),
            itemBuilder: (_) => [
              for (final t in noteBlockTypes)
                PopupMenuItem(
                  value: t,
                  child: Row(children: [
                    Icon(blockTypeIcon(t),
                        size: 18,
                        color: t == b.type ? LHColors.or : null),
                    const SizedBox(width: LHSpacing.sm),
                    Text(blockTypeLabel(t)),
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(blockTypeIcon(b.type),
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          // Case à cocher des blocs « check ».
          if (b.type == 'check')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: b.checked,
                  onChanged: (_) => _toggleChecked(i),
                ),
              ),
            ),
          // Champ du bloc (les citations ont une barre d'accent).
          Expanded(
            child: b.type == 'quote'
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: LHSpacing.sm, vertical: 2),
                    decoration: const BoxDecoration(
                      border: Border(
                          left: BorderSide(color: LHColors.or, width: 2.5)),
                    ),
                    child: field,
                  )
                : field,
          ),
          // Monter / descendre / supprimer.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniAction(
                  Icons.arrow_upward, 'Monter', i > 0 ? () => _moveBlock(i, -1) : null),
              _miniAction(
                  Icons.arrow_downward,
                  'Descendre',
                  i < _blocks.length - 1 ? () => _moveBlock(i, 1) : null),
              _miniAction(Icons.close, 'Supprimer', () => _removeBlock(i)),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle? _blockTextStyle(String type, ThemeData theme) {
    switch (type) {
      case 'h1':
        return theme.textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800, fontFamily: LHFonts.titres);
      case 'h2':
        return theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700, fontFamily: LHFonts.titres);
      case 'h3':
        return theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700, fontFamily: LHFonts.titres);
      case 'quote':
        return theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant);
      default:
        return theme.textTheme.bodyMedium;
    }
  }

  Widget _miniAction(IconData icon, String tooltip, VoidCallback? onTap) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 16,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
      ),
    );
  }
}

/// Aperçu statique (lecture seule) des blocs d'une version.
class _StaticBlocks extends StatelessWidget {
  const _StaticBlocks(this.blocksJson);

  final String blocksJson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<dynamic> list;
    try {
      list = jsonDecode(blocksJson) as List;
    } catch (_) {
      list = [];
    }
    if (list.isEmpty) {
      return Text('Note vide',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in list)
          _staticBlock((e as Map)['type'] as String? ?? 'p',
              (e['text'] as String?) ?? '', e['checked'] == true, theme),
      ],
    );
  }

  Widget _staticBlock(String type, String text, bool checked, ThemeData theme) {
    if (type == 'check') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? LHColors.emeraudeClair : null,
          ),
          const SizedBox(width: LHSpacing.sm),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                    decoration: checked ? TextDecoration.lineThrough : null)),
          ),
        ]),
      );
    }
    if (type == 'bullet') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('•  $text', style: theme.textTheme.bodyMedium),
      );
    }
    if (type == 'quote') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(left: LHSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: LHColors.or, width: 2.5)),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    switch (type) {
      case 'h1':
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(text,
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800, fontFamily: LHFonts.titres)),
        );
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(text,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, fontFamily: LHFonts.titres)),
        );
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(text,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700, fontFamily: LHFonts.titres)),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(text, style: theme.textTheme.bodyMedium),
        );
    }
  }
}

// ═══════════════════════════ ÉCRAN : CORBEILLE (D06 §11.7) ═══════════════════════════

/// Corbeille — restauration pendant 30 jours, purge définitive explicite.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final trashAsync = ref.watch(trashedNotesProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Corbeille'),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (notes) => notes.isEmpty
            ? const EmptyState(
                icon: Icons.delete_outline,
                message: 'La corbeille est vide',
                hint: 'Les notes supprimées restent restaurables pendant 30 jours.',
              )
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(LHSpacing.screen,
                      LHSpacing.sm, LHSpacing.screen, LHSpacing.xs),
                  child: Row(children: [
                    Icon(Icons.info_outline,
                        size: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Purge automatique après 30 jours',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96, top: 4),
                    itemCount: notes.length,
                    itemBuilder: (context, i) =>
                        _TrashTile(note: notes[i]),
                  ),
                ),
              ]),
      ),
    );
  }
}

class _TrashTile extends ConsumerWidget {
  const _TrashTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.screen, vertical: 4),
      child: LHCard(
        padding: const EdgeInsets.symmetric(
            horizontal: LHSpacing.md, vertical: LHSpacing.sm + 2),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (note.plainText.trim().isNotEmpty)
                    Text(
                      note.plainText.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  Text(
                    'Supprimée ${relativeTime(note.trashedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
          ),
          IconButton(
            tooltip: 'Restaurer',
            icon: const Icon(Icons.restore_from_trash_outlined,
                color: LHColors.emeraudeClair),
            onPressed: () async {
              await db.restoreNote(note.id);
              if (context.mounted) lhToast(context, 'Note restaurée');
            },
          ),
          IconButton(
            tooltip: 'Supprimer définitivement',
            icon: const Icon(Icons.delete_forever, color: LHColors.erreur),
            onPressed: () async {
              final ok = await lhConfirm(
                context,
                title: 'Supprimer définitivement ?',
                message:
                    '« ${note.title} » et l\'ensemble de ses versions seront supprimés définitivement. Cette action est irréversible.',
                confirmLabel: 'Supprimer',
                destructive: true,
              );
              if (ok) {
                await db.purgeNote(note.id);
                if (context.mounted) {
                  lhToast(context, 'Note supprimée définitivement');
                }
              }
            },
          ),
        ]),
      ),
    );
  }
}

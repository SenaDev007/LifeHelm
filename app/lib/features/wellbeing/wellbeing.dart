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

// ═══════════════════════════ LABELS BIEN-ÊTRE (D09) ═══════════════════════════

/// Émojis d'humeur 1..5 — subjectif, jamais un diagnostic (D09 §14.2).
const moodEmojis = ['😞', '😕', '😐', '🙂', '😄'];

Color moodColor(int? mood) {
  switch (mood) {
    case 1:
      return LHColors.erreur;
    case 2:
      return LHColors.alerte;
    case 3:
      return LHColors.neutre;
    case 4:
      return LHColors.or;
    case 5:
      return LHColors.emeraudeClair;
    default:
      return LHColors.neutre;
  }
}

/// Moyenne FR à une décimale ; null si aucune valeur (une valeur absente
/// n'est JAMAIS zéro — D09 §14.2).
String avgLabel(Iterable<int> values) {
  final list = values.whereType<int>().toList();
  if (list.isEmpty) return '—';
  final avg = list.reduce((a, b) => a + b) / list.length;
  final s = (avg * 10).round() / 10;
  return s.toStringAsFixed(1).replaceAll('.', ',');
}

List<String> decodeTags(String? json) {
  if (json == null) return [];
  try {
    return (jsonDecode(json) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

// ═══════════════════════════ REQUÊTES D09 ═══════════════════════════

extension WellbeingQueries on AppDatabase {
  // —— Journal ——
  Stream<List<WellbeingEntry>> watchEntries(String spaceId) {
    return (select(wellbeingEntries)
          ..where((e) => e.spaceId.equals(spaceId))
          ..orderBy([
            (e) => OrderingTerm.desc(e.dateKey),
            (e) => OrderingTerm.desc(e.createdAt),
          ]))
        .watch();
  }

  Future<void> saveEntry(WellbeingEntry e, {required bool isNew}) async {
    await into(wellbeingEntries).insert(e, mode: InsertMode.insertOrReplace);
    logOp('WellbeingEntry', e.id, isNew ? 'CREATE' : 'UPDATE',
        {'dateKey': e.dateKey, 'mood': e.mood});
  }

  Future<void> deleteEntry(WellbeingEntry e) async {
    await (delete(wellbeingEntries)..where((x) => x.id.equals(e.id))).go();
    logOp('WellbeingEntry', e.id, 'DELETE', {'dateKey': e.dateKey});
  }

  // —— Bilans quotidiens ——
  Stream<List<DailyReview>> watchDailyReviews(String spaceId) {
    return (select(dailyReviews)
          ..where((r) => r.spaceId.equals(spaceId))
          ..orderBy([(r) => OrderingTerm.desc(r.dateKey)]))
        .watch();
  }

  Future<DailyReview?> getDailyReview(String spaceId, String dateKey) {
    return (select(dailyReviews)
          ..where((r) => r.spaceId.equals(spaceId) & r.dateKey.equals(dateKey)))
        .getSingleOrNull();
  }

  Future<void> saveDailyReview(DailyReview r, {required bool isNew}) async {
    await into(dailyReviews).insert(r, mode: InsertMode.insertOrReplace);
    logOp('DailyReview', r.id, isNew ? 'CREATE' : 'UPDATE',
        {'dateKey': r.dateKey});
  }

  // —— Questions de réflexion ——
  Stream<List<ReflectionQuestion>> watchActiveQuestions() {
    return (select(reflectionQuestions)
          ..where((q) => q.active.equals(true))
          ..orderBy([(q) => OrderingTerm.asc(q.position)]))
        .watch();
  }

  Future<List<ReflectionQuestion>> getActiveQuestions() {
    return (select(reflectionQuestions)
          ..where((q) => q.active.equals(true))
          ..orderBy([(q) => OrderingTerm.asc(q.position)]))
        .get();
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final wellbeingEntriesProvider =
    StreamProvider.family<List<WellbeingEntry>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchEntries(spaceId));

final dailyReviewsProvider = StreamProvider.family<List<DailyReview>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchDailyReviews(spaceId));

final reflectionQuestionsProvider = StreamProvider<List<ReflectionQuestion>>(
    (ref) => ref.watch(dbProvider).watchActiveQuestions());

// ═══════════════════════════ ÉCRAN : BIEN-ÊTRE ═══════════════════════════

/// Journal & indicateurs — privé par défaut (D09 §14.1-4).
class WellbeingScreen extends ConsumerWidget {
  const WellbeingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final entriesAsync = ref.watch(wellbeingEntriesProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Bien-être'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _EntrySheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle entrée'),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (entries) => _WellbeingBody(entries: entries),
      ),
    );
  }
}

class _WellbeingBody extends StatelessWidget {
  const _WellbeingBody({required this.entries});

  final List<WellbeingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = fmt.today();
    final fromKey = fmt.dateKey(fmt.addDays(today, -6));
    final toKey = fmt.dateKey(today);
    final last7 = entries
        .where((e) =>
            e.dateKey.compareTo(fromKey) >= 0 &&
            e.dateKey.compareTo(toKey) <= 0)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        // Bandeau confidentialité (D09 : privé par défaut, partage explicite).
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            Icon(Icons.lock_outline,
                size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Privé par défaut — les données de bien-être restent dans cet espace.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ]),
        ),

        // Résumé 7 jours : moyennes humeur / énergie / stress.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: LHCard(
            accent: LHColors.or.withValues(alpha: 0.85),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('7 derniers jours', style: theme.textTheme.titleSmall),
              const SizedBox(height: LHSpacing.md),
              Row(children: [
                Expanded(
                  child: StatTile(
                    label: 'Humeur moy.',
                    value: avgLabel(last7.map((e) => e.mood).whereType<int>()),
                    color: LHColors.or,
                    icon: Icons.mood_outlined,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Énergie moy.',
                    value:
                        avgLabel(last7.map((e) => e.energy).whereType<int>()),
                    color: LHColors.emeraudeClair,
                    icon: Icons.bolt_outlined,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Stress moy.',
                    value:
                        avgLabel(last7.map((e) => e.stress).whereType<int>()),
                    color: LHColors.info,
                    icon: Icons.spa_outlined,
                  ),
                ),
              ]),
              const SizedBox(height: LHSpacing.md),
              // Mini-graphe barres : humeur des 7 derniers jours.
              _MoodBars(entries: last7),
            ]),
          ),
        ),

        // Timeline du journal.
        SectionHeader('Journal',
            inset: LHSpacing.screen,
            overline: 'Entrées',
            action: TextButton(
              onPressed: () => context.push('/wellbeing/review'),
              child: const Text('Bilan du jour'),
            )),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState(
                illustration: 'assets/illustrations/wellbeing.png',
                icon: Icons.book_outlined,
                message:
                    'Aucune entrée dans le journal.\nNotez votre humeur du jour pour démarrer.'),
          )
        else
          for (final e in entries)
            _EntryTile(
                entry: e, onTap: () => _EntrySheet.show(context, existing: e)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Astuce : humeur, énergie et stress sont facultatifs — une valeur absente n\'est jamais comptée comme zéro.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Barres d'humeur : hauteur ∝ valeur/5, couleur selon le niveau.
/// Jours sans humeur : talon discret en contour (pas de zéro).
class _MoodBars extends StatelessWidget {
  const _MoodBars({required this.entries});

  final List<WellbeingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = fmt.today();
    final days = [for (var i = 6; i >= 0; i--) fmt.addDays(today, -i)];
    final byDay = <String, WellbeingEntry>{};
    for (final e in entries) {
      final existing = byDay[e.dateKey];
      // Plusieurs entrées par jour : la dernière créée l'emporte.
      if (existing == null || e.createdAt.isAfter(existing.createdAt)) {
        byDay[e.dateKey] = e;
      }
    }

    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 16,
                  height: (byDay[fmt.dateKey(d)]?.mood != null)
                      ? 8 + 38 * (byDay[fmt.dateKey(d)]!.mood! / 5)
                      : 4,
                  decoration: BoxDecoration(
                    color: byDay[fmt.dateKey(d)]?.mood != null
                        ? moodColor(byDay[fmt.dateKey(d)]!.mood)
                        : null,
                    border: byDay[fmt.dateKey(d)]?.mood != null
                        ? null
                        : Border.all(color: theme.colorScheme.outline),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  fmt.weekdaysFr[d.weekday - 1],
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: fmt.isSameDay(d, today)
                          ? LHColors.or
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          fmt.isSameDay(d, today) ? FontWeight.w800 : null),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final WellbeingEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = decodeTags(entry.tagsJson);
    final mood = entry.mood;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LHCard(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: moodColor(mood).withValues(alpha: 0.14),
              border:
                  Border.all(color: moodColor(mood).withValues(alpha: 0.55)),
            ),
            child: Text(mood != null ? moodEmojis[mood - 1] : '—',
                style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  fmt.humanDate(fmt.parseKey(entry.dateKey)),
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (entry.energy != null)
                  Text('⚡ ${entry.energy}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                if (entry.stress != null) ...[
                  const SizedBox(width: 8),
                  Text('🧘 ${entry.stress}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ]),
              if (entry.note != null && entry.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry.note!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final t in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(LHRadius.full),
                      ),
                      child: Text('#$t',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Feuille de saisie/édition d'une entrée (modal).
class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({this.existing});

  final WellbeingEntry? existing;

  /// Ouvre la feuille (création ou édition — même modal prérempli).
  static Future<void> show(BuildContext context,
      {WellbeingEntry? existing}) async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(existing: existing),
    );
  }

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  late final TextEditingController _note;
  late final TextEditingController _tags;

  late String _dateKey;
  int? _mood;
  int? _energy;
  int? _stress;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _note = TextEditingController(text: e?.note ?? '');
    _tags = TextEditingController(
        text: e == null ? '' : decodeTags(e.tagsJson).join(', '));
    _dateKey = e?.dateKey ?? fmt.dateKey(fmt.today());
    _mood = e?.mood;
    _energy = e?.energy;
    _stress = e?.stress;
  }

  @override
  void dispose() {
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fmt.parseKey(_dateKey),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _dateKey = fmt.dateKey(picked));
  }

  Future<void> _save() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final e = widget.existing;
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final entry = WellbeingEntry(
      id: e?.id ?? 'wbe_${now.microsecondsSinceEpoch}',
      spaceId: e?.spaceId ?? ref.read(activeSpaceIdProvider),
      dateKey: _dateKey,
      mood: _mood,
      energy: _energy,
      stress: _stress,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      tagsJson: tags.isEmpty ? null : jsonEncode(tags),
      createdAt: e?.createdAt ?? now,
    );
    await db.saveEntry(entry, isNew: e == null);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await lhConfirm(
      context,
      title: 'Supprimer cette entrée ?',
      message:
          'L\'entrée du ${fmt.formatShort(fmt.parseKey(e.dateKey))} sera supprimée (journalisée pour la synchronisation).',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(dbProvider).deleteEntry(e);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: LHSpacing.screen,
        right: LHSpacing.screen,
        top: LHSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEdit ? 'Modifier l\'entrée' : 'Nouvelle entrée',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: LHSpacing.md),

            // Date (défaut : aujourd'hui)
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(LHRadius.md),
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Date', icon: Icon(Icons.event_outlined)),
                child: Text(fmt.formatFull(fmt.parseKey(_dateKey))),
              ),
            ),
            const SizedBox(height: LHSpacing.md),

            // Humeur 1..5 (facultative)
            _EmojiScale(
              label: 'Humeur (facultative)',
              value: _mood,
              onChanged: (v) => setState(() => _mood = v),
            ),
            const SizedBox(height: LHSpacing.md),
            _NumberScale(
              label: 'Énergie (facultative)',
              value: _energy,
              icon: '⚡',
              onChanged: (v) => setState(() => _energy = v),
            ),
            const SizedBox(height: LHSpacing.md),
            _NumberScale(
              label: 'Stress (facultative)',
              value: _stress,
              icon: '🧘',
              onChanged: (v) => setState(() => _stress = v),
            ),
            const SizedBox(height: LHSpacing.md),

            TextField(
              controller: _note,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Note', hintText: 'Comment était votre journée ?'),
            ),
            const SizedBox(height: LHSpacing.md),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                  labelText: 'Étiquettes',
                  hintText: 'séparées par des virgules',
                  prefixIcon: Icon(Icons.tag_outlined)),
            ),
            const SizedBox(height: LHSpacing.lg),

            Row(children: [
              if (isEdit)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: LHColors.erreur),
                  onPressed: _delete,
                  child: const Text('Supprimer'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Sélecteur d'humeur : 5 émojis, re-tap pour désélectionner.
class _EmojiScale extends StatelessWidget {
  const _EmojiScale(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value == i ? null : i),
              child: Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      value == i ? moodColor(i).withValues(alpha: 0.16) : null,
                  border: Border.all(
                    color:
                        value == i ? moodColor(i) : theme.colorScheme.outline,
                    width: value == i ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(LHRadius.md),
                ),
                child: Text(moodEmojis[i - 1],
                    style: TextStyle(
                        fontSize: 22, color: value == i ? moodColor(i) : null)),
              ),
            ),
          ),
      ]),
    ]);
  }
}

/// Sélecteur numérique 1..5 (énergie, stress), désélection possible.
class _NumberScale extends StatelessWidget {
  const _NumberScale(
      {required this.label,
      required this.value,
      required this.icon,
      required this.onChanged});

  final String label;
  final int? value;
  final String icon;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Row(children: [
        Text('$icon ', style: const TextStyle(fontSize: 16)),
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$i'),
              selected: value == i,
              onSelected: (sel) => onChanged(sel ? i : null),
              labelStyle: TextStyle(
                  // Règle n°3 : jamais d'or brut sur lavis doré.
                  color: value == i
                      ? LHContrast.selectedChipLabel(Theme.of(context).brightness)
                      : null,
                  fontWeight: FontWeight.w700),
            ),
          ),
      ]),
    ]);
  }
}

// ═══════════════════════════ ÉCRAN : BILAN DU JOUR ═══════════════════════════

/// Bilan quotidien guidé — réponses aux questions de réflexion actives,
/// note de synthèse, mise à jour si un bilan existe déjà (D09 §14.1-3).
class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({super.key});

  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen> {
  final _noteCtrl = TextEditingController();
  final _answers = <String, TextEditingController>{};

  List<ReflectionQuestion> _questions = [];
  DailyReview? _existing;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    _questions = await db.getActiveQuestions();
    final todayKey = fmt.dateKey(fmt.today());
    _existing = await db.getDailyReview(spaceId, todayKey);

    // Préremplissage depuis answersJson [{"q":..,"a":..}].
    final byQuestion = <String, String>{};
    if (_existing != null) {
      try {
        final list = (jsonDecode(_existing!.answersJson) as List)
            .cast<Map<String, dynamic>>();
        for (final m in list) {
          byQuestion[m['q'] as String? ?? ''] = m['a'] as String? ?? '';
        }
      } catch (_) {/* answersJson illisible : on repart à blanc */}
    }
    for (final q in _questions) {
      _answers[q.id] =
          TextEditingController(text: byQuestion[q.question] ?? '');
    }
    _noteCtrl.text = _existing?.note ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final todayKey = fmt.dateKey(fmt.today());

    final answers = <Map<String, String>>[];
    for (final q in _questions) {
      final a = _answers[q.id]?.text.trim() ?? '';
      if (a.isNotEmpty) answers.add({'q': q.question, 'a': a});
    }

    final existing = _existing;
    final review = DailyReview(
      id: existing?.id ?? 'review_${now.microsecondsSinceEpoch}',
      spaceId: existing?.spaceId ?? ref.read(activeSpaceIdProvider),
      dateKey: todayKey,
      answersJson: jsonEncode(answers),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      createdAt: existing?.createdAt ?? now,
    );
    await db.saveDailyReview(review, isNew: existing == null);
    if (!mounted) return;
    setState(() => _saving = false);
    lhToast(
        context, existing == null ? 'Bilan enregistré' : 'Bilan mis à jour');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final reviewsAsync = ref.watch(dailyReviewsProvider(spaceId));
    final todayKey = fmt.dateKey(fmt.today());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilan du jour'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_existing == null ? 'Enregistrer' : 'Mettre à jour')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        children: [
          Text(fmt.formatFull(fmt.today()),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: LHSpacing.md),

          if (_questions.isEmpty)
            const EmptyState(
                icon: Icons.help_outline,
                message:
                    'Aucune question de réflexion active.\nAjoutez-en pour guider votre bilan.')
          else ...[
            for (final q in _questions) ...[
              Text(q.question,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _answers[q.id],
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Votre réponse…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(LHRadius.md)),
                ),
              ),
              const SizedBox(height: LHSpacing.lg),
            ],
          ],

          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Synthèse du jour',
              hintText: 'Ce que vous retenez de cette journée…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LHRadius.md)),
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.done_all),
            label: Text(_existing == null
                ? 'Enregistrer le bilan'
                : 'Mettre à jour le bilan'),
          ),

          // 7 derniers bilans (hors aujourd'hui, en cours d'édition ci-dessus).
          SectionHeader('Bilans récents', overline: 'Historique'),
          reviewsAsync.when(
            loading: () => const SizedBox(),
            error: (e, st) => const SizedBox(),
            data: (reviews) {
              final recent = reviews
                  .where((r) => r.dateKey.compareTo(todayKey) < 0)
                  .take(7)
                  .toList();
              if (recent.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun bilan antérieur.',
                      textAlign: TextAlign.center),
                );
              }
              return Column(children: [
                for (final r in recent)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                    child: LHCard(
                      onTap: () {},
                      child: Row(children: [
                        const Icon(Icons.auto_awesome_outlined,
                            color: LHColors.or, size: 22),
                        const SizedBox(width: LHSpacing.md),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fmt.humanDate(fmt.parseKey(r.dateKey)),
                                    style: theme.textTheme.titleSmall),
                                if (r.note != null && r.note!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(r.note!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              ]),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

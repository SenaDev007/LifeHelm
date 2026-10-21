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

// ═══════════════════════════ LABELS & COULEURS (D08) ═══════════════════════════

/// Palette proposée pour les habitudes (8 couleurs).
const habitPalette = [
  '#22C55E', '#FFB400', '#3B82F6', '#FF7A00',
  '#E05B5B', '#8B5CF6', '#E8A13D', '#5BB8D9',
];

/// Bleu clair « jour de repos » (distinct de la palette d'états — D08).
const Color lhRest = Color(0xFF9EC9E8);

Color hexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

/// Statut d'occurrence → couleur (DONE émeraude, MISSED rouge, SKIPPED gris,
/// REST bleu clair, PENDING contour — statuts distincts, D08 §13.1-2).
Color occurrenceColor(String status) {
  switch (status) {
    case 'DONE':
      return LHColors.succes;
    case 'MISSED':
      return LHColors.erreur;
    case 'SKIPPED':
      return LHColors.neutre;
    case 'REST':
      return lhRest;
    default:
      return LHColors.neutre;
  }
}

String occurrenceLabel(String status) {
  switch (status) {
    case 'DONE':
      return 'Fait';
    case 'MISSED':
      return 'Manquée';
    case 'SKIPPED':
      return 'Ignorée';
    case 'REST':
      return 'Repos';
    default:
      return 'À faire';
  }
}

const dayNamesFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

List<int> decodeWeekdays(String? json) {
  if (json == null) return [];
  try {
    return (jsonDecode(json) as List).cast<int>()..sort();
  } catch (_) {
    return [];
  }
}

/// Jour programmé par ce plan ? (D08 : DAILY / WEEKLY / INTERVAL —
/// les jours non programmés ne créée RIEN et ne casse pas une série).
bool isScheduledOn(HabitSchedule? s, DateTime d) {
  if (s == null) return false;
  final since = fmt.parseKey(s.sinceKey);
  final day = DateTime(d.year, d.month, d.day);
  if (day.isBefore(since)) return false;
  switch (s.freq) {
    case 'DAILY':
      return true;
    case 'WEEKLY':
      return decodeWeekdays(s.weekdaysJson).contains(d.weekday);
    case 'INTERVAL':
      final n = s.intervalDays ?? 1;
      if (n < 1) return false;
      final diff = fmt.daysBetween(since, day);
      return diff >= 0 && diff % n == 0;
    default:
      return false;
  }
}

String scheduleSummary(HabitSchedule? s) {
  if (s == null) return 'Sans planification';
  switch (s.freq) {
    case 'DAILY':
      return 'Quotidienne';
    case 'WEEKLY':
      final wd = decodeWeekdays(s.weekdaysJson);
      if (wd.isEmpty) return 'Hebdomadaire';
      return [for (final d in wd) dayNamesFr[d - 1]].join(', ');
    case 'INTERVAL':
      return 'Tous les ${s.intervalDays ?? 1} jours';
    default:
      return s.freq;
  }
}

/// Format FR d'une valeur quantitative (jamais zéro par défaut : null = « — »).
String qtyLabel(double? v) {
  if (v == null) return '—';
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return s.replaceAll('.', ',');
}

HabitSchedule? scheduleFor(List<HabitSchedule> schedules, String habitId) {
  final ofHabit = schedules.where((s) => s.habitId == habitId).toList();
  if (ofHabit.isEmpty) return null;
  ofHabit.sort((a, b) => b.sinceKey.compareTo(a.sinceKey));
  return ofHabit.first;
}

// ═══════════════════════════ REQUÊTES D08 ═══════════════════════════

extension HabitQueries on AppDatabase {
  // —— Habitudes ——
  Stream<List<Habit>> watchHabits(String spaceId) {
    return (select(habits)
          ..where((h) => h.spaceId.equals(spaceId) & h.archivedAt.isNull())
          ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
        .watch();
  }

  Stream<Habit?> watchHabit(String id) =>
      (select(habits)..where((h) => h.id.equals(id))).watchSingleOrNull();

  Future<Habit?> getHabit(String id) =>
      (select(habits)..where((h) => h.id.equals(id))).getSingleOrNull();

  Future<void> saveHabit(Habit h, {required bool isNew}) async {
    await into(habits).insert(h, mode: InsertMode.insertOrReplace);
    logOp('Habit', h.id, isNew ? 'CREATE' : 'UPDATE',
        {'name': h.name, 'trackingType': h.trackingType});
  }

  Future<void> archiveHabit(String id, bool archived) async {
    await (update(habits)..where((h) => h.id.equals(id)))
        .write(HabitsCompanion(
            archivedAt: Value(archived ? DateTime.now() : null)));
    logOp('Habit', id, 'UPDATE', {'archived': archived});
  }

  // —— Planifications ——
  Stream<List<HabitSchedule>> watchAllSchedules() {
    return (select(habitSchedules)
          ..orderBy([(s) => OrderingTerm.asc(s.sinceKey)]))
        .watch();
  }

  Future<HabitSchedule?> getSchedule(String habitId) =>
      (select(habitSchedules)..where((s) => s.habitId.equals(habitId)))
          .getSingleOrNull();

  Future<void> upsertSchedule(HabitSchedule s, {required bool isNew}) async {
    await into(habitSchedules).insert(s, mode: InsertMode.insertOrReplace);
    logOp('HabitSchedule', s.habitId, isNew ? 'CREATE' : 'UPDATE',
        {'freq': s.freq, 'sinceKey': s.sinceKey});
  }

  // —— Occurrences ——
  /// Toutes les occurrences des habitudes actives de l'espace (jointure).
  Stream<List<HabitOccurrence>> watchSpaceOccurrences(String spaceId) {
    final query = select(habitOccurrences).join([
      innerJoin(habits, habits.id.equalsExp(habitOccurrences.habitId)),
    ]);
    query.where(habits.spaceId.equals(spaceId));
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(habitOccurrences)).toList());
  }

  Stream<List<HabitOccurrence>> watchHabitOccurrences(String habitId) {
    return (select(habitOccurrences)
          ..where((o) => o.habitId.equals(habitId))
          ..orderBy([(o) => OrderingTerm.desc(o.dateKey)]))
        .watch();
  }

  /// Mutations d'occurrence : manquée ≠ ignorée (D08 §13.1-2).
  Future<void> setOccurrenceStatus(String id,
      {required String status, double? value}) async {
    await (update(habitOccurrences)..where((o) => o.id.equals(id))).write(
        HabitOccurrencesCompanion(
            status: Value(status),
            value: Value(value),
            updatedAt: Value(DateTime.now())));
    logOp('HabitOccurrence', id, 'UPDATE', {'status': status, 'value': value});
  }

  // —— Routines ——
  Stream<List<Routine>> watchRoutines(String spaceId) {
    return (select(routines)
          ..where((r) => r.spaceId.equals(spaceId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  Stream<Routine?> watchRoutine(String id) =>
      (select(routines)..where((r) => r.id.equals(id))).watchSingleOrNull();

  Future<Routine?> getRoutine(String id) =>
      (select(routines)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> saveRoutine(Routine r, {required bool isNew}) async {
    await into(routines).insert(r, mode: InsertMode.insertOrReplace);
    logOp('Routine', r.id, isNew ? 'CREATE' : 'UPDATE', {'name': r.name});
  }

  Future<void> deleteRoutine(String id) async {
    await (delete(routineSteps)..where((s) => s.routineId.equals(id))).go();
    await (delete(routineOccurrences)..where((o) => o.routineId.equals(id)))
        .go();
    await (delete(routines)..where((r) => r.id.equals(id))).go();
    logOp('Routine', id, 'DELETE', {'cascade': true});
  }

  // —— Étapes de routine ——
  Stream<List<RoutineStep>> watchRoutineSteps(String routineId) {
    return (select(routineSteps)
          ..where((s) => s.routineId.equals(routineId))
          ..orderBy([(s) => OrderingTerm.asc(s.position)]))
        .watch();
  }

  Future<void> addRoutineStep(String routineId,
      {String? habitId, required String label}) async {
    final existing = await (select(routineSteps)
          ..where((s) => s.routineId.equals(routineId)))
        .get();
    final id = 'rstep_${DateTime.now().microsecondsSinceEpoch}';
    await into(routineSteps).insert(RoutineStep(
        id: id,
        routineId: routineId,
        habitId: habitId,
        label: label,
        position: existing.length));
    logOp('RoutineStep', id, 'CREATE',
        {'routineId': routineId, 'habitId': habitId, 'label': label});
  }

  Future<void> deleteRoutineStep(String id) async {
    await (delete(routineSteps)..where((s) => s.id.equals(id))).go();
    logOp('RoutineStep', id, 'DELETE', {});
  }

  /// Réordonnancement persistant (flèches haut/bas) : réécrit les positions.
  Future<void> writeStepPositions(List<RoutineStep> ordered) async {
    if (ordered.isEmpty) return;
    for (final (i, s) in ordered.indexed) {
      await (update(routineSteps)..where((x) => x.id.equals(s.id)))
          .write(RoutineStepsCompanion(position: Value(i)));
    }
    logOp('RoutineStep', ordered.first.routineId, 'UPDATE',
        {'reordered': ordered.length});
  }

  // —— Exécution du jour ——
  /// Occurrence du jour, créée paresseusement (doneCount 0).
  Future<RoutineOccurrence> ensureRoutineOccurrence(String routineId) async {
    final todayKey = fmt.dateKey(fmt.today());
    final existing = await (select(routineOccurrences)
          ..where((o) =>
              o.routineId.equals(routineId) & o.dateKey.equals(todayKey)))
        .getSingleOrNull();
    if (existing != null) return existing;
    final occ = RoutineOccurrence(
        id: '${routineId}_$todayKey',
        routineId: routineId,
        dateKey: todayKey,
        doneCount: 0);
    await into(routineOccurrences).insert(occ, mode: InsertMode.insertOrIgnore);
    logOp('RoutineOccurrence', occ.id, 'CREATE', {'dateKey': todayKey});
    return occ;
  }

  Stream<RoutineOccurrence?> watchTodayOccurrence(String routineId) {
    final todayKey = fmt.dateKey(fmt.today());
    return (select(routineOccurrences)
          ..where((o) =>
              o.routineId.equals(routineId) & o.dateKey.equals(todayKey)))
        .watchSingleOrNull();
  }

  Future<void> setRoutineDoneCount(String id, int count) async {
    await (update(routineOccurrences)..where((o) => o.id.equals(id)))
        .write(RoutineOccurrencesCompanion(doneCount: Value(count)));
    logOp('RoutineOccurrence', id, 'UPDATE', {'doneCount': count});
  }
}

// ═══════════════════════════ GÉNÉRATION PARESSEUSE (D08) ═══════════════════════════

/// Crée les occurrences PENDING des jours programmés entre fromKey et toKey.
/// Idempotent : identifiant déterministe `<habitId>_<dateKey>` + insertOrIgnore.
/// Ne crée RIEN pour les jours non programmés (repos — D08 §13.2).
Future<void> ensureOccurrences(AppDatabase db, Habit habit,
    HabitSchedule? schedule, String fromKey, String toKey) async {
  if (schedule == null) return;
  final from = fmt.parseKey(fromKey);
  final to = fmt.parseKey(toKey);
  if (from.isAfter(to)) return;

  final existing = await (db.select(db.habitOccurrences)
        ..where((o) => o.habitId.equals(habit.id)))
      .get();
  final knownKeys = existing.map((o) => o.dateKey).toSet();

  final rows = <HabitOccurrence>[];
  for (var d = from; !d.isAfter(to); d = fmt.addDays(d, 1)) {
    final day = DateTime(d.year, d.month, d.day);
    if (!isScheduledOn(schedule, day)) continue;
    final dk = fmt.dateKey(day);
    if (knownKeys.contains(dk)) continue;
    rows.add(HabitOccurrence(
        id: '${habit.id}_$dk',
        habitId: habit.id,
        dateKey: dk,
        status: 'PENDING',
        updatedAt: DateTime.now()));
  }
  if (rows.isEmpty) return;
  await db.batch((b) {
    for (final r in rows) {
      b.insert(db.habitOccurrences, r, mode: InsertMode.insertOrIgnore);
    }
  });
}

// ═══════════════════════════ STATISTIQUES (D08) ═══════════════════════════

/// Série actuelle : jours programmés consécutifs en DONE.
/// SKIPPED et jours non programmés ne cassent PAS la série ;
/// MISSED ou passé non saisi la casse (D08 §13.1-5).
int computeStreak(HabitSchedule? sched, List<HabitOccurrence> occs) {
  final byKey = {for (final o in occs) o.dateKey: o};
  final today = fmt.today();
  var streak = 0;
  for (var i = 0; i < 366; i++) {
    final d = fmt.addDays(today, -i);
    final dk = fmt.dateKey(d);
    final scheduled = sched == null ? byKey.containsKey(dk) : isScheduledOn(sched, d);
    final o = byKey[dk];
    final isToday = i == 0;
    if (o == null) {
      if (!scheduled) continue; // jour de repos
      if (isToday) continue; // pas encore généré aujourd'hui
      break; // passé non saisi
    }
    if (o.status == 'DONE') {
      streak++;
      continue;
    }
    if (o.status == 'SKIPPED' || o.status == 'REST') continue; // ne casse pas
    if (o.status == 'PENDING' && isToday) continue; // jour en cours
    break; // MISSED, ou PENDING dans le passé
  }
  return streak;
}

/// Taux de réussite sur 30 jours : DONE / (DONE + MISSED + passé non saisi).
/// SKIPPED (repos délibéré) et jours non programmés sont exclus du dénominateur.
/// Retourne null si aucun jour évaluable (« — », jamais zéro).
double? computeRate30(HabitSchedule? sched, List<HabitOccurrence> occs) {
  final byKey = {for (final o in occs) o.dateKey: o};
  final today = fmt.today();
  var done = 0;
  var denom = 0;
  for (var i = 0; i < 30; i++) {
    final d = fmt.addDays(today, -i);
    final dk = fmt.dateKey(d);
    final scheduled = sched == null ? byKey.containsKey(dk) : isScheduledOn(sched, d);
    if (!scheduled) continue;
    final o = byKey[dk];
    if (o == null) {
      if (i == 0) continue; // aujourd'hui pas encore saisi
      denom++; // passé non saisi : échec
      continue;
    }
    if (o.status == 'DONE') {
      done++;
      denom++;
    } else if (o.status == 'MISSED') {
      denom++;
    } else if (o.status == 'PENDING' && i > 0) {
      denom++; // passé non saisi
    }
    // SKIPPED / REST / PENDING-aujourd'hui : exclus
  }
  if (denom == 0) return null;
  return done / denom;
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final habitsProvider = StreamProvider.family<List<Habit>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchHabits(spaceId));

final allSchedulesProvider = StreamProvider<List<HabitSchedule>>(
    (ref) => ref.watch(dbProvider).watchAllSchedules());

final spaceOccurrencesProvider =
    StreamProvider.family<List<HabitOccurrence>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchSpaceOccurrences(spaceId));

final habitProvider = StreamProvider.family<Habit?, String>(
    (ref, id) => ref.watch(dbProvider).watchHabit(id));

final habitOccurrencesProvider =
    StreamProvider.family<List<HabitOccurrence>, String>(
        (ref, habitId) => ref.watch(dbProvider).watchHabitOccurrences(habitId));

final routinesProvider = StreamProvider.family<List<Routine>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchRoutines(spaceId));

final routineProvider = StreamProvider.family<Routine?, String>(
    (ref, id) => ref.watch(dbProvider).watchRoutine(id));

final routineStepsProvider =
    StreamProvider.family<List<RoutineStep>, String>(
        (ref, routineId) => ref.watch(dbProvider).watchRoutineSteps(routineId));

final todayRoutineOccurrenceProvider =
    StreamProvider.family<RoutineOccurrence?, String>((ref, routineId) =>
        ref.watch(dbProvider).watchTodayOccurrence(routineId));

// ═══════════════════════════ ÉCRAN : HABITUDES ═══════════════════════════

enum _HabitsView { today, week, stats }

/// Suivi des habitudes — aujourd'hui / semaine / stats (D08).
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final habitsAsync = ref.watch(habitsProvider(spaceId));
    final schedulesAsync = ref.watch(allSchedulesProvider);
    final occurrencesAsync = ref.watch(spaceOccurrencesProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Habitudes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/habit/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle habitude'),
      ),
      body: habitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (habits) {
          final schedules = schedulesAsync.valueOrNull ?? [];
          final occurrences = occurrencesAsync.valueOrNull ?? [];
          // Génération paresseuse : 60 derniers jours (D08 §13.2).
          unawaited(_ensureAllOccurrences(ref, habits, schedules));
          return _HabitsBody(
              habits: habits,
              schedules: schedules,
              occurrences: occurrences);
        },
      ),
    );
  }

  Future<void> _ensureAllOccurrences(WidgetRef ref, List<Habit> habits,
      List<HabitSchedule> schedules) async {
    if (habits.isEmpty) return;
    final db = ref.read(dbProvider);
    final today = fmt.today();
    final fromKey = fmt.dateKey(fmt.addDays(today, -60));
    final toKey = fmt.dateKey(today);
    for (final h in habits) {
      await ensureOccurrences(
          db, h, scheduleFor(schedules, h.id), fromKey, toKey);
    }
  }
}

class _HabitsBody extends StatefulWidget {
  const _HabitsBody(
      {required this.habits,
      required this.schedules,
      required this.occurrences});

  final List<Habit> habits;
  final List<HabitSchedule> schedules;
  final List<HabitOccurrence> occurrences;

  @override
  State<_HabitsBody> createState() => _HabitsBodyState();
}

class _HabitsBodyState extends State<_HabitsBody> {
  _HabitsView _view = _HabitsView.today;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, LHSpacing.sm),
        child: LhSegmented<_HabitsView>(
          value: _view,
          items: const {
            _HabitsView.today: 'Aujourd\'hui',
            _HabitsView.week: 'Semaine',
            _HabitsView.stats: 'Stats',
          },
          onChanged: (v) => setState(() => _view = v),
        ),
      ),
      Expanded(
        child: switch (_view) {
          _HabitsView.today => _TodayView(
              habits: widget.habits,
              schedules: widget.schedules,
              occurrences: widget.occurrences),
          _HabitsView.week => _WeekView(
              habits: widget.habits,
              schedules: widget.schedules,
              occurrences: widget.occurrences),
          _HabitsView.stats => _StatsView(
              habits: widget.habits,
              schedules: widget.schedules,
              occurrences: widget.occurrences),
        },
      ),
    ]);
  }
}

// ———————— Vue « Aujourd'hui » ————————

class _TodayView extends StatelessWidget {
  const _TodayView(
      {required this.habits,
      required this.schedules,
      required this.occurrences});

  final List<Habit> habits;
  final List<HabitSchedule> schedules;
  final List<HabitOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (habits.isEmpty) {
      return EmptyState(
        illustration: 'assets/illustrations/habits.png',
        icon: Icons.self_improvement_outlined,
        message: 'Aucune habitude active',
        hint:
            'Créez une habitude pour suivre vos routines jour après jour.',
        action: FilledButton.tonal(
          onPressed: () => context.push('/habit/new'),
          child: const Text('Nouvelle habitude'),
        ),
      );
    }
    final todayKey = fmt.dateKey(fmt.today());
    final todayOccs = {
      for (final o in occurrences.where((o) => o.dateKey == todayKey))
        o.habitId: o
    };
    final done = todayOccs.values.where((o) => o.status == 'DONE').length;
    final missed = todayOccs.values.where((o) => o.status == 'MISSED').length;
    final scheduledCount = todayOccs.length;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      itemCount: habits.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              scheduledCount == 0
                  ? 'Rien de programmé aujourd\'hui.'
                  : '$done/$scheduledCount faite(s)'
                      '${missed > 0 ? ' · $missed manquée(s)' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        final h = habits[i - 1];
        return _HabitTodayTile(
          habit: h,
          schedule: scheduleFor(schedules, h.id),
          occurrence: todayOccs[h.id],
        );
      },
    );
  }
}

class _HabitTodayTile extends ConsumerWidget {
  const _HabitTodayTile(
      {required this.habit, required this.schedule, this.occurrence});

  final Habit habit;
  final HabitSchedule? schedule;
  final HabitOccurrence? occurrence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final color = hexColor(habit.colorHex);
    final occ = occurrence;
    final isRest = occ == null;
    final status = occ?.status ?? 'REST';
    final isQuantity = habit.trackingType == 'QUANTITY';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LHCard(
        onTap: () => context.push('/habit/${habit.id}'),
        child: Row(children: [
          // Zone d'action principale
          _TodayAction(
            habit: habit,
            color: color,
            status: status,
            value: occ?.value,
            isRest: isRest,
            onToggle: () {
              if (isRest) {
                lhToast(context, 'Repos : habitude non programmée aujourd\'hui.');
                return;
              }
              switch (status) {
                case 'DONE':
                  db.setOccurrenceStatus(occ.id, status: 'PENDING', value: occ.value);
                  break;
                case 'PENDING':
                  db.setOccurrenceStatus(occ.id, status: 'DONE', value: occ.value);
                  break;
                default:
                  db.setOccurrenceStatus(occ.id, status: 'DONE', value: occ.value);
              }
            },
            onQuantityTap: () => isRest
                ? lhToast(context, 'Repos : habitude non programmée aujourd\'hui.')
                : _openQuantityDialog(context, db, occ),
          ),
          const SizedBox(width: LHSpacing.md),
          // Contenu
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(habit.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: isRest
                              ? theme.colorScheme.onSurfaceVariant
                              : null)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    // Badges distincts : manquée (rouge) ≠ ignorée (gris).
                    if (status == 'MISSED')
                      _miniBadge('Manquée', LHColors.erreur,
                          icon: Icons.close),
                    if (status == 'SKIPPED')
                      _miniBadge('Ignorée', LHColors.neutre,
                          icon: Icons.remove_circle_outline),
                    if (status == 'DONE' && isQuantity && occ?.value != null)
                      _miniBadge(
                          '${qtyLabel(occ!.value)}${habit.unit != null ? ' ${habit.unit}' : ''}',
                          LHColors.succes,
                          icon: Icons.check),
                    _miniBadge(scheduleSummary(schedule),
                        isRest ? lhRest : theme.colorScheme.onSurfaceVariant,
                        size: 12),
                  ]),
                ]),
          ),
          // Menu par habitude
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'miss':
                  if (isRest) {
                    lhToast(context,
                        'Cette habitude n\'est pas programmée aujourd\'hui.');
                    break;
                  }
                  await db.setOccurrenceStatus(occ.id,
                      status: 'MISSED', value: null);
                  break;
                case 'skip':
                  if (isRest) {
                    lhToast(context,
                        'Cette habitude n\'est pas programmée aujourd\'hui.');
                    break;
                  }
                  await db.setOccurrenceStatus(occ.id,
                      status: 'SKIPPED', value: null);
                  break;
                case 'details':
                  if (context.mounted) context.push('/habit/${habit.id}');
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'miss', child: Text('Marquer manquée')),
              const PopupMenuItem(value: 'skip', child: Text('Ignorer')),
              const PopupMenuItem(value: 'details', child: Text('Détails')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _openQuantityDialog(
      BuildContext context, AppDatabase db, HabitOccurrence occ) async {
    final controller = TextEditingController(
        text: occ.value == null
            ? (habit.targetValue == null ? '' : qtyLabel(habit.targetValue))
            : qtyLabel(occ.value));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(habit.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Objectif : ${qtyLabel(habit.targetValue)}'
              '${habit.unit != null ? ' ${habit.unit}' : ''}',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Valeur du jour',
              suffixText: habit.unit ?? '',
            ),
          ),
        ]),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: LHColors.erreur),
            onPressed: () async {
              await db.setOccurrenceStatus(occ.id, status: 'MISSED', value: null);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Marquer manquée'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim().replaceAll(',', '.');
              final v = double.tryParse(raw);
              if (v == null || v < 0) {
                lhToast(ctx, 'Saisissez une valeur valide.');
                return;
              }
              await db.setOccurrenceStatus(occ.id, status: 'DONE', value: v);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Marquer fait'),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String label, Color color,
      {IconData? icon, double size = 13}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LHRadius.full),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: size, color: color),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: TextStyle(
                fontSize: size, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Bouton rond binaire (émeraude = fait) ou champ de valeur quantitatif.
class _TodayAction extends StatelessWidget {
  const _TodayAction({
    required this.habit,
    required this.color,
    required this.status,
    required this.value,
    required this.isRest,
    required this.onToggle,
    required this.onQuantityTap,
  });

  final Habit habit;
  final Color color;
  final String status;
  final double? value;
  final bool isRest;
  final VoidCallback onToggle;
  final VoidCallback onQuantityTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (habit.trackingType == 'QUANTITY') {
      final target = habit.targetValue;
      final shown = value != null
          ? qtyLabel(value)
          : (status == 'DONE' && target != null ? qtyLabel(target) : '—');
      return GestureDetector(
        onTap: onQuantityTap,
        child: Container(
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LHRadius.md),
            border: Border.all(
                color: isRest
                    ? theme.colorScheme.outline
                    : (status == 'DONE'
                        ? LHColors.succes
                        : color.withValues(alpha: 0.7)),
                width: 1.6),
            color: status == 'DONE'
                ? LHColors.succes.withValues(alpha: 0.10)
                : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(shown,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isRest
                        ? theme.colorScheme.onSurfaceVariant
                        : (status == 'DONE' ? LHColors.succes : null))),
            Text(
                '/ ${target != null ? qtyLabel(target) : '—'}'
                '${habit.unit != null ? ' ${habit.unit}' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
    }
    // Binaire : gros bouton rond.
    final done = status == 'DONE';
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: isRest
                  ? theme.colorScheme.outline.withValues(alpha: 0.7)
                  : done
                      ? LHColors.succes
                      : color,
              width: 2),
          color: done
              ? LHColors.succes
              : (isRest ? null : color.withValues(alpha: 0.08)),
        ),
        child: isRest
            ? Icon(Icons.bedtime_outlined,
                size: 22, color: lhRest.withValues(alpha: 0.9))
            : done
                ? const Icon(Icons.check, size: 26, color: Colors.white)
                : status == 'MISSED'
                    ? Icon(Icons.close,
                        size: 22, color: LHColors.erreur.withValues(alpha: 0.8))
                    : status == 'SKIPPED'
                        ? Icon(Icons.remove_circle_outline,
                            size: 22,
                            color: LHColors.neutre.withValues(alpha: 0.8))
                        : null,
      ),
    );
  }
}

// ———————— Vue « Semaine » ————————

class _WeekView extends StatelessWidget {
  const _WeekView(
      {required this.habits,
      required this.schedules,
      required this.occurrences});

  final List<Habit> habits;
  final List<HabitSchedule> schedules;
  final List<HabitOccurrence> occurrences;

  List<DateTime> get _days {
    final today = fmt.today();
    return [for (var i = 6; i >= 0; i--) fmt.addDays(today, -i)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (habits.isEmpty) {
      return const EmptyState(
          icon: Icons.view_week_outlined,
          message: 'Aucune habitude à afficher');
    }
    final days = _days;
    final byHabit = <String, List<HabitOccurrence>>{};
    for (final o in occurrences) {
      byHabit.putIfAbsent(o.habitId, () => []).add(o);
    }

    return Column(children: [
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24, top: 4),
          itemCount: habits.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _WeekHeader(days: days);
            final h = habits[i - 1];
            final sched = scheduleFor(schedules, h.id);
            final occs = byHabit[h.id] ?? const <HabitOccurrence>[];
            return _WeekRow(
                habit: h, schedule: sched, days: days, occurrences: occs);
          },
        ),
      ),
      // Légende des pastilles
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in ['DONE', 'MISSED', 'SKIPPED', 'REST', 'PENDING'])
              Row(mainAxisSize: MainAxisSize.min, children: [
                _StatusDot(status: s, size: 12),
                const SizedBox(width: 4),
                Text(occurrenceLabel(s),
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
              ]),
          ],
        ),
      ),
    ]);
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.days});

  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = fmt.today();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        const SizedBox(width: 96, child: Text('Habitude')),
        for (final d in days)
          Expanded(
            child: Column(children: [
              Text(
                fmt.weekdaysFr[d.weekday - 1],
                style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fmt.isSameDay(d, today)
                        ? LHColors.or
                        : theme.colorScheme.onSurfaceVariant),
              ),
              Text('${d.day}',
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
      ]),
    );
  }
}

class _WeekRow extends ConsumerWidget {
  const _WeekRow(
      {required this.habit,
      required this.schedule,
      required this.days,
      required this.occurrences});

  final Habit habit;
  final HabitSchedule? schedule;
  final List<DateTime> days;
  final List<HabitOccurrence> occurrences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final byKey = {for (final o in occurrences) o.dateKey: o};
    final color = hexColor(habit.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
          ]),
        ),
        for (final d in days)
          Expanded(
            child: Center(
              child: _WeekCell(
                status: byKey[fmt.dateKey(d)]?.status,
                scheduled: schedule != null && isScheduledOn(schedule, d),
                onTap: (byKey[fmt.dateKey(d)] == null || schedule == null)
                    ? null
                    : () => _cycle(context, db, byKey[fmt.dateKey(d)]!),
              ),
            ),
          ),
      ]),
    );
  }

  /// Cycle PENDING → DONE → MISSED → SKIPPED → PENDING (D08).
  void _cycle(BuildContext context, AppDatabase db, HabitOccurrence occ) {
    const next = {
      'PENDING': 'DONE',
      'DONE': 'MISSED',
      'MISSED': 'SKIPPED',
      'SKIPPED': 'PENDING',
      'REST': 'PENDING',
    };
    final to = next[occ.status] ?? 'PENDING';
    db.setOccurrenceStatus(occ.id, status: to, value: occ.value);
  }
}

class _WeekCell extends StatelessWidget {
  const _WeekCell({required this.status, required this.scheduled, this.onTap});

  final String? status;
  final bool scheduled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (status == null || !scheduled) {
      // Jour non programmé : repos (bleu clair), non interactif.
      if (!scheduled) {
        return const _StatusDot(status: 'REST', size: 26, dimmed: true);
      }
      return _StatusDot(status: 'PENDING', size: 26, onTap: onTap);
    }
    return _StatusDot(status: status!, size: 26, onTap: onTap);
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(
      {required this.status, required this.size, this.onTap, this.dimmed = false});

  final String status;
  final double size;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = occurrenceColor(status);
    final filled = status == 'DONE' ||
        status == 'MISSED' ||
        status == 'SKIPPED' ||
        status == 'REST';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? c.withValues(alpha: dimmed ? 0.45 : 1)
              : Colors.transparent,
          border: filled
              ? null
              : Border.all(
                  color: theme.colorScheme.outline, width: 1.6),
        ),
        child: status == 'DONE' && size >= 24
            ? Icon(Icons.check,
                size: size * 0.5, color: Colors.white)
            : null,
      ),
    );
  }
}

// ———————— Vue « Stats » ————————

class _StatsView extends StatelessWidget {
  const _StatsView(
      {required this.habits,
      required this.schedules,
      required this.occurrences});

  final List<Habit> habits;
  final List<HabitSchedule> schedules;
  final List<HabitOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    if (habits.isEmpty) {
      return const EmptyState(
          icon: Icons.insights_outlined,
          message: 'Aucune statistique pour l\'instant');
    }
    final byHabit = <String, List<HabitOccurrence>>{};
    for (final o in occurrences) {
      byHabit.putIfAbsent(o.habitId, () => []).add(o);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      itemCount: habits.length,
      itemBuilder: (context, i) {
        final h = habits[i];
        final sched = scheduleFor(schedules, h.id);
        final occs = byHabit[h.id] ?? const <HabitOccurrence>[];
        return _HabitStatCard(habit: h, schedule: sched, occurrences: occs);
      },
    );
  }
}

class _HabitStatCard extends StatelessWidget {
  const _HabitStatCard(
      {required this.habit, required this.schedule, required this.occurrences});

  final Habit habit;
  final HabitSchedule? schedule;
  final List<HabitOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hexColor(habit.colorHex);
    final streak = computeStreak(schedule, occurrences);
    final rate = computeRate30(schedule, occurrences);
    final rateLabel = rate == null
        ? '—'
        : '${(rate * 100).round()} %';

    // Mini-historique : 21 derniers jours (repos = bleu clair, contour = à faire).
    final today = fmt.today();
    final byKey = {for (final o in occurrences) o.dateKey: o};
    final history = <Widget>[];
    for (var i = 20; i >= 0; i--) {
      final d = fmt.addDays(today, -i);
      final scheduled = schedule != null && isScheduledOn(schedule, d);
      final o = byKey[fmt.dateKey(d)];
      String st;
      if (o != null) {
        st = o.status;
      } else {
        st = scheduled ? 'PENDING' : 'REST';
      }
      history.add(_StatusDot(status: st, size: 13));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: LHCard(
        accent: color.withValues(alpha: 0.85),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall),
            ),
            Text(scheduleSummary(schedule),
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: LHSpacing.md),
          Row(children: [
            Expanded(
              child: StatTile(
                label: 'Série actuelle',
                value: '$streak j',
                color: LHColors.or,
                icon: Icons.local_fire_department_outlined,
              ),
            ),
            Expanded(
              child: StatTile(
                label: 'Réussite (30 j)',
                value: rateLabel,
                color: rate == null ? null : LHColors.succes,
                icon: Icons.task_alt_outlined,
              ),
            ),
            Expanded(
              child: StatTile(
                label: 'Suivi',
                value: habit.trackingType == 'QUANTITY'
                    ? (habit.targetValue != null
                        ? '${qtyLabel(habit.targetValue)} ${habit.unit ?? ''}'
                        : '—')
                    : 'Binaire',
                icon: Icons.track_changes_outlined,
              ),
            ),
          ]),
          const SizedBox(height: LHSpacing.md),
          Wrap(spacing: 4, runSpacing: 4, children: history),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : DÉTAIL HABITUDE ═══════════════════════════

/// Édition complète d'une habitude — `/habit/:id`.
/// `id == 'new'` (depuis `/habit/new`) : mode création.
class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<HabitDetailScreen> createState() =>
      _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _unit = TextEditingController();
  final _target = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '2');

  bool _loaded = false;
  bool _notFound = false;
  bool _saving = false;

  String _trackingType = 'BINARY';
  String _colorHex = habitPalette.first;
  String _freq = 'DAILY';
  List<int> _weekdays = [1, 2, 3, 4, 5];
  String? _sinceKey; // préservé lors d'un changement de planification
  Habit? _existing;
  HabitSchedule? _existingSchedule;

  bool get _isNew => widget.id == 'new' || _existing == null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _unit.dispose();
    _target.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (widget.id == 'new') {
      _sinceKey = fmt.dateKey(fmt.today());
      if (mounted) setState(() {});
      return;
    }
    final db = ref.read(dbProvider);
    final h = await db.getHabit(widget.id);
    if (h == null) {
      _notFound = true;
      if (mounted) setState(() {});
      return;
    }
    _existing = h;
    _name.text = h.name;
    _description.text = h.description ?? '';
    _trackingType = h.trackingType;
    _unit.text = h.unit ?? '';
    _target.text = h.targetValue == null ? '' : qtyLabel(h.targetValue);
    _colorHex = h.colorHex;
    final schedules = await (db.select(db.habitSchedules)
          ..where((s) => s.habitId.equals(h.id)))
        .get();
    if (schedules.isNotEmpty) {
      schedules.sort((a, b) => b.sinceKey.compareTo(a.sinceKey));
      final s = schedules.first;
      _existingSchedule = s;
      _freq = s.freq;
      _sinceKey = s.sinceKey;
      _weekdays = decodeWeekdays(s.weekdaysJson);
      if (_weekdays.isEmpty) _weekdays = [1, 2, 3, 4, 5];
      _intervalCtrl.text = '${s.intervalDays ?? 2}';
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      lhToast(context, 'Le nom est obligatoire.');
      return;
    }
    if (_freq == 'WEEKLY' && _weekdays.isEmpty) {
      lhToast(context, 'Sélectionnez au moins un jour de semaine.');
      return;
    }
    final n = int.tryParse(_intervalCtrl.text.trim());
    if (_freq == 'INTERVAL' && (n == null || n < 1)) {
      lhToast(context, 'Indiquez un intervalle d\'au moins 1 jour.');
      return;
    }
    double? target;
    if (_trackingType == 'QUANTITY' && _target.text.trim().isNotEmpty) {
      target = double.tryParse(_target.text.trim().replaceAll(',', '.'));
      if (target == null || target < 0) {
        lhToast(context, 'Cible invalide.');
        return;
      }
    }

    setState(() => _saving = true);
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final id = _isNew ? 'habit_${now.microsecondsSinceEpoch}' : _existing!.id;
    final habit = Habit(
      id: id,
      spaceId: _isNew ? ref.read(activeSpaceIdProvider) : _existing!.spaceId,
      name: name,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      trackingType: _trackingType,
      unit: _trackingType == 'QUANTITY' && _unit.text.trim().isNotEmpty
          ? _unit.text.trim()
          : null,
      targetValue: target,
      colorHex: _colorHex,
      archivedAt: _existing?.archivedAt,
      createdAt: _existing?.createdAt ?? now,
    );
    await db.saveHabit(habit, isNew: _isNew);

    final schedule = HabitSchedule(
      id: '${id}_sched',
      habitId: id,
      freq: _freq,
      weekdaysJson: _freq == 'WEEKLY'
          ? jsonEncode(_weekdays..sort())
          : null,
      intervalDays: _freq == 'INTERVAL' ? (n ?? 2) : null,
      sinceKey: _sinceKey ?? fmt.dateKey(fmt.today()),
    );
    await db.upsertSchedule(schedule, isNew: _existingSchedule == null);

    // Génère immédiatement les occurrences du jour (impatience bienvenue).
    await ensureOccurrences(db, habit, schedule,
        fmt.dateKey(fmt.addDays(fmt.today(), -60)), fmt.dateKey(fmt.today()));

    if (!mounted) return;
    lhToast(context, 'Habitude enregistrée');
    context.pop();
  }

  Future<void> _archive() async {
    final ok = await lhConfirm(
      context,
      title: 'Archiver cette habitude ?',
      message:
          'Elle disparaît du suivi quotidien. L\'historique est conservé et l\'archivage reste réversible.',
      confirmLabel: 'Archiver',
    );
    if (!ok) return;
    await ref.read(dbProvider).archiveHabit(widget.id, true);
    if (!mounted) return;
    lhToast(context, 'Habitude archivée');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Habitude introuvable')),
        body: EmptyState(
          icon: Icons.search_off,
          message: 'Cette habitude n\'existe pas ou a été supprimée.',
          action: TextButton(
              onPressed: () => context.pop(), child: const Text('Retour')),
        ),
      );
    }
    final showHistory = !_isNew;
    final occurrencesAsync =
        showHistory ? ref.watch(habitOccurrencesProvider(widget.id)) : null;
    final occurrences = occurrencesAsync?.valueOrNull ?? const <HabitOccurrence>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nouvelle habitude' : 'Modifier l\'habitude'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Enregistrer')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        children: [
          TextField(
            controller: _name,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleMedium,
            decoration: const InputDecoration(
                hintText: 'Nom de l\'habitude (ex. Lire 20 minutes)',
                border: InputBorder.none),
          ),
          const Divider(),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description (facultative)'),
          ),
          const SizedBox(height: LHSpacing.lg),

          // —— Suivi ——
          LabeledField(
            label: 'Type de suivi',
            child: LhSegmented<String>(
              value: _trackingType,
              items: const {'BINARY': 'Binaire', 'QUANTITY': 'Quantitatif'},
              onChanged: (v) => setState(() => _trackingType = v),
            ),
          ),
          if (_trackingType == 'QUANTITY') ...[
            const SizedBox(height: LHSpacing.md),
            Row(children: [
              Expanded(
                child: LabeledField(
                  label: 'Unité',
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                        hintText: 'min, L, pages…'),
                  ),
                ),
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'Cible (facultative)',
                  child: TextField(
                    controller: _target,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(hintText: 'ex. 20'),
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: LHSpacing.lg),

          // —— Couleur ——
          LabeledField(
            label: 'Couleur',
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final hex in habitPalette)
                  GestureDetector(
                    onTap: () => setState(() => _colorHex = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hexColor(hex),
                        border: _colorHex == hex
                            ? Border.all(
                                color: theme.colorScheme.onSurface, width: 3)
                            : null,
                      ),
                      child: _colorHex == hex
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LHSpacing.lg),

          // —— Planification ——
          LabeledField(
            label: 'Planification',
            child: LhSegmented<String>(
              value: _freq,
              items: const {
                'DAILY': 'Quotidienne',
                'WEEKLY': 'Jours fixes',
                'INTERVAL': 'Intervalle',
              },
              onChanged: (v) => setState(() => _freq = v),
            ),
          ),
          if (_freq == 'WEEKLY')
            Padding(
              padding: const EdgeInsets.only(top: LHSpacing.md),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(dayNamesFr[d - 1]),
                      selected: _weekdays.contains(d),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _weekdays.add(d);
                        } else {
                          _weekdays.remove(d);
                        }
                      }),
                    ),
                ],
              ),
            ),
          if (_freq == 'INTERVAL')
            Padding(
              padding: const EdgeInsets.only(top: LHSpacing.md),
              child: Row(children: [
                const Text('Tous les'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('jours'),
              ]),
            ),
          const SizedBox(height: LHSpacing.xl),

          // —— Historique & stats (édition seulement) ——
          if (showHistory) ...[
            SectionHeader('Historique du mois', overline: 'Occurrences'),
            _MonthGrid(
              schedule: _existingSchedule,
              occurrences: occurrences,
            ),
            const SizedBox(height: LHSpacing.lg),
            _HabitStatCard(
              habit: _existing!,
              schedule: _existingSchedule,
              occurrences: occurrences,
            ),
            const SizedBox(height: LHSpacing.xl),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant),
              onPressed: _archive,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archiver cette habitude'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grille du mois courant : lignes de semaines L..D (D08).
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.schedule, required this.occurrences});

  final HabitSchedule? schedule;
  final List<HabitOccurrence> occurrences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final now = fmt.today();
    final monthStart = DateTime(now.year, now.month, 1);
    final gridStart = fmt.startOfWeek(monthStart);
    final byKey = {for (final o in occurrences) o.dateKey: o};

    return LHCard(
      child: Column(children: [
        Row(children: [
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Center(
                child: Text(fmt.weekdaysFr[d - 1],
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
        ]),
        for (var w = 0; w < 6; w++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(builder: (context) {
                    final d = fmt.addDays(gridStart, w * 7 + i);
                    final inMonth = d.month == now.month;
                    if (!inMonth) return const SizedBox(height: 44);
                    final dk = fmt.dateKey(d);
                    final isFuture = d.isAfter(now);
                    final isToday = fmt.isSameDay(d, now);
                    final occ = byKey[dk];
                    final scheduled =
                        schedule != null && isScheduledOn(schedule, d);
                    return Column(children: [
                      Text('${d.day}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: isToday
                                  ? LHColors.or
                                  : (isFuture
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.onSurfaceVariant),
                              fontWeight:
                                  isToday ? FontWeight.w800 : null)),
                      const SizedBox(height: 3),
                      _StatusDot(
                        status: occ?.status ??
                            (scheduled ? 'PENDING' : 'REST'),
                        size: 22,
                        dimmed: isFuture,
                        onTap: (occ == null || isFuture)
                            ? null
                            : () {
                                const next = {
                                  'PENDING': 'DONE',
                                  'DONE': 'MISSED',
                                  'MISSED': 'SKIPPED',
                                  'SKIPPED': 'PENDING',
                                  'REST': 'PENDING',
                                };
                                db.setOccurrenceStatus(occ.id,
                                    status: next[occ.status] ?? 'PENDING',
                                    value: occ.value);
                              },
                      ),
                    ]);
                  }),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ═══════════════════════════ ÉCRAN : ROUTINES ═══════════════════════════

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final routinesAsync = ref.watch(routinesProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Routines'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRoutineDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle routine'),
      ),
      body: routinesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (routines) {
          if (routines.isEmpty) {
            return EmptyState(
              icon: Icons.repeat_outlined,
              message: 'Aucune routine',
              hint:
                  'Une routine enchaîne des étapes et des habitudes existantes.',
              action: FilledButton.tonal(
                onPressed: () => _showRoutineDialog(context, ref),
                child: const Text('Nouvelle routine'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96, top: 4),
            itemCount: routines.length,
            itemBuilder: (context, i) =>
                _RoutineTile(routine: routines[i]),
          );
        },
      ),
    );
  }

  Future<void> _showRoutineDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    TimeOfDay? time = const TimeOfDay(hour: 7, minute: 0);
    var days = <int>[1, 2, 3, 4, 5];
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Nouvelle routine'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Nom (ex. Routine du matin)'),
              ),
              const SizedBox(height: LHSpacing.md),
              // Heure prévue
              InkWell(
                borderRadius: BorderRadius.circular(LHRadius.md),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: time ?? const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (picked != null) setDialog(() => time = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Heure prévue', icon: Icon(Icons.schedule)),
                  child: Text(time == null
                      ? 'Sans heure'
                      : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'),
                ),
              ),
              const SizedBox(height: LHSpacing.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Jours',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(dayNamesFr[d - 1]),
                      selected: days.contains(d),
                      onSelected: (sel) => setDialog(() {
                        if (sel) {
                          days.add(d);
                        } else {
                          days.remove(d);
                        }
                      }),
                    ),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  lhToast(ctx, 'Le nom est obligatoire.');
                  return;
                }
                final now = DateTime.now();
                final r = Routine(
                  id: 'routine_${now.microsecondsSinceEpoch}',
                  spaceId: spaceId,
                  name: name,
                  scheduledTime: time == null
                      ? null
                      : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
                  weekdaysJson: days.isEmpty ? null : jsonEncode(days..sort()),
                  createdAt: now,
                );
                await db.saveRoutine(r, isNew: true);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  lhToast(ctx, 'Routine créée');
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = decodeWeekdays(routine.weekdaysJson);
    final daysLabel = days.isEmpty
        ? 'Tous les jours'
        : [for (final d in days) dayNamesFr[d - 1]].join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LHCard(
        onTap: () => context.push('/routine/${routine.id}'),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LHColors.or.withValues(alpha: 0.14),
              border: Border.all(color: LHColors.or.withValues(alpha: 0.55)),
            ),
            child: const Icon(Icons.repeat, color: LHColors.or, size: 22),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(routine.name,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    '${routine.scheduledTime != null ? '${routine.scheduledTime} · ' : ''}$daysLabel',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
          ),
          const Icon(Icons.chevron_right,
              color: LHColors.neutre),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : DÉTAIL ROUTINE ═══════════════════════════

class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  bool _loaded = false;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final db = ref.read(dbProvider);
    final r = await db.getRoutine(widget.id);
    if (r == null) {
      _notFound = true;
      if (mounted) setState(() {});
      return;
    }
    // Occurrence du jour créée paresseusement (exécution suivie par doneCount).
    await db.ensureRoutineOccurrence(r.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Routine introuvable')),
        body: EmptyState(
          icon: Icons.search_off,
          message: 'Cette routine n\'existe pas ou a été supprimée.',
          action: TextButton(
              onPressed: () => context.pop(), child: const Text('Retour')),
        ),
      );
    }
    final routineAsync = ref.watch(routineProvider(widget.id));
    final routine = routineAsync.valueOrNull;
    if (routine == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Routine')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final spaceId = ref.watch(activeSpaceIdProvider);
    final habitsAsync = ref.watch(habitsProvider(spaceId));
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];

    return Scaffold(
      appBar: AppBar(title: Text(routine.name)),
      body: ListView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        children: [
          // —— Déroulé (édition des étapes) ——
          SectionHeader('Déroulé', overline: 'Étapes ordonnées'),
          _StepsCard(routine: routine, habits: habits),
          const SizedBox(height: LHSpacing.lg),

          // —— Exécution du jour ——
          SectionHeader('Exécution du jour', overline: routine.scheduledTime ?? 'Sans heure'),
          _TodayExecutionCard(routine: routine, habits: habits),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

/// Édition des étapes : référence aux habitudes SANS dupliquer leur
/// historique (CDC D08 §13.2) — un pas lié affiche l'habitude et y renvoie.
class _StepsCard extends ConsumerWidget {
  const _StepsCard({required this.routine, required this.habits});

  final Routine routine;
  final List<Habit> habits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final stepsAsync = ref.watch(routineStepsProvider(routine.id));
    final steps = stepsAsync.valueOrNull ?? const <RoutineStep>[];

    return LHCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (steps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Aucune étape. Ajoutez une étape libre ou liez une habitude.'),
          ),
        for (final (i, s) in steps.indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: s.habitId != null &&
                    habits.any((h) => h.id == s.habitId)
                ? () => context.push('/habit/${s.habitId}')
                : null,
            leading: s.habitId != null
                ? const Icon(Icons.link, color: LHColors.or, size: 20)
                : Icon(Icons.radio_button_unchecked,
                    size: 18, color: Theme.of(context).colorScheme.outline),
            title: Text(
              _stepTitle(s, habits),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: s.habitId != null ? FontWeight.w600 : null),
            ),
            subtitle: s.habitId != null
                ? const Text('Habitude liée',
                    style: TextStyle(fontSize: 11, color: LHColors.or))
                : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0
                    ? null
                    : () => _move(db, steps, i, -1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: i == steps.length - 1
                    ? null
                    : () => _move(db, steps, i, 1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close,
                    size: 18, color: LHColors.erreur),
                onPressed: () async {
                  await db.deleteRoutineStep(s.id);
                },
              ),
            ]),
          ),
        const Divider(height: 1),
        OutlinedButton.icon(
          onPressed: () => _addStepSheet(context, ref, db),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter une étape'),
        ),
      ]),
    );
  }

  String _stepTitle(RoutineStep s, List<Habit> habits) {
    if (s.habitId != null) {
      final h = habits.where((x) => x.id == s.habitId).firstOrNull;
      if (h != null) return h.name;
    }
    return s.label;
  }

  void _move(AppDatabase db, List<RoutineStep> steps, int index, int delta) {
    final j = index + delta;
    if (j < 0 || j >= steps.length) return;
    final ordered = [...steps];
    final tmp = ordered[index];
    ordered[index] = ordered[j];
    ordered[j] = tmp;
    db.writeStepPositions(ordered);
  }

  Future<void> _addStepSheet(
      BuildContext context, WidgetRef ref, AppDatabase db) async {
    final labelCtrl = TextEditingController();
    final spaceId = ref.read(activeSpaceIdProvider);
    final habits = await db.watchHabits(spaceId).first;
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(LHSpacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ajouter une étape',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
              ),
              // Étape libre
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: LHSpacing.lg),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: labelCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText: 'Étape libre (ex. Douche)',
                          prefixIcon: Icon(Icons.edit_outlined)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajouter l\'étape libre',
                    icon: const Icon(Icons.add_circle),
                    onPressed: () async {
                      final v = labelCtrl.text.trim();
                      if (v.isEmpty) {
                        lhToast(ctx, 'Saisissez un libellé.');
                        return;
                      }
                      await db.addRoutineStep(routine.id, label: v);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ]),
              ),
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Lier une habitude',
                      style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ),
              if (habits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucune habitude active à lier.'),
                ),
              for (final h in habits)
                ListTile(
                  dense: true,
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: hexColor(h.colorHex), shape: BoxShape.circle),
                  ),
                  title: Text(h.name),
                  subtitle: Text(
                      h.trackingType == 'QUANTITY'
                          ? 'Suivi quantitatif'
                          : 'Suivi binaire',
                      style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.link, size: 18, color: LHColors.or),
                  onTap: () async {
                    await db.addRoutineStep(routine.id,
                        habitId: h.id, label: h.name);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Exécution du jour : RoutineOccurrence avec cases à cocher par étape.
/// Modèle séquentiel persisté via doneCount (cocher l'étape N valide 1..N).
class _TodayExecutionCard extends ConsumerWidget {
  const _TodayExecutionCard({required this.routine, required this.habits});

  final Routine routine;
  final List<Habit> habits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final stepsAsync = ref.watch(routineStepsProvider(routine.id));
    final steps = stepsAsync.valueOrNull ?? const <RoutineStep>[];
    final occAsync = ref.watch(todayRoutineOccurrenceProvider(routine.id));
    final occ = occAsync.valueOrNull;

    if (steps.isEmpty) {
      return const LHCard(
          child: Text(
              'Ajoutez des étapes pour suivre l\'exécution de la routine.'));
    }
    final done = occ?.doneCount ?? 0;
    final total = steps.length;
    final complete = done >= total;

    return LHCard(
      accent: complete ? LHColors.succes : LHColors.or,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(
            progress: total == 0 ? 0 : done / total,
            size: 40,
            stroke: 3.5,
            color: complete ? LHColors.succes : LHColors.or,
            child: Text('$done/$total',
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child: Text(
              complete ? 'Routine terminée aujourd\'hui 🎉' : 'En cours…',
              style: theme.textTheme.titleSmall?.copyWith(
                  color: complete ? LHColors.succes : null),
            ),
          ),
        ]),
        const SizedBox(height: LHSpacing.sm),
        for (final (i, s) in steps.indexed)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: i < done,
            activeColor: LHColors.succes,
            title: Text(
              s.habitId != null
                  ? (habits
                          .where((h) => h.id == s.habitId)
                          .firstOrNull
                          ?.name ??
                      s.label)
                  : s.label,
              style: TextStyle(
                  fontSize: 14,
                  decoration: i < done ? TextDecoration.lineThrough : null),
            ),
            secondary: s.habitId != null
                ? IconButton(
                    tooltip: 'Voir l\'habitude',
                    icon: const Icon(Icons.link,
                        size: 18, color: LHColors.or),
                    onPressed: () => context.push('/habit/${s.habitId}'),
                  )
                : null,
            onChanged: (v) {
              final id = occ?.id;
              if (id == null) return;
              // Case N : séquentiel — cocher N valide les étapes 1..N.
              db.setRoutineDoneCount(id, v! ? i + 1 : i);
            },
          ),
        const SizedBox(height: LHSpacing.sm),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor:
                      complete ? null : LHColors.succes),
              onPressed: occ == null
                  ? null
                  : () => db.setRoutineDoneCount(occ.id, total),
              icon: const Icon(Icons.done_all),
              label: const Text('Tout terminer'),
            ),
          ),
          if (done > 0) ...[
            const SizedBox(width: LHSpacing.md),
            TextButton(
              onPressed: occ == null
                  ? null
                  : () => db.setRoutineDoneCount(occ.id, 0),
              child: const Text('Réinitialiser'),
            ),
          ],
        ]),
      ]),
    );
  }
}

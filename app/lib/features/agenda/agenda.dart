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

// ═══════════════════════════ LABELS MÉTIER (D04) ═══════════════════════════

String eventStatusLabel(String s) {
  switch (s) {
    case 'SCHEDULED':
      return 'Planifié';
    case 'COMPLETED':
      return 'Terminé';
    case 'CANCELLED':
      return 'Annulé';
    case 'RESCHEDULED':
      return 'Reporté';
    default:
      return s;
  }
}

Color eventStatusColor(String s) {
  switch (s) {
    case 'SCHEDULED':
      return LHColors.info;
    case 'COMPLETED':
      return LHColors.tacheTerminee;
    case 'CANCELLED':
      return LHColors.tacheAnnulee;
    default:
      return LHColors.tacheAttente;
  }
}

int _minutes(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + (parts.length > 1 ? int.parse(parts[1]) : 0);
}

Color hexToColor(String hex, {Color fallback = const Color(0xFF3B82F6)}) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse('FF$h', radix: 16);
  return v == null ? fallback : Color(v);
}

// ═══════════════════════════ DONNÉES DÉRIVÉES ═══════════════════════════

/// Occurrence concrète d'un événement (série ou instance unique).
class AgendaEntry {
  AgendaEntry({required this.event, required this.date});
  final CalendarEvent event;
  final DateTime date;

  String get key => '${event.id}_${fmt.dateKey(date)}';
  bool get isAllDay => event.allDay || event.startTime == null;
  int get startMinutes => _minutes(event.startTime ?? '00:00');
  int get endMinutes => _minutes(event.endTime ?? '23:59');
}

/// Étend les événements (séries + instances) sur une période [from, to],
/// en excluant les occurrences annulées via les exceptions (D04 §9.1-3).
List<AgendaEntry> expandOccurrences(
  List<CalendarEvent> events,
  Map<String, RecurrenceRule> rules,
  List<EventException> exceptions,
  DateTime from,
  DateTime to,
) {
  final cancelled = {
    for (final e in exceptions)
      if (e.cancelled) '${e.eventId}_${e.dateKey}'
  };
  final result = <AgendaEntry>[];

  for (final e in events) {
    final start = fmt.parseKey(e.startDate);
    final end = fmt.parseKey(e.endDate);
    final rule = e.recurrenceRuleId == null ? null : rules[e.recurrenceRuleId];

    if (rule == null) {
      // Instance unique : incluse si elle touche la fenêtre.
      if (!(end.isBefore(from) || start.isAfter(to))) {
        result.add(AgendaEntry(event: e, date: start));
      }
      continue;
    }

    // Série : parcourt les jours de la fenêtre élargie au début de la série.
    final windowStart = start.isBefore(from) ? from : start;
    var probe = windowStart;
    var guard = 0;
    while (!probe.isAfter(to) && guard < 400) {
      guard++;
      if (!start.isAfter(probe) && _matchesRule(rule, start, probe)) {
        final k = '${e.id}_${fmt.dateKey(probe)}';
        if (!cancelled.contains(k)) {
          result.add(AgendaEntry(event: e, date: probe));
        }
      }
      probe = fmt.addDays(probe, 1);
    }
  }

  result.sort((a, b) {
    final at = a.isAllDay ? -1 : a.startMinutes;
    final bt = b.isAllDay ? -1 : b.startMinutes;
    return at.compareTo(bt);
  });
  return result;
}

bool _matchesRule(RecurrenceRule rule, DateTime seriesStart, DateTime d) {
  if (d.isBefore(seriesStart)) return false;
  switch (rule.freq) {
    case 'DAILY':
      return fmt.daysBetween(seriesStart, d) % rule.interval == 0;
    case 'WEEKLY':
      final days = fmt.daysBetween(fmt.startOfWeek(seriesStart), fmt.startOfWeek(d)) ~/ 7;
      if (days % rule.interval != 0) return false;
      if (rule.byWeekday == null) return d.weekday == seriesStart.weekday;
      final wd = (jsonDecode(rule.byWeekday!) as List).cast<int>();
      return wd.contains(d.weekday);
    case 'MONTHLY':
      if (d.day != seriesStart.day) return false;
      var months = (d.year - seriesStart.year) * 12 + (d.month - seriesStart.month);
      return months % rule.interval == 0;
    case 'YEARLY':
      if (d.day != seriesStart.day || d.month != seriesStart.month) return false;
      return (d.year - seriesStart.year) % rule.interval == 0;
    default:
      return false;
  }
}

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension AgendaQueries on AppDatabase {
  Stream<List<CalendarEvent>> watchEvents(String spaceId) {
    return (select(calendarEvents)
          ..where((e) => e.spaceId.equals(spaceId))
          ..orderBy([(e) => OrderingTerm(expression: e.startDate)]))
        .watch();
  }

  Stream<CalendarEvent> watchEvent(String id) =>
      (select(calendarEvents)..where((e) => e.id.equals(id))).watchSingle();

  Stream<List<Calendar>> watchCalendars(String spaceId) =>
      (select(calendars)..where((c) => c.spaceId.equals(spaceId))).watch();

  Stream<List<EventParticipant>> watchParticipants(String eventId) =>
      (select(eventParticipants)..where((p) => p.eventId.equals(eventId)))
          .watch();

  Stream<List<EventException>> watchExceptionsForSpace(String spaceId) {
    final query = select(eventExceptions).join([
      innerJoin(calendarEvents, calendarEvents.id.equalsExp(eventExceptions.eventId))
    ])
      ..where(calendarEvents.spaceId.equals(spaceId));
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(eventExceptions)).toList());
  }

  Stream<Map<String, RecurrenceRule>> watchRuleMap() {
    return (select(recurrenceRules)).watch().map(
        (list) => {for (final r in list) r.id: r});
  }

  Future<CalendarEvent?> getEvent(String id) =>
      (select(calendarEvents)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Crée ou renomme un calendrier (gestion D04, journalisé pour la sync).
  Future<void> saveCalendar(Calendar c, {required bool isNew}) async {
    await into(calendars).insert(c, mode: InsertMode.insertOrReplace);
    logOp('Calendar', c.id, isNew ? 'CREATE' : 'UPDATE',
        {'name': c.name, 'color': c.colorHex});
  }

  /// Bascule la visibilité d'un calendrier dans les vues agenda.
  Future<void> setCalendarVisibility(String id, bool visible) async {
    await (update(calendars)..where((c) => c.id.equals(id)))
        .write(CalendarsCompanion(isVisible: Value(visible)));
    logOp('Calendar', id, 'UPDATE', {'isVisible': visible});
  }

  Future<RecurrenceRule?> getRule(String? id) async {
    if (id == null) return null;
    return await (select(recurrenceRules)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> saveEvent(CalendarEvent e) async {
    await into(calendarEvents).insert(e, mode: InsertMode.insertOrReplace);
    logOp('CalendarEvent', e.id, 'CREATE_OR_UPDATE',
        {'title': e.title, 'start': e.startDate});
  }

  /// Report : conserve l'historique via `originalStart` (D04 §9.1-2).
  Future<void> rescheduleEvent(
      CalendarEvent e, String newDate, String? newTime) async {
    await (update(calendarEvents)..where((x) => x.id.equals(e.id)))
        .write(CalendarEventsCompanion(
      originalStart: Value(e.originalStart ?? e.startDate),
      startDate: Value(newDate),
      startTime: Value(newTime),
      status: const Value('SCHEDULED'),
      updatedAt: Value(DateTime.now()),
    ));
    logOp('CalendarEvent', e.id, 'UPDATE', {'rescheduledTo': newDate});
  }

  Future<void> setEventStatus(String id, String status) async {
    await (update(calendarEvents)..where((x) => x.id.equals(id)))
        .write(CalendarEventsCompanion(
            status: Value(status), updatedAt: Value(DateTime.now())));
    logOp('CalendarEvent', id, 'UPDATE', {'status': status});
  }

  Future<void> deleteEvent(CalendarEvent e) async {
    await (delete(eventParticipants)..where((p) => p.eventId.equals(e.id))).go();
    final exceptions = await (select(eventExceptions)
          ..where((x) => x.eventId.equals(e.id)))
        .get();
    await (delete(eventExceptions)..where((x) => x.eventId.equals(e.id))).go();
    for (final x in exceptions) {
      logOp('EventException', x.id, 'DELETE', {});
    }
    await (delete(calendarEvents)..where((x) => x.id.equals(e.id))).go();
    logOp('CalendarEvent', e.id, 'DELETE', {'title': e.title});
  }

  Future<void> addParticipant(String eventId, String name, String status) async {
    await into(eventParticipants).insert(EventParticipant(
        id: '${eventId}_$name', eventId: eventId, name: name, status: status));
  }

  Future<void> removeParticipant(String id) =>
      (delete(eventParticipants)..where((p) => p.id.equals(id))).go();

  /// Annule une occurrence d'une série (exception) sans toucher la série.
  Future<void> cancelOccurrence(String eventId, String dateKey) async {
    await into(eventExceptions).insert(EventException(
        id: '${eventId}_$dateKey',
        eventId: eventId,
        dateKey: dateKey,
        cancelled: true));
    logOp('EventException', '${eventId}_$dateKey', 'CREATE',
        {'cancelled': dateKey});
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final calendarsProvider = StreamProvider.family<List<Calendar>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchCalendars(spaceId));

final eventsProvider = StreamProvider.family<List<CalendarEvent>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchEvents(spaceId));

final eventExceptionsProvider =
    StreamProvider.family<List<EventException>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchExceptionsForSpace(spaceId));

final ruleMapProvider = StreamProvider<Map<String, RecurrenceRule>>(
    (ref) => ref.watch(dbProvider).watchRuleMap());

final eventProvider = StreamProvider.family<CalendarEvent?, String>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.calendarEvents)..where((e) => e.id.equals(id)))
      .watchSingleOrNull();
});

final participantsProvider = StreamProvider.family<List<EventParticipant>, String>(
    (ref, id) => ref.watch(dbProvider).watchParticipants(id));

// ═══════════════════════════ ÉCRAN : AGENDA ═══════════════════════════

enum _AgendaView { day, week, month }

/// Agenda — vues jour / semaine / mois (D04 §9.2).
/// Les chevauchements sont signalés mais ne bloquent pas (D04 §9.1-8).
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  _AgendaView _view = _AgendaView.month;
  DateTime _selected = fmt.today();
  DateTime _month = fmt.today();

  @override
  Widget build(BuildContext context) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final eventsAsync = ref.watch(eventsProvider(spaceId));
    final exceptionsAsync = ref.watch(eventExceptionsProvider(spaceId));
    final rulesAsync = ref.watch(ruleMapProvider);
    final calendars = ref.watch(calendarsProvider(spaceId)).valueOrNull ?? [];

    return Scaffold(
      appBar: LhAppBar(title: 'Agenda'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/event/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel événement'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: LhSegmented<_AgendaView>(
            value: _view,
            items: const {
              _AgendaView.day: 'Jour',
              _AgendaView.week: 'Semaine',
              _AgendaView.month: 'Mois',
            },
            onChanged: (v) => setState(() => _view = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openCalendarManager(context, spaceId),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Calendriers'),
            ),
          ),
        ),
        Expanded(
          child: eventsAsync.maybeWhen(
            loading: () => const Center(child: CircularProgressIndicator()),
            orElse: () {
              final exceptions = exceptionsAsync.valueOrNull ?? [];
              final rules = rulesAsync.valueOrNull ?? {};
              // Les calendriers masqués n'apparaissent pas dans les vues
              // (les événements orphelins restent visibles).
              final hidden = {
                for (final c in calendars)
                  if (!c.isVisible) c.id
              };
              final visibleEvents = (eventsAsync.value ?? [])
                  .where((e) => !hidden.contains(e.calendarId))
                  .toList();
              final entries = expandOccurrences(
                  visibleEvents, rules, exceptions, _rangeFrom, _rangeTo);
              return _buildBody(entries);
            },
          ),
        ),
      ]),
    );
  }

  /// Feuille de gestion des calendriers : créer, renommer, masquer.
  Future<void> _openCalendarManager(BuildContext context, String spaceId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CalendarManagerSheet(spaceId: spaceId),
    );
  }

  (DateTime, DateTime) get _range {
    switch (_view) {
      case _AgendaView.day:
        return (_selected, _selected);
      case _AgendaView.week:
        final s = fmt.startOfWeek(_selected);
        return (s, fmt.addDays(s, 6));
      case _AgendaView.month:
        return (DateTime(_month.year, _month.month, 1),
            DateTime(_month.year, _month.month + 1, 0));
    }
  }

  DateTime get _rangeFrom => _range.$1;
  DateTime get _rangeTo => _range.$2;

  Widget _buildBody(List<AgendaEntry> entries) {
    switch (_view) {
      case _AgendaView.day:
        return _dayList(entries, _selected);
      case _AgendaView.week:
        return _weekView(entries);
      case _AgendaView.month:
        return _monthView(entries);
    }
  }

  Widget _dayList(List<AgendaEntry> entries, DateTime day) {
    final dayEntries = entries.where((e) => fmt.isSameDay(e.date, day)).toList();
    final overlaps = _findOverlaps(dayEntries);
    if (dayEntries.isEmpty) {
      return EmptyState(
        illustration: 'assets/illustrations/agenda.png',
        icon: Icons.event_available,
        message: 'Rien de prévu ${fmt.isSameDay(day, fmt.today()) ? "aujourd'hui" : 'ce jour-là'}',
        hint: 'Profitez-en — ou planifiez quelque chose.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96, top: 8),
      itemCount: dayEntries.length,
      itemBuilder: (context, i) => _EventTile(
          entry: dayEntries[i], hasOverlap: overlaps.contains(dayEntries[i].key)),
    );
  }

  Widget _weekView(List<AgendaEntry> entries) {
    final start = fmt.startOfWeek(_selected);
    final days = List.generate(7, (i) => fmt.addDays(start, i));
    return Column(children: [
      SizedBox(
        height: 68,
        child: Row(children: [
          for (final d in days)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _selected = d;
                  _view = _AgendaView.day;
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  decoration: BoxDecoration(
                    color: fmt.isSameDay(d, fmt.today())
                        ? LHColors.or.withValues(alpha: 0.15)
                        : null,
                    borderRadius: BorderRadius.circular(LHRadius.md),
                    border: fmt.isSameDay(d, _selected)
                        ? Border.all(color: LHColors.or)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(fmt.weekdaysFr[d.weekday - 1],
                          style: const TextStyle(fontSize: 11)),
                      Text('${d.day}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final d in days)
              ..._daySection(entries, d),
          ],
        ),
      ),
    ]);
  }

  List<Widget> _daySection(List<AgendaEntry> entries, DateTime d) {
    final dayEntries = entries.where((e) => fmt.isSameDay(e.date, d)).toList();
    if (dayEntries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        child: Text(fmt.humanDate(d),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
      ...dayEntries.map((e) => _EventTile(entry: e, hasOverlap: false)),
    ];
  }

  Widget _monthView(List<AgendaEntry> entries) {
    final theme = Theme.of(context);
    final cells = fmt.monthGrid(_month);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            onPressed: () =>
                setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
            icon: const Icon(Icons.chevron_left)),
        TextButton(
          onPressed: () => setState(() {
            _month = fmt.today();
            _selected = fmt.today();
          }),
          child: Text(fmt.formatMonthYear(_month),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        IconButton(
            onPressed: () =>
                setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final w in fmt.weekdaysFr)
            Expanded(
                child: Center(
                    child: Text(w,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)))),
        ]),
      ),
      SizedBox(
        height: 300,
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: [
            for (final d in cells)
              GestureDetector(
                onTap: () => setState(() => _selected = d),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: fmt.isSameDay(d, _selected)
                        ? LHColors.or.withValues(alpha: 0.18)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${d.day}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: fmt.isSameDay(d, fmt.today())
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: d.month != _month.month
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null)),
                      if (entries.any((e) => fmt.isSameDay(e.date, d)))
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(top: 1),
                          decoration: const BoxDecoration(
                              color: LHColors.or, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(child: _dayList(entries, _selected)),
    ]);
  }

  Set<String> _findOverlaps(List<AgendaEntry> day) {
    final timed = day.where((e) => !e.isAllDay).toList();
    final result = <String>{};
    for (var i = 0; i < timed.length; i++) {
      for (var j = i + 1; j < timed.length; j++) {
        final a = timed[i], b = timed[j];
        if (a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes) {
          result.add(a.key);
          result.add(b.key);
        }
      }
    }
    return result;
  }
}

// ═══════════════════════════ VIGNETTE ÉVÉNEMENT ═══════════════════════════

/// Feuille « Calendriers » : créer, renommer et masquer les calendriers
/// de l'espace actif (D04). Chaque mutation est journalisée (sync).
class _CalendarManagerSheet extends ConsumerWidget {
  const _CalendarManagerSheet({required this.spaceId});

  final String spaceId;

  static const _presetColors = [
    '#FFB400', // or
    '#3B82F6', // bleu
    '#22C55E', // émeraude
    '#FF7A00', // orange
    '#8B5CF6', // violet
  ];

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final nameCtrl = TextEditingController();
    var color = _presetColors.first;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau calendrier'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Nom, ex. : Sport'),
          ),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (ctx, setInner) => Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final c in _presetColors)
                  GestureDetector(
                    onTap: () => setInner(() => color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: hexToColor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c
                              ? Theme.of(ctx).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final id = 'cal_${DateTime.now().microsecondsSinceEpoch}';
              await db.saveCalendar(
                Calendar(
                    id: id,
                    spaceId: spaceId,
                    name: name,
                    colorHex: color,
                    isVisible: true),
                isNew: true,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDialog(
      BuildContext context, WidgetRef ref, Calendar c) async {
    final db = ref.read(dbProvider);
    final nameCtrl = TextEditingController(text: c.name);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le calendrier'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await db.saveCalendar(
                Calendar(
                    id: c.id,
                    spaceId: c.spaceId,
                    name: name,
                    colorHex: c.colorHex,
                    isVisible: c.isVisible),
                isNew: false,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final calendarsAsync = ref.watch(calendarsProvider(spaceId));
    final calendars = calendarsAsync.valueOrNull ?? [];
    final db = ref.read(dbProvider);

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            Expanded(
              child: Text('Calendriers',
                  style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Nouveau calendrier',
              icon: const Icon(Icons.add),
              onPressed: () => _createDialog(context, ref),
            ),
          ]),
        ),
        const Divider(height: 1),
        if (calendars.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Aucun calendrier dans cet espace.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final c in calendars)
          ListTile(
            leading: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: hexToColor(c.colorHex),
                shape: BoxShape.circle,
              ),
            ),
            title: Text(c.name),
            subtitle: Text(c.isVisible ? 'Visible — appuyez pour renommer'
                : 'Masqué — appuyez pour renommer',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            trailing: Switch(
              value: c.isVisible,
              onChanged: (v) => db.setCalendarVisibility(c.id, v),
            ),
            onTap: () => _renameDialog(context, ref, c),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.entry, required this.hasOverlap});

  final AgendaEntry entry;
  final bool hasOverlap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = entry.event;
    final spaceId = ref.watch(activeSpaceIdProvider);
    final calendars =
        ref.watch(calendarsProvider(spaceId)).valueOrNull ?? <Calendar>[];
    final color = calendars
            .where((c) => c.id == e.calendarId)
            .firstOrNull
            ?.colorHex ??
        '#3B82F6';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: LHCard(
        onTap: () => context.push('/event/${e.id}'),
        accent: e.status == 'CANCELLED' ? LHColors.neutre : hexToColor(color),
        child: Row(children: [
          if (entry.isAllDay)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.schedule, size: 18, color: LHColors.neutre),
            )
          else
            SizedBox(
              width: 48,
              child: Column(children: [
                Text(e.startTime ?? '',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(e.endTime ?? '',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          decoration: e.status == 'CANCELLED'
                              ? TextDecoration.lineThrough
                              : null)),
                  const SizedBox(height: 2),
                  Wrap(spacing: 6, runSpacing: 3, children: [
                    if (e.location != null)
                      _meta(theme, Icons.place_outlined, e.location!),
                    if (e.recurrenceRuleId != null)
                      _meta(theme, Icons.repeat, 'Récurrent'),
                    if (hasOverlap)
                      _meta(theme, Icons.warning_amber_rounded, 'Chevauchement',
                          color: LHColors.alerte),
                    if (e.status != 'SCHEDULED')
                      StatusChip(
                          label: eventStatusLabel(e.status),
                          color: eventStatusColor(e.status),
                          small: true),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text, {Color? color}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color ?? LHColors.neutre),
      const SizedBox(width: 3),
      Text(text,
          style: TextStyle(
              fontSize: 12,
              color: color ?? theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

// ═══════════════════════════ ÉCRAN : ÉDITION ═══════════════════════════

/// Création / édition d'événement — D04 : invitations, récurrence,
/// journée entière (date de fin exclusive), report avec historique.
class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _participantCtrl = TextEditingController();

  String? _calendarId;
  bool _allDay = false;
  String _startDate = '';
  String _startTime = '09:00';
  String _endDate = '';
  String _endTime = '10:00';
  String _status = 'SCHEDULED';
  String? _recurrenceFreq;
  List<int> _recurrenceDays = [DateTime.monday];
  final Map<String, String> _participants = {}; // nom -> statut
  bool _loaded = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _participantCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final db = ref.read(dbProvider);
    final today = fmt.dateKey(fmt.today());

    if (widget.id != null) {
      final e = await db.getEvent(widget.id!);
      if (e != null) {
        _title.text = e.title;
        _description.text = e.description ?? '';
        _location.text = e.location ?? '';
        _calendarId = e.calendarId;
        _allDay = e.allDay;
        _startDate = e.startDate;
        _startTime = e.startTime ?? '09:00';
        _endDate = e.endDate;
        _endTime = e.endTime ?? '10:00';
        _status = e.status;
        if (e.recurrenceRuleId != null) {
          final rule = await db.getRule(e.recurrenceRuleId!);
          if (rule != null) {
            _recurrenceFreq = rule.freq;
            if (rule.byWeekday != null) {
              _recurrenceDays = (jsonDecode(rule.byWeekday!) as List).cast<int>();
            }
          }
        }
        final parts = await db.watchParticipants(e.id).first;
        for (final p in parts) {
          _participants[p.name] = p.status;
        }
      }
    } else {
      _startDate = today;
      _endDate = today;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDate(bool isEnd) async {
    final current = fmt.parseKey(isEnd ? _endDate : _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() {
        if (isEnd) {
          // Journée entière : date de fin exclusive (D04 §9.2) — l'UI demande
          // le dernier jour inclus et stocke la borne exclue.
          _endDate = _allDay
              ? fmt.dateKey(fmt.addDays(picked, 1))
              : fmt.dateKey(picked);
          if (!_allDay && _endDate.compareTo(_startDate) < 0) {
            _endDate = _startDate;
          }
        } else {
          _startDate = fmt.dateKey(picked);
          if (_endDate.isEmpty || _endDate.compareTo(_startDate) < 0) {
            _endDate = _startDate;
          }
        }
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = fmt.parseKey(_startDate)
        .add(Duration(minutes: _minutes(isStart ? _startTime : _endTime)));
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (picked != null) {
      setState(() {
        final value =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        if (isStart) {
          _startTime = value;
        } else {
          _endTime = value;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      lhToast(context, 'Le titre est obligatoire.');
      return;
    }
    if (_calendarId == null) {
      lhToast(context, 'Choisissez un calendrier.');
      return;
    }
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final id = widget.id ?? 'event_${now.microsecondsSinceEpoch}';

    String? ruleId;
    if (_recurrenceFreq != null) {
      ruleId = 'erule_${id}_${_recurrenceFreq}';
      await db.into(db.recurrenceRules).insert(
          RecurrenceRule(
              id: ruleId,
              freq: _recurrenceFreq!,
              interval: 1,
              byWeekday: _recurrenceFreq == 'WEEKLY'
                  ? jsonEncode(_recurrenceDays)
                  : null),
          mode: InsertMode.insertOrReplace);
      db.logOp('RecurrenceRule', ruleId, 'CREATE_OR_UPDATE',
          {'freq': _recurrenceFreq});
    }

    final existing = await db.getEvent(id);
    final event = CalendarEvent(
      id: id,
      spaceId: existing?.spaceId ?? ref.read(activeSpaceIdProvider),
      calendarId: _calendarId!,
      title: _title.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      allDay: _allDay,
      startDate: _startDate,
      startTime: _allDay ? null : _startTime,
      endDate: _endDate.isEmpty ? _startDate : _endDate,
      endTime: _allDay ? null : _endTime,
      status: _status,
      originalStart: existing?.originalStart,
      recurrenceRuleId: ruleId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveEvent(event);

    // Participants (invitations dès le MVP — D04 §9.1-4)
    final current = await db.watchParticipants(id).first;
    for (final p in current) {
      if (!_participants.containsKey(p.name)) await db.removeParticipant(p.id);
    }
    for (final entry in _participants.entries) {
      final existingStatus = current
          .where((p) => p.name == entry.key)
          .firstOrNull
          ?.status;
      if (existingStatus != entry.value) {
        if (existingStatus != null) await db.removeParticipant('${id}_${entry.key}');
        await db.addParticipant(id, entry.key, entry.value);
      }
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final calendars = ref.watch(calendarsProvider(spaceId)).valueOrNull ?? [];
    if (_calendarId == null && calendars.isNotEmpty) {
      _calendarId = calendars.first.id;
    }
    final isNew = widget.id == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvel événement' : 'Modifier l\'événement'),
        actions: [
          TextButton(
              onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleMedium,
            decoration: const InputDecoration(
                hintText: 'Titre de l\'événement', border: InputBorder.none),
            autofocus: isNew,
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Journée entière'),
            subtitle: const Text(
                'Dates civiles sans horaire ; la date de fin est exclusive.',
                style: TextStyle(fontSize: 12)),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          const SizedBox(height: LHSpacing.md),
          Row(children: [
            Expanded(
              child: LabeledField(
                label: 'Début',
                child: _dateTile(fmt.humanDate(fmt.parseKey(_startDate)),
                    () => _pickDate(false)),
              ),
            ),
            if (!_allDay) ...[
              const SizedBox(width: LHSpacing.md),
              SizedBox(
                width: 104,
                child: LabeledField(
                  label: 'Heure',
                  child: _dateTile(_startTime, () => _pickTime(isStart: true)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: LHSpacing.md),
          Row(children: [
            Expanded(
              child: LabeledField(
                label: _allDay ? 'Fin (dernier jour)' : 'Fin',
                child: _dateTile(
                    _allDay
                        ? fmt.humanDate(fmt.addDays(fmt.parseKey(_endDate), -1))
                        : fmt.humanDate(fmt.parseKey(_endDate.isEmpty ? _startDate : _endDate)),
                    () => _pickDate(true)),
              ),
            ),
            if (!_allDay) ...[
              const SizedBox(width: LHSpacing.md),
              SizedBox(
                width: 104,
                child: LabeledField(
                  label: 'Heure',
                  child: _dateTile(_endTime, () => _pickTime(isStart: false)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Calendrier',
            child: DropdownButtonFormField<String>(
              value: _calendarId,
              items: [
                for (final c in calendars)
                  DropdownMenuItem(
                      value: c.id,
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: hexToColor(c.colorHex),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ])),
              ],
              onChanged: (v) => setState(() => _calendarId = v),
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Récurrence',
            child: Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Aucune'),
                  selected: _recurrenceFreq == null,
                  onSelected: (_) => setState(() => _recurrenceFreq = null),
                ),
                for (final f in ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'])
                  ChoiceChip(
                    label: Text({
                      'DAILY': 'Quotidien',
                      'WEEKLY': 'Hebdo',
                      'MONTHLY': 'Mensuel',
                      'YEARLY': 'Annuel',
                    }[f]!),
                    selected: _recurrenceFreq == f,
                    onSelected: (_) => setState(() => _recurrenceFreq = f),
                  ),
              ],
            ),
          ),
          if (_recurrenceFreq == 'WEEKLY')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(fmt.weekdaysFr[d - 1]),
                      selected: _recurrenceDays.contains(d),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _recurrenceDays.add(d);
                        } else {
                          _recurrenceDays.remove(d);
                        }
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Lieu (optionnel)',
            child: TextField(
              controller: _location,
              decoration:
                  const InputDecoration(hintText: 'Ex. : Maison des jeunes'),
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Participants & invitations',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final name in _participants.keys)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: InitialsAvatar(name: name, size: 32),
                      title: Text(name),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButton<String>(
                          value: _participants[name],
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: 'INVITED', child: Text('Invité')),
                            DropdownMenuItem(
                                value: 'ACCEPTED', child: Text('Accepté')),
                            DropdownMenuItem(
                                value: 'DECLINED', child: Text('Décliné')),
                            DropdownMenuItem(
                                value: 'TENTATIVE', child: Text('Incertain')),
                          ],
                          onChanged: (v) =>
                              setState(() => _participants[name] = v ?? 'INVITED'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setState(() => _participants.remove(name)),
                        ),
                      ]),
                    ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _participantCtrl,
                        decoration: const InputDecoration(
                            hintText: 'Nom du participant…'),
                        onSubmitted: (v) {
                          final n = v.trim();
                          if (n.isNotEmpty) {
                            setState(() {
                              _participants[n] = 'INVITED';
                              _participantCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    IconButton(
                        onPressed: () {
                          final n = _participantCtrl.text.trim();
                          if (n.isNotEmpty) {
                            setState(() {
                              _participants[n] = 'INVITED';
                              _participantCtrl.clear();
                            });
                          }
                        },
                        icon: const Icon(Icons.person_add_alt)),
                  ]),
                ]),
          ),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Description',
            child: TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Détails…'),
            ),
          ),
          const SizedBox(height: LHSpacing.xl),
          if (widget.id != null) _existingActions(theme),
          const SizedBox(height: LHSpacing.xxl),
        ]),
      ),
    );
  }

  Widget _existingActions(ThemeData theme) {
    final eventAsync = ref.watch(eventProvider(widget.id!));
    final e = eventAsync.valueOrNull;
    if (e == null) return const SizedBox();
    final db = ref.read(dbProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (e.status == 'SCHEDULED')
          OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Terminer'),
            onPressed: () async {
              await db.setEventStatus(e.id, 'COMPLETED');
            },
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: const Text('Reporter'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: fmt.parseKey(e.startDate),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              locale: const Locale('fr'),
            );
            if (picked != null) {
              await db.rescheduleEvent(e, fmt.dateKey(picked), e.startTime);
              if (mounted) lhToast(context, 'Événement reporté (historique conservé).');
            }
          },
        ),
        if (e.status == 'SCHEDULED')
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Annuler'),
            onPressed: () async {
              await db.setEventStatus(e.id, 'CANCELLED');
            },
          ),
        if (e.status != 'SCHEDULED')
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Replanifier'),
            onPressed: () => db.setEventStatus(e.id, 'SCHEDULED'),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: LHColors.erreur),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Supprimer'),
          onPressed: () async {
            final ok = await lhConfirm(context,
                title: 'Supprimer l\'événement ?',
                message:
                    '« ${e.title} » sera supprimé. Cette action est journalisée pour la synchronisation.',
                confirmLabel: 'Supprimer',
                destructive: true);
            if (ok) {
              await db.deleteEvent(e);
              if (mounted) context.pop();
            }
          },
        ),
      ]),
      if (e.originalStart != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Reporté — date initiale : ${fmt.formatLong(fmt.parseKey(e.originalStart!))}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _dateTile(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LHRadius.md),
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(label),
      ),
    );
  }
}

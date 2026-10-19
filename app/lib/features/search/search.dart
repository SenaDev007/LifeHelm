import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart' as dbm;
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

// ═══════════════════════════ RÉSULTATS (D14) ═══════════════════════════

class SearchHit {
  SearchHit({
    required this.module,
    required this.title,
    required this.subtitle,
    required this.route,
    this.icon,
  });

  final String module; // clé de filtre
  final String title;
  final String subtitle;
  final String route;
  final IconData? icon;
}

String searchModuleLabel(String m) => switch (m) {
      'tasks' => 'Tâches',
      'events' => 'Agenda',
      'finance' => 'Finances',
      'notes' => 'Notes',
      'projects' => 'Projets',
      'goals' => 'Objectifs',
      'habits' => 'Habitudes',
      'contacts' => 'Contacts',
      'messages' => 'Messages',
      'documents' => 'Documents',
      _ => m,
    };

IconData searchModuleIcon(String m) => switch (m) {
      'tasks' => Icons.checklist_rounded,
      'events' => Icons.event_rounded,
      'finance' => Icons.account_balance_wallet_rounded,
      'notes' => Icons.edit_note_rounded,
      'projects' => Icons.flag_rounded,
      'goals' => Icons.track_changes,
      'habits' => Icons.repeat_rounded,
      'contacts' => Icons.people_outline,
      'messages' => Icons.chat_bubble_outline_rounded,
      'documents' => Icons.description_outlined,
      _ => Icons.search,
    };

// ═══════════════════════════ SERVICE ═══════════════════════════

/// Recherche textuelle locale multi-modules (D14 §19.1-1).
/// Limitée à l'espace actif par défaut (D14 §19.1-3).
extension SearchQueries on dbm.AppDatabase {
  Future<List<SearchHit>> searchAll(String spaceId, String rawQuery,
      {String? moduleFilter}) async {
    final q = rawQuery.trim().toLowerCase();
    if (q.length < 2) return const [];
    final hits = <SearchHit>[];
    bool match(String? text) =>
        text != null && text.toLowerCase().contains(q);

    if (moduleFilter == null || moduleFilter == 'tasks') {
      final rows = await (select(tasks)
            ..where((t) =>
                t.spaceId.equals(spaceId) & t.archivedAt.isNull()))
          .get();
      for (final t in rows) {
        if (match(t.title) || match(t.notes)) {
          hits.add(SearchHit(
            module: 'tasks',
            title: t.title,
            subtitle: 'Tâche · ${_taskSub(t.status)}',
            route: '/task/${t.id}',
          ));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'events') {
      final rows = await (select(calendarEvents)
            ..where((e) => e.spaceId.equals(spaceId)))
          .get();
      for (final e in rows) {
        if (match(e.title) || match(e.description) || match(e.location)) {
          hits.add(SearchHit(
            module: 'events',
            title: e.title,
            subtitle: 'Événement · ${e.startDate.split('-').reversed.join('/')}',
            route: '/event/${e.id}',
          ));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'finance') {
      final txs = await (select(financialTransactions)
            ..where((t) => t.spaceId.equals(spaceId)))
          .get();
      final accounts = await (select(financialAccounts)
            ..where((a) => a.spaceId.equals(spaceId)))
          .get();
      for (final t in txs) {
        if (match(t.note)) {
          final acc =
              accounts.where((a) => a.id == t.accountId).firstOrNull;
          hits.add(SearchHit(
            module: 'finance',
            title: t.note ?? 'Opération',
            subtitle:
                'Opération · ${acc?.name ?? ''} · ${t.occurredAt.day}/${t.occurredAt.month}/${t.occurredAt.year}',
            route: '/account/${t.accountId}',
          ));
        }
      }
      for (final a in accounts) {
        if (match(a.name)) {
          hits.add(SearchHit(
              module: 'finance',
              title: a.name,
              subtitle: 'Compte · ${a.currency}',
              route: '/account/${a.id}'));
        }
      }
      final dues = await (select(financialDueItems)
            ..where((d) => d.spaceId.equals(spaceId)))
          .get();
      for (final d in dues) {
        if (match(d.label)) {
          hits.add(SearchHit(
              module: 'finance',
              title: d.label,
              subtitle: 'Échéance · ${d.dueDate.split('-').reversed.join('/')}',
              route: '/dues'));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'notes') {
      final rows = await (select(notes)
            ..where((n) =>
                n.spaceId.equals(spaceId) & n.trashedAt.isNull()))
          .get();
      for (final n in rows) {
        if (match(n.title) || match(n.plainText)) {
          hits.add(SearchHit(
            module: 'notes',
            title: n.title,
            subtitle: n.plainText.length > 60
                ? 'Note · ${n.plainText.substring(0, 60)}…'
                : 'Note',
            route: '/note/${n.id}',
          ));
        }
      }
      final docs = await (select(documents)
            ..where((d) => d.spaceId.equals(spaceId)))
          .get();
      for (final d in docs) {
        if (match(d.name)) {
          hits.add(SearchHit(
              module: 'documents',
              title: d.name,
              subtitle: 'Document · ${d.mimeType}',
              route: '/notes'));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'projects') {
      final rows = await (select(projects)
            ..where((p) => p.spaceId.equals(spaceId)))
          .get();
      for (final p in rows) {
        if (match(p.name) || match(p.description)) {
          hits.add(SearchHit(
            module: 'projects',
            title: p.name,
            subtitle: 'Projet${p.description != null ? ' · ${p.description}' : ''}',
            route: '/project/${p.id}',
          ));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'goals') {
      final rows = await (select(goals)..where((g) => g.spaceId.equals(spaceId))).get();
      for (final g in rows) {
        if (match(g.title) || match(g.description)) {
          hits.add(SearchHit(
              module: 'goals',
              title: g.title,
              subtitle: 'Objectif',
              route: '/goal/${g.id}'));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'habits') {
      final rows = await (select(habits)
            ..where((h) => h.spaceId.equals(spaceId) & h.archivedAt.isNull()))
          .get();
      for (final h in rows) {
        if (match(h.name) || match(h.description)) {
          hits.add(SearchHit(
              module: 'habits',
              title: h.name,
              subtitle: 'Habitude',
              route: '/habit/${h.id}'));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'contacts') {
      final rows = await (select(contacts)
            ..where((c) => c.spaceId.equals(spaceId)))
          .get();
      for (final c in rows) {
        final name = c.kind == 'PERSON'
            ? '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim()
            : (c.organizationName ?? '');
        if (match(name) || match(c.notes) || match(c.jobTitle)) {
          hits.add(SearchHit(
              module: 'contacts',
              title: name,
              subtitle: c.kind == 'PERSON' ? 'Contact' : 'Organisation',
              route: '/contact/${c.id}'));
        }
      }
    }

    if (moduleFilter == null || moduleFilter == 'messages') {
      final convs = await (select(conversations)
            ..where((c) => c.spaceId.equals(spaceId)))
          .get();
      for (final conv in convs) {
        final msgs = await (select(messages)
              ..where((m) =>
                  m.conversationId.equals(conv.id) & m.deletedAt.isNull()))
            .get();
        for (final m in msgs) {
          if (match(m.body)) {
            hits.add(SearchHit(
              module: 'messages',
              title: m.body.length > 70 ? '${m.body.substring(0, 70)}…' : m.body,
              subtitle:
                  'Message${conv.title != null ? ' · ${conv.title}' : ''}',
              route: '/chat/${conv.id}',
            ));
            break; // une occurrence par conversation suffit
          }
        }
      }
    }

    // Classement par pertinence : correspondance de titre d'abord.
    hits.sort((a, b) {
      final at = a.title.toLowerCase().contains(q) ? 0 : 1;
      final bt = b.title.toLowerCase().contains(q) ? 0 : 1;
      return at.compareTo(bt);
    });
    return hits;
  }

  static String _taskSub(String status) => switch (status) {
        'TODO' => 'à faire',
        'IN_PROGRESS' => 'en cours',
        'WAITING' => 'en attente',
        'DONE' => 'terminée',
        _ => 'annulée',
      };

  Future<void> recordSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    await into(recentSearches)
        .insert(dbm.RecentSearche(
            id: 'rs_${DateTime.now().microsecondsSinceEpoch}',
            query: q,
            at: DateTime.now()));
    // Rétention : garde les 20 dernières.
    final all = await (select(recentSearches)
          ..orderBy([(r) => OrderingTerm(
              expression: r.at, mode: OrderingMode.desc)]))
        .get();
    for (final r in all.skip(20)) {
      await (delete(recentSearches)..where((x) => x.id.equals(r.id))).go();
    }
  }

  Stream<List<String>> watchRecentSearches() {
    return (select(recentSearches)
          ..orderBy(
              [(r) => OrderingTerm(expression: r.at, mode: OrderingMode.desc)]))
        .watch()
        .map((rows) => rows.map((r) => r.query).toList());
  }
}

final recentSearchesProvider = StreamProvider<List<String>>(
    (ref) => ref.watch(dbProvider).watchRecentSearches());

// ═══════════════════════════ ÉCRAN : RECHERCHE ═══════════════════════════

/// Recherche globale — suggestions pendant la saisie, résultats filtrés
/// par module, classement par pertinence (D14 §19.3).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  String? _moduleFilter;
  Future<List<SearchHit>>? _future;
  final _filterable = <String>{
    'tasks', 'events', 'finance', 'notes', 'projects', 'goals', 'habits',
    'contacts', 'messages'
  };

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final spaceId = ref.read(activeSpaceIdProvider);
      setState(() {
        _query = value;
        _future = value.trim().length < 2
            ? null
            : ref.read(dbProvider).searchAll(spaceId, value,
                moduleFilter: _moduleFilter);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = ref.watch(recentSearchesProvider).valueOrNull ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            ref.read(dbProvider).recordSearch(v);
            _onChanged(v);
          },
          decoration: const InputDecoration(
            hintText: 'Rechercher dans l\'espace actif…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _query = '';
                  _future = null;
                });
              },
            ),
        ],
      ),
      body: Column(children: [
        // Filtres par module (D14 §19.1-7)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip(null, 'Tout'),
              for (final m in _filterable) _filterChip(m, searchModuleLabel(m)),
            ],
          ),
        ),
        Expanded(
          child: _query.trim().length < 2
              ? (recent.isEmpty
                  ? const EmptyState(
                      icon: Icons.search,
                      message: 'Recherchez dans tous vos modules',
                      hint:
                          'Tâches, notes, contacts, opérations, messages… — limité à l\'espace actif.')
                  : ListView(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text('RECHERCHES RÉCENTES',
                            style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      for (final r in recent)
                        ListTile(
                          leading: const Icon(Icons.history, size: 20),
                          title: Text(r),
                          dense: true,
                          onTap: () {
                            _controller.text = r;
                            _onChanged(r);
                          },
                        ),
                    ]))
              : FutureBuilder<List<SearchHit>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final hits = snap.data ?? const <SearchHit>[];
                    if (hits.isEmpty) {
                      return EmptyState(
                        icon: Icons.search_off,
                        message: 'Aucun résultat pour « $_query »',
                        hint:
                            'Vérifiez l\'orthographe ou changez de filtre de module.',
                      );
                    }
                    // Groupement par module.
                    final grouped = <String, List<SearchHit>>{};
                    for (final h in hits) {
                      (grouped[h.module] ??= []).add(h);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: grouped.length,
                      itemBuilder: (context, i) {
                        final module = grouped.keys.elementAt(i);
                        final moduleHits = grouped[module]!;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 14, 20, 2),
                                child: Row(children: [
                                  Icon(searchModuleIcon(module),
                                      size: 16,
                                      color: theme.brightness ==
                                              Brightness.dark
                                          ? LHColors.or
                                          : LHColors.orDeep),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${searchModuleLabel(module)} — ${moduleHits.length}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ]),
                              ),
                              ...moduleHits.take(5).map((h) => ListTile(
                                    dense: true,
                                    leading: h.icon != null
                                        ? Icon(h.icon)
                                        : Icon(searchModuleIcon(h.module),
                                            color: theme.colorScheme
                                                .onSurfaceVariant),
                                    title: Text(h.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(h.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)),
                                    onTap: () {
                                      ref
                                          .read(dbProvider)
                                          .recordSearch(_query);
                                      context.push(h.route);
                                    },
                                  )),
                            ]);
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _filterChip(String? value, String label) {
    final selected = _moduleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (sel) {
          setState(() => _moduleFilter = sel ? value : null);
          _onChanged(_controller.text);
        },
      ),
    );
  }
}

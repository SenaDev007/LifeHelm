import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';

/// Fournisseurs Riverpod transversaux.
/// Riverpod est la proposition du CDC (§3.3) adoptée pour ce projet.

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Réglages applicatifs (table Settings) sous forme de flux clé-valeur.
final settingsProvider = StreamProvider<Map<String, String>>(
    (ref) => ref.watch(dbProvider).watchSettings());

/// Espace actif — persisté dans les réglages (CDC §5).
class ActiveSpaceNotifier extends StateNotifier<String> {
  ActiveSpaceNotifier(this._db) : super('') {
    _init();
  }
  final AppDatabase _db;

  Future<void> _init() async {
    final saved = await _db.getSetting('activeSpaceId');
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    } else {
      final spaces = await _db.getAllSpaces();
      if (spaces.isNotEmpty) state = spaces.first.id;
    }
  }

  /// Recharge l'espace actif depuis les réglages (après onboarding).
  Future<void> reload() => _init();

  Future<void> set(String spaceId) async {
    state = spaceId;
    await _db.setSetting('activeSpaceId', spaceId);
  }
}

final activeSpaceIdProvider =
    StateNotifierProvider<ActiveSpaceNotifier, String>(
        (ref) => ActiveSpaceNotifier(ref.watch(dbProvider)));

/// Espace actif (données complètes).
final activeSpaceProvider = StreamProvider<Space?>((ref) {
  final id = ref.watch(activeSpaceIdProvider);
  if (id.isEmpty) return const Stream.empty();
  return ref.watch(dbProvider).watchSpace(id);
});

/// Tous les espaces.
final spacesProvider = StreamProvider<List<Space>>(
    (ref) => ref.watch(dbProvider).watchSpaces());

/// Mode de thème : clair / sombre / système (CDC §4.3).
final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
  switch (settings['themeMode']) {
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    default:
      return ThemeMode.light; // interface claire Navy Royal + Or solaire
  }
});

/// Préférences du cockpit (D02) : sections visibles, ordre, fenêtre, résumés.
class CockpitPrefs {
  final List<String> visibleSections;
  final List<String> sectionOrder;
  final int upcomingWindowDays;
  final bool showFinanceSummary;
  final bool showAiSummary; // désactivée par défaut (D02 §7.1-4)

  const CockpitPrefs({
    this.visibleSections = const [
      'today', 'actions', 'priorities', 'agenda', 'finance', 'goals', 'alerts'
    ],
    this.sectionOrder = const [
      'today', 'actions', 'priorities', 'agenda', 'finance', 'goals', 'alerts'
    ],
    this.upcomingWindowDays = 7, // valeur proposée, non figée (CDC D02 §7.1-5)
    this.showFinanceSummary = true,
    this.showAiSummary = false,
  });

  CockpitPrefs copyWith({
    List<String>? visibleSections,
    List<String>? sectionOrder,
    int? upcomingWindowDays,
    bool? showFinanceSummary,
    bool? showAiSummary,
  }) =>
      CockpitPrefs(
        visibleSections: visibleSections ?? this.visibleSections,
        sectionOrder: sectionOrder ?? this.sectionOrder,
        upcomingWindowDays: upcomingWindowDays ?? this.upcomingWindowDays,
        showFinanceSummary: showFinanceSummary ?? this.showFinanceSummary,
        showAiSummary: showAiSummary ?? this.showAiSummary,
      );
}

final cockpitPrefsProvider = Provider<CockpitPrefs>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull ?? const {};
  List<String> parse(String? raw, List<String> fallback) {
    if (raw == null) return fallback;
    try {
      final l = (jsonDecode(raw) as List).cast<String>();
      return l.isEmpty ? fallback : l;
    } catch (_) {
      return fallback;
    }
  }

  return CockpitPrefs(
    visibleSections: parse(s['cockpitVisibleSections'],
        const ['today', 'actions', 'priorities', 'agenda', 'finance', 'goals', 'alerts']),
    sectionOrder: parse(s['cockpitSectionOrder'],
        const ['today', 'actions', 'priorities', 'agenda', 'finance', 'goals', 'alerts']),
    upcomingWindowDays: int.tryParse(s['upcomingWindowDays'] ?? '') ?? 7,
    showFinanceSummary: (s['showFinanceSummary'] ?? 'true') == 'true',
    showAiSummary: (s['showAiSummary'] ?? 'false') == 'true',
  );
});

/// Compteur de notifications non lues (badge cloche).
final unreadNotifCountProvider = StreamProvider<int>(
    (ref) => ref.watch(dbProvider).watchUnreadCount());

/// File de synchronisation en attente (D01.4).
final pendingOpsProvider = StreamProvider<List<SyncOperation>>(
    (ref) => ref.watch(dbProvider).watchPendingOps());

final pendingOpCountProvider = StreamProvider<int>(
    (ref) => ref.watch(dbProvider).watchPendingOpCount());

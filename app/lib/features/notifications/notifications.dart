import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart' as dbm;
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../ai/briefing.dart' show AiAlertsSection;

// ═══════════════════════════ LABELS (D13) ═══════════════════════════

String notifPriorityLabel(String p) => switch (p) {
      'INFO' => 'Info',
      'NORMAL' => 'Normale',
      'IMPORTANT' => 'Importante',
      'CRITICAL' => 'Critique',
      _ => p,
    };

Color notifPriorityColor(String p) => switch (p) {
      'INFO' => LHColors.notifInfo,
      'NORMAL' => LHColors.notifNormale,
      'IMPORTANT' => LHColors.notifImportante,
      'CRITICAL' => LHColors.notifCritique,
      _ => LHColors.neutre,
    };

String notifCategoryLabel(String c) => switch (c) {
      'TASK' => 'Tâches',
      'AGENDA' => 'Agenda',
      'FINANCE' => 'Finances',
      'PROJECT' => 'Projets',
      'HABIT' => 'Habitudes',
      'NOTE' => 'Notes',
      'MESSAGE' => 'Messagerie',
      'SECURITY' => 'Sécurité',
      _ => 'Système',
    };

IconData notifCategoryIcon(String c) => switch (c) {
      'TASK' => Icons.checklist_rounded,
      'AGENDA' => Icons.event_rounded,
      'FINANCE' => Icons.account_balance_wallet_rounded,
      'PROJECT' => Icons.flag_rounded,
      'HABIT' => Icons.repeat_rounded,
      'NOTE' => Icons.edit_note_rounded,
      'MESSAGE' => Icons.chat_bubble_outline_rounded,
      'SECURITY' => Icons.shield_outlined,
      _ => Icons.system_update,
    };

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension NotificationQueries on dbm.AppDatabase {
  Stream<List<dbm.Notification>> watchActive(String spaceId) {
    return (select(notifications)
          ..where((n) =>
              n.spaceId.equals(spaceId) &
              n.archivedAt.isNull() &
              (n.snoozedUntil.isNull() |
                  n.snoozedUntil.isSmallerThanValue(DateTime.now())))
          ..orderBy([
            (n) =>
                OrderingTerm(expression: n.priority, mode: OrderingMode.desc),
            (n) =>
                OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<dbm.Notification>> watchArchived(String spaceId) {
    return (select(notifications)
          ..where((n) => n.spaceId.equals(spaceId) & n.archivedAt.isNotNull())
          ..orderBy([
            (n) =>
                OrderingTerm(expression: n.archivedAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  Future<void> markRead(String id, {bool read = true}) async {
    await (update(notifications)..where((n) => n.id.equals(id))).write(
        dbm.NotificationsCompanion(
            readAt: Value(read ? DateTime.now() : null)));
  }

  Future<void> markAllRead(String spaceId) async {
    await (update(notifications)
          ..where((n) =>
              n.spaceId.equals(spaceId) &
              n.readAt.isNull() &
              n.archivedAt.isNull()))
        .write(dbm.NotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> snooze(String id, Duration duration) async {
    await (update(notifications)..where((n) => n.id.equals(id))).write(
        dbm.NotificationsCompanion(
            snoozedUntil: Value(DateTime.now().add(duration))));
    logOp(
        'Notification', id, 'UPDATE', {'snoozedFor': '${duration.inMinutes}m'});
  }

  Future<void> archive(String id, {bool archived = true}) async {
    await (update(notifications)..where((n) => n.id.equals(id))).write(
        dbm.NotificationsCompanion(
            archivedAt: Value(archived ? DateTime.now() : null)));
  }

  /// Plages silencieuses : les alertes non critiques sont regroupées
  /// visuellement pendant la plage (D13 §18.1-7).
  (bool, String) quietHoursStatus(Map<String, String> settings) {
    final enabled = (settings['quietHoursEnabled'] ?? 'false') == 'true';
    if (!enabled) return (false, '');
    final start = settings['quietStart'] ?? '22:00';
    final end = settings['quietEnd'] ?? '07:00';
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    int parse(String s) =>
        (int.tryParse(s.split(':')[0]) ?? 0) * 60 +
        (int.tryParse(s.split(':')[1]) ?? 0);
    final s = parse(start), e = parse(end);
    final inRange =
        s <= e ? (minutes >= s && minutes < e) : (minutes >= s || minutes < e);
    return (inRange, '$start – $end');
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final activeNotificationsProvider =
    StreamProvider.family<List<dbm.Notification>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchActive(spaceId));

final archivedNotificationsProvider =
    StreamProvider.family<List<dbm.Notification>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchArchived(spaceId));

// ═══════════════════════════ ÉCRAN : CENTRE ═══════════════════════════

/// Centre de notifications intégré (D13 §18.1-6) — priorités, report,
/// archivage, plages silencieuses.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final active = ref.watch(activeNotificationsProvider(spaceId));
    final archived = ref.watch(archivedNotificationsProvider(spaceId));
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
    final (inQuiet, quietRange) =
        ref.watch(dbProvider).quietHoursStatus(settings);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            IconButton(
              tooltip: 'Tout marquer lu',
              icon: const Icon(Icons.done_all),
              onPressed: () => ref.read(dbProvider).markAllRead(spaceId),
            ),
            IconButton(
              tooltip: 'Préférences',
              icon: const Icon(Icons.tune),
              onPressed: () => context.push('/notification-preferences'),
            ),
          ],
        ),
        body: Column(children: [
          if (inQuiet)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: LHColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(LHRadius.md),
                border: Border.all(color: LHColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.bedtime_outlined,
                    size: 16, color: LHColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plage silencieuse active ($quietRange) — les alertes non critiques seront regroupées. Les critiques passent toujours.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                ),
              ]),
            ),
          TabBar(
            tabs: [
              Tab(text: 'Actives (${active.valueOrNull?.length ?? 0})'),
              Tab(text: 'Archivées (${archived.valueOrNull?.length ?? 0})'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _list(context, ref, active.valueOrNull ?? [], active: true),
              _list(context, ref, archived.valueOrNull ?? [], active: false),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _list(
      BuildContext context, WidgetRef ref, List<dbm.Notification> items,
      {required bool active}) {
    // Onglet actif : les alertes intelligentes HELM AI (serveur, Phase 3)
    // figurent en tête, avant les notifications locales des modules.
    final leading = active ? const [AiAlertsSection()] : const <Widget>[];
    if (items.isEmpty && leading.isEmpty) {
      return EmptyState(
        icon:
            active ? Icons.notifications_none_rounded : Icons.archive_outlined,
        message: active
            ? 'Aucune notification active'
            : 'Aucune notification archivée',
        hint: active
            ? 'Les alertes de vos modules apparaîtront ici.'
            : 'Les notifications archivées sont conservées 90 jours.',
      );
    }
    if (items.isEmpty) {
      return ListView(
          padding: const EdgeInsets.only(bottom: 24, top: 8),
          children: [
            ...leading,
            if (active) _emptyActive(theme: Theme.of(context))
          ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      itemCount: leading.length + items.length,
      itemBuilder: (context, i) => i < leading.length
          ? leading[i]
          : _NotifTile(n: items[i - leading.length], activeList: active),
    );
  }

  Widget _emptyActive({required ThemeData theme}) => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(children: [
          Icon(Icons.notifications_none_rounded,
              size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Aucune notification de module active',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _NotifTile extends ConsumerWidget {
  const _NotifTile({required this.n, required this.activeList});
  final dbm.Notification n;
  final bool activeList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.read(dbProvider);
    final unread = n.readAt == null;
    final color = notifPriorityColor(n.priority);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LHCard(
        accent: color,
        onTap: () {
          // Navigation vers la ressource source si connue.
          final route = switch (n.resourceType) {
            'TASK' => '/task/${n.resourceId}',
            'EVENT' => '/event/${n.resourceId}',
            'DUE' => '/dues',
            'BUDGET' => '/budgets',
            'CONVERSATION' => '/chat/${n.resourceId}',
            _ => null,
          };
          if (route != null && n.resourceId != null) {
            context.push(route);
          }
          if (unread) db.markRead(n.id);
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(notifCategoryIcon(n.category), size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread ? FontWeight.w800 : null)),
                    Text(
                      '${notifCategoryLabel(n.category)} · ${notifPriorityLabel(n.priority)} · ${fmt.humanDate(n.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
            ),
            if (unread)
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ]),
          const SizedBox(height: 8),
          Text(n.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          if (activeList) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (unread)
                ActionChip(
                  label:
                      const Text('Marquer lu', style: TextStyle(fontSize: 12)),
                  onPressed: () => db.markRead(n.id),
                ),
              ChoiceChip(
                label: const Text('Plus tard', style: TextStyle(fontSize: 12)),
                selected: false,
                onSelected: (_) => db.snooze(n.id, const Duration(hours: 1)),
              ),
              ActionChip(
                label: const Text('Demain', style: TextStyle(fontSize: 12)),
                onPressed: () => db.snooze(n.id, const Duration(hours: 16)),
              ),
              ActionChip(
                label: const Text('Archiver', style: TextStyle(fontSize: 12)),
                onPressed: () => db.archive(n.id),
              ),
            ]),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => db.archive(n.id, archived: false),
                child: const Text('Restaurer'),
              ),
            ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : PRÉFÉRENCES ═══════════════════════════

/// Préférences par catégorie + plages silencieuses (D13 §18.4).
class NotificationPrefsScreen extends ConsumerStatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  ConsumerState<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState
    extends ConsumerState<NotificationPrefsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
    final prefsAsync = ref.watch(notifPrefsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de notifications')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        SectionHeader('Plage silencieuse',
            inset: LHSpacing.screen, overline: 'Tranquillité'),
        SwitchListTile(
          secondary: const Icon(Icons.bedtime_outlined),
          title: const Text('Activer la plage silencieuse'),
          subtitle: Text(
              'Les alertes non critiques sont regroupées pendant la plage ; les critiques passent toujours (CDC D13).'),
          value: (settings['quietHoursEnabled'] ?? 'false') == 'true',
          onChanged: (v) => db.setSetting('quietHoursEnabled', '$v'),
        ),
        if ((settings['quietHoursEnabled'] ?? 'false') == 'true')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: LabeledField(
                  label: 'Début',
                  child: _timeField(settings['quietStart'] ?? '22:00',
                      (t) => db.setSetting('quietStart', t)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Fin',
                  child: _timeField(settings['quietEnd'] ?? '07:00',
                      (t) => db.setSetting('quietEnd', t)),
                ),
              ),
            ]),
          ),
        SectionHeader('Par catégorie',
            inset: LHSpacing.screen, overline: 'Filtres'),
        prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (prefs) => Column(
            children: [
              for (final p in prefs)
                SwitchListTile(
                  secondary: Icon(notifCategoryIcon(p.category),
                      color: notifPriorityColor('NORMAL')),
                  title: Text(notifCategoryLabel(p.category)),
                  value: p.inAppEnabled,
                  onChanged: (v) async {
                    await (db.update(db.notificationPrefs)
                          ..where((x) => x.id.equals(p.id)))
                        .write(dbm.NotificationPrefsCompanion(
                            inAppEnabled: Value(v)));
                    db.logOp(
                        'NotificationPref', p.category, 'UPDATE', {'inApp': v});
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Les préférences ne modifient jamais la ressource source : reporter le rappel d\'une échéance ne reporte pas sa date (CDC D13 §18.4).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  Widget _timeField(String current, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () async {
        final parts = current.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 22,
              minute: int.tryParse(parts[1]) ?? 0),
        );
        if (picked != null) {
          onChanged(
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(current),
      ),
    );
  }
}

final notifPrefsListProvider =
    StreamProvider<List<dbm.NotificationPref>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.notificationPrefs)
        ..orderBy([(p) => OrderingTerm(expression: p.category)]))
      .watch();
});

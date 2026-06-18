import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../providers/notification_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Tout marquer comme lu',
            onPressed: () async {
              try {
                await ref.read(notificationRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Toutes les notifications sont marquées comme lues'),
                      backgroundColor: LifeHelmColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: notifsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 16),
              Text('Erreur: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(notificationsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
          data: (result) {
            if (result.notifications.isEmpty) {
              return _EmptyState(
                onGenerate: () async {
                  try {
                    await ref.read(notificationRepositoryProvider).generateDaily();
                    ref.invalidate(notificationsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Notifications du jour générées'),
                          backgroundColor: LifeHelmColors.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                      );
                    }
                  }
                },
              );
            }
            return Column(
              children: [
                if (result.unreadCount > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: LifeHelmColors.info.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active, color: LifeHelmColors.info, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${result.unreadCount} notification(s) non lue(s)',
                            style: const TextStyle(
                              color: LifeHelmColors.info,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await ref.read(notificationRepositoryProvider).markAllRead();
                              ref.invalidate(notificationsProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                                );
                              }
                            }
                          },
                          child: const Text('Tout lire'),
                        ),
                      ],
                    ),
                  ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: result.notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final n = result.notifications[i];
                    return Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: LifeHelmColors.danger,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Supprimer la notification'),
                            content: const Text('Cette action est irréversible.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                                child: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) async {
                        try {
                          await ref.read(notificationRepositoryProvider).delete(n.id);
                          ref.invalidate(notificationsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notification supprimée'),
                                backgroundColor: LifeHelmColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                            );
                          }
                          ref.invalidate(notificationsProvider);
                        }
                      },
                      child: _NotificationTile(
                        notification: n,
                        onTap: () async {
                          // Marquer comme lu si pas déjà lu
                          if (!n.read) {
                            try {
                              await ref.read(notificationRepositoryProvider).markRead(n.id);
                              ref.invalidate(notificationsProvider);
                            } catch (_) {}
                          }
                          // Navigation selon le type
                          _navigate(context, n);
                        },
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _navigate(BuildContext context, NotificationItem n) {
    switch (n.type.toUpperCase()) {
      case 'FINANCE':
        context.push('/finance');
        break;
      case 'GOALS':
        context.push('/goals');
        break;
      case 'ROUTINES':
        context.push('/routines');
        break;
      case 'HEALTH':
        context.push('/health');
        break;
      case 'FAMILY':
        context.push('/family');
        break;
      case 'SUBSCRIPTION':
        context.push('/subscriptions');
        break;
      case 'INSIGHT':
      case 'AI':
        context.push('/ai');
        break;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});
  final NotificationItem notification;
  final VoidCallback onTap;

  IconData _iconFor(String type) {
    switch (type.toUpperCase()) {
      case 'FINANCE': return Icons.account_balance_wallet;
      case 'HEALTH': return Icons.favorite;
      case 'ROUTINES': return Icons.today;
      case 'GOALS': return Icons.flag;
      case 'FAMILY': return Icons.family_restroom;
      case 'SUBSCRIPTION': return Icons.star;
      case 'INSIGHT': return Icons.lightbulb;
      case 'REMINDER': return Icons.alarm;
      case 'SYSTEM':
      default:
        return Icons.info;
    }
  }

  Color _colorFor(String type) {
    switch (type.toUpperCase()) {
      case 'FINANCE': return LifeHelmColors.finance;
      case 'HEALTH': return LifeHelmColors.health;
      case 'ROUTINES': return LifeHelmColors.routines;
      case 'GOALS': return LifeHelmColors.goals;
      case 'FAMILY': return LifeHelmColors.relations;
      case 'SUBSCRIPTION': return LifeHelmColors.accent;
      case 'INSIGHT': return LifeHelmColors.primary;
      case 'REMINDER': return LifeHelmColors.warning;
      default: return LifeHelmColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(notification.type);
    final icon = _iconFor(notification.type);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: notification.read
            ? BorderSide.none
            : BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.read ? FontWeight.w600 : FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!notification.read)
                          Container(
                            width: 8, height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: LifeHelmColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            NotificationTypes.label(notification.type),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (notification.createdAt != null)
                          Text(
                            FormatUtils.formatRelative(notification.createdAt!),
                            style: const TextStyle(
                              color: LifeHelmColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: LifeHelmColors.info.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none, color: LifeHelmColors.info, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune notification',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'LifeHelm analyse tes données chaque jour pour t\'envoyer des rappels et insights pertinents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Générer celles du jour'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// V2 — Widget indicateur de sync (à mettre dans l'AppBar)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_service.dart';
import '../theme/theme.dart';

class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncService = ref.watch(syncServiceProvider);
    return StreamBuilder<SyncStatus>(
      stream: syncService.statusStream,
      initialData: syncService.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        final config = _statusConfig(status);

        return IconButton(
          icon: Icon(config.icon, color: config.color, size: 20),
          tooltip: config.label,
          onPressed: () {
            if (status == SyncStatus.offline || status == SyncStatus.error || status == SyncStatus.idle) {
              syncService.sync(force: true);
            }
          },
        );
      },
    );
  }

  _StatusConfig _statusConfig(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return _StatusConfig(Icons.cloud_done, LifeHelmColors.textTertiary, 'Synchronisé');
      case SyncStatus.pushing:
        return _StatusConfig(Icons.upload, LifeHelmColors.info, 'Envoi…');
      case SyncStatus.pulling:
        return _StatusConfig(Icons.download, LifeHelmColors.info, 'Récupération…');
      case SyncStatus.done:
        return _StatusConfig(Icons.cloud_done, LifeHelmColors.success, 'À jour');
      case SyncStatus.error:
        return _StatusConfig(Icons.cloud_off, LifeHelmColors.danger, 'Erreur — tap pour réessayer');
      case SyncStatus.offline:
        return _StatusConfig(Icons.cloud_off, LifeHelmColors.warning, 'Hors ligne');
    }
  }
}

class _StatusConfig {
  final IconData icon;
  final Color color;
  final String label;
  _StatusConfig(this.icon, this.color, this.label);
}

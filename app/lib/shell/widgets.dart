import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/common.dart';

/// Barre d'application transversale : sélecteur d'espace, recherche, cloche.
class LhAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const LhAppBar({super.key, this.title, this.showActions = true});

  final String? title;
  final bool showActions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _openSpaceSwitcher(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final spaces = await db.getAllSpaces();
    final activeId = ref.read(activeSpaceIdProvider);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8,  20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Changer d\'espace',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          ...spaces.map((s) {
            final active = s.id == activeId;
            return ListTile(
              leading: InitialsAvatar(name: s.name, color: spaceColor(s.type), size: 38),
              title: Text(s.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(spaceTypeLabel(s.type), style: const TextStyle(fontSize: 12)),
              trailing: active
                  ? const Icon(Icons.check_circle,
                      color: LHColors.emeraudeClair)
                  : null,
              onTap: () {
                ref.read(activeSpaceIdProvider.notifier).set(s.id);
                Navigator.pop(ctx);
              },
            );
          }),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Gérer les espaces'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/spaces');
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(activeSpaceProvider).valueOrNull;
    final theme = Theme.of(context);
    return AppBar(
      title: title != null
          ? Text(title!)
          : InkWell(
              onTap: () => _openSpaceSwitcher(context, ref),
              borderRadius: BorderRadius.circular(LHRadius.full),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  InitialsAvatar(
                      name: space?.name ?? '…',
                      color: spaceColor(space?.type ?? 'PERSONAL'),
                      size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      space?.name ?? 'LifeHelm',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 18),
                ]),
              ),
            ),
      actions: showActions
          ? [
              // HELM AI — accès à l'assistant depuis tous les modules (D17).
              IconButton(
                tooltip: 'HELM AI — Assistant',
                icon: const Icon(Icons.auto_awesome_rounded),
                onPressed: () => context.push('/assistant'),
              ),
              IconButton(
                tooltip: 'Recherche globale',
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/search'),
              ),
              _BellButton(onTap: () => context.push('/notifications')),
              const SizedBox(width: 4),
            ]
          : null,
    );
  }
}

class _BellButton extends ConsumerWidget {
  const _BellButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotifCountProvider).valueOrNull ?? 0;
    return Stack(alignment: Alignment.center, children: [
      IconButton(
        tooltip: 'Notifications',
        icon: const Icon(Icons.notifications_none_rounded),
        onPressed: onTap,
      ),
      if (count > 0)
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: const BoxDecoration(
                color: LHColors.erreur, shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 9.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
    ]);
  }
}

/// Logo officiel LifeHelm 2026 — emblème phare & boussole dorée (kit de
/// marque favicon_lifehelm). Un seul visuel pour les deux thèmes : l'or et
/// le marine restent parfaitement lisibles sur fond ivoire comme sur fond
/// bleu nuit (contraste validé). Source : assets/brand/logo-lifehelm.png.
class HelmMark extends StatelessWidget {
  const HelmMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo-lifehelm.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.explore_rounded, size: size * 0.7, color: LHColors.or),
    );
  }
}

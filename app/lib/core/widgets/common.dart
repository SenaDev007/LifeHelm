import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ══════════════════════════ CARTES & SECTIONS ══════════════════════════

/// Carte LifeHelm : surface, bordure fine, rayon généreux.
class LHCard extends StatelessWidget {
  const LHCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LHSpacing.lg),
    this.accent, // barre d'accent verticale (ex. or / émeraude)
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LHRadius.lg),
        side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LHRadius.lg),
        child: Stack(children: [
          // Barre d'accent verticale (or / émeraude…), sans imposer
          // de contraintes de hauteur aux enfants.
          if (accent != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 3.5,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          Padding(
            padding: accent != null
                ? padding.copyWith(left: padding.left + 10)
                : padding,
            child: child,
          ),
        ]),
      ),
    );
  }
}

/// En-tête de section : surline dorée + titre Manrope.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.overline});

  final String title;
  final String? overline;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: 2, right: 2, top: LHSpacing.xl, bottom: LHSpacing.md),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (overline != null)
              Text(overline!.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: theme.brightness == Brightness.dark
                          ? LHColors.or
                          : LHColors.orDeep)),
            const SizedBox(height: 2),
            Text(title, style: theme.textTheme.titleLarge),
          ]),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

/// État vide : icône + message + action optionnelle.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LHSpacing.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: LHSpacing.md),
          Text(message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          if (hint != null) ...[
            const SizedBox(height: LHSpacing.xs),
            Text(hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[
            const SizedBox(height: LHSpacing.lg),
            action!,
          ],
        ]),
      ),
    );
  }
}

// ══════════════════════════ BADGES & PUCES ══════════════════════════

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration:
          BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Puce de statut colorée (tâches, projets, objectifs, événements…).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color,
      this.small = false, this.outlined = false});

  final String label;
  final Color color;
  final bool small;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: outlined ? null : color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(LHRadius.full),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Dot(color, size: small ? 6 : 7),
        const SizedBox(width: 6),
        Text(label,
            style: (small ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Pastille de compte (avatar initiales).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.color, this.size = 40});

  final String name;
  final Color? color;
  final double size;

  String _initials(String n) {
    final parts =
        n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? LHColors.or;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        border: Border.all(color: c.withValues(alpha: 0.55)),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(_initials(name),
          style: TextStyle(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36,
              fontFamily: LHFonts.titres)),
    );
  }
}

/// Anneau de progression (or sur piste sombre).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.progress, this.size = 44,
      this.stroke = 4, this.color, this.child});

  final double progress; // 0..1
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ??
        (theme.brightness == Brightness.dark ? LHColors.or : LHColors.orDeep);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: stroke,
            color: c,
            backgroundColor:
                theme.colorScheme.outline.withValues(alpha: 0.5),
            strokeCap: StrokeCap.round,
          ),
        ),
        if (child != null) child!,
      ]),
    );
  }
}

/// Barre de progression fine avec seuil d'alerte.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.ratio, this.alertRatio = 0.8});

  final double ratio;
  final double alertRatio;

  @override
  Widget build(BuildContext context) {
    final clamped = ratio.clamp(0.0, 1.0);
    final Color c = ratio >= 1.0
        ? LHColors.erreur
        : ratio >= alertRatio
            ? LHColors.alerte
            : LHColors.emeraudeClair;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LHRadius.full),
      child: SizedBox(
        height: 7,
        child: Stack(children: [
          Container(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
          FractionallySizedBox(
            widthFactor: clamped,
            child: Container(color: c),
          ),
        ]),
      ),
    );
  }
}

/// Titre « statistique » : valeur large + libellé.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value,
      this.color, this.icon});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
        ],
        Expanded(child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      ]),
      const SizedBox(height: 3),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w800)),
    ]);
  }
}

// ══════════════════════════ CHAMPS ══════════════════════════

/// Champ libellé : surline + enfant (DropDown, TextField, picker…).
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      child,
    ]);
  }
}

/// Sélecteur de segments style segments iOS/Android harmonisés.
class LhSegmented<T> extends StatelessWidget {
  const LhSegmented({super.key, required this.value, required this.items,
      required this.onChanged});

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.outline.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(LHRadius.md),
      ),
      child: Row(children: [
        for (final entry in items.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: entry.key == value
                      ? (theme.brightness == Brightness.dark
                          ? LHColors.or
                          : LHColors.orDeep)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(LHRadius.sm + 1),
                ),
                alignment: Alignment.center,
                child: Text(entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: entry.key == value
                          ? (theme.brightness == Brightness.dark
                              ? LHColors.noir
                              : Colors.white)
                          : theme.colorScheme.onSurfaceVariant,
                    )),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Feuille de confirmation standard.
Future<bool> lhConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmer',
  bool destructive = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: LHColors.erreur)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Petit SnackBar harmonisé.
void lhToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ══════════════════════════ ESPACES ══════════════════════════

Color spaceColor(String type) {
  switch (type) {
    case 'FAMILY':
      return LHColors.espaceFamille;
    case 'PROFESSIONAL':
      return LHColors.espacePro;
    default:
      return LHColors.espacePerso;
  }
}

String spaceTypeLabel(String type) {
  switch (type) {
    case 'FAMILY':
      return 'Espace familial';
    case 'PROFESSIONAL':
      return 'Espace professionnel';
    default:
      return 'Espace personnel';
  }
}

IconData spaceIcon(String type) {
  switch (type) {
    case 'FAMILY':
      return Icons.family_restroom;
    case 'PROFESSIONAL':
      return Icons.work_outline;
    default:
      return Icons.person_outline;
  }
}

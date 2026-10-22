import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

/// Bouclier anti-crash.
///
/// Avant : toute exception de construction remplaçait l'écran par la page
/// grise technique de Flutter (« package:flutter/src/… Failed assertion … »),
/// sans aucune issue pour l'utilisateur.
///
/// Après : un écran de récupération soigné — message simple, données
/// intactes, bouton « Reprendre » qui ramène au tableau de bord (le
/// sous-arbre fautif est reconstruit au passage), et le détail technique
/// repliable pour le signalement.
abstract final class ErrorShield {
  static void install() {
    // Erreurs asynchrones non attrapées par le framework : loguées,
    // l'application continue de tourner.
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('LifeHelm [erreur non capturée] : $error\n$stack');
      return true;
    };

    // Écran de récupération à la place du gris technique.
    ErrorWidget.builder = (details) {
      debugPrint('LifeHelm [erreur de rendu] : ${details.exception}');
      return _RecoveryScreen(error: details.exception);
    };
  }
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen({required this.error});

  final Object error;

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  bool _showDetails = false;

  void _recover(BuildContext context) {
    // Retour au tableau de bord : la navigation reconstruit le sous-arbre
    // fautif. Défensif à double niveau (routeur, puis navigateur nu).
    try {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go('/');
        return;
      }
    } catch (_) {}
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.error.toString();
    final firstLine = details.split('\n').first;
    return Material(
      color: LHColors.ivoire,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: LHColors.orTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 34, color: LHColors.orDeep),
              ),
              const SizedBox(height: 16),
              const Text(
                'Petit accroc d’affichage',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: LHColors.navyInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cette vue n’a pas pu s’afficher complètement. '
                'Vos données sont intactes — reprenez là où vous étiez.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: LHColors.ardoise),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _recover(context),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Reprendre'),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Text(
                  _showDetails ? 'Masquer le détail' : 'Afficher le détail',
                  style: const TextStyle(
                      fontSize: 12,
                      color: LHColors.electrique,
                      decoration: TextDecoration.underline),
                ),
              ),
              if (_showDetails) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LHColors.ivoireElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      details,
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: LHColors.ardoise),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Signalez « $firstLine » si le problème persiste.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: LHColors.neutre),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

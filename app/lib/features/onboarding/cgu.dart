import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

// ═══════════════════════════ CONDITIONS GÉNÉRALES D'UTILISATION ═══════════════════════════

/// Conditions Générales d'Utilisation de LifeHelm — document intégral,
/// présenté dans une feuille plein écran lisible et hiérarchisée.
class CguScreen extends StatelessWidget {
  const CguScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Conditions Générales d\'Utilisation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.md, LHSpacing.screen, 40),
        children: [
          Text('Conditions Générales d\'Utilisation',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: LHSpacing.sm),
          Text(
            'Application LifeHelm — Life Management System\n'
            'Édité par YEYO TECH\n'
            'Dernière mise à jour : octobre 2026',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.6),
          ),
          const Divider(height: LHSpacing.xl),
          for (final article in _articles)
            Padding(
              padding: const EdgeInsets.only(bottom: LHSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(article.$1,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: LHSpacing.sm),
                  for (final p in article.$2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LHSpacing.sm),
                      child: Text(p,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.65)),
                    ),
                ],
              ),
            ),
          SectionHeader('Contact', overline: 'YEYO TECH'),
          Text(
            'Pour toute question relative aux présentes conditions : '
            'support@yeyotech.com. Nous nous engageons à répondre à toute '
            'sollicitation dans un délai raisonnable et à vous accompagner '
            'dans l\'exercice de vos droits.',
            style:
                theme.textTheme.bodyMedium?.copyWith(height: 1.65),
          ),
        ],
      ),
    );
  }
}

/// Articles des CGU — (titre, paragraphes).
const List<(String, List<String>)> _articles = [
  (
    'Article 1 — Objet et acceptation',
    [
      'Les présentes Conditions Générales d\'Utilisation (ci-après « les CGU ») '
      'encadrent l\'accès et l\'utilisation de l\'application mobile LifeHelm '
      '(ci-après « l\'Application »), éditée par YEYO TECH (ci-après « l\'Éditeur »). '
      'LifeHelm est un système de gestion de vie personnel et professionnel : '
      'tâches, agenda, finances, budgets, prêts et emprunts, notes, projets, '
      'habitudes, bien-être, carrière, contacts et messagerie.',
      'En créant un compte, en vous connectant ou en utilisant simplement '
      'l\'Application, vous reconnaissez avoir lu, compris et accepté '
      'l\'intégralité des présentes CGU. Si vous n\'acceptez pas tout ou partie '
      'de ces conditions, vous ne devez pas utiliser l\'Application.',
    ],
  ),
  (
    'Article 2 — Description du service',
    [
      'LifeHelm est conçue selon le principe « hors ligne d\'abord » : vos '
      'données sont enregistrées sur votre appareil et restent accessibles '
      'sans connexion Internet. La création d\'un compte active une '
      'sauvegarde en ligne chiffrée et une synchronisation multi-appareils '
      'de vos espaces de vie : Personnel, Famille et Professionnel.',
      'L\'Application manipère des données strictement personnelles et ne '
      'constitue en aucun cas un service bancaire, financier, d\'investissement, '
      'de conseil juridique, médical ou comptable. Les montants, budgets, '
      'recettes et dépenses que vous saisissez le sont à titre informatif, '
      'pour votre organisation personnelle.',
    ],
  ),
  (
    'Article 3 — Inscription et compte utilisateur',
    [
      'La création d\'un compte exige au minimum une adresse électronique ou '
      'un numéro de téléphone, votre prénom et un mot de passe d\'au moins '
      'huit caractères. Vous vous engagez à fournir des informations exactes, '
      'à jour, et à garder votre mot de passe strictement confidentiel.',
      'Vous êtes seul responsable des activités réalisées depuis votre compte. '
      'En cas de perte de votre mot de passe, une procédure de réinitialisation '
      'est disponible ; les questions de sécurité que vous aurez définies '
      'peuvent vous permettre de récupérer l\'accès à vos données.',
      'Vous pouvez à tout moment modifier votre profil, changer votre mot de '
      'passe, consulter et gérer vos sessions connectées, ou supprimer '
      'définitivement votre compte depuis l\'écran « Mon profil ». La '
      'suppression du compte efface de manière irréversible vos données '
      'synchronisées sur nos serveurs.',
    ],
  ),
  (
    'Article 4 — Données personnelles et confidentialité',
    [
      'L\'Éditeur applique une politique de minimisation : seules les données '
      'strictement nécessaires au fonctionnement du service sont collectées '
      '(identité, coordonnées, préférences et contenus que vous créez). Vos '
      'contenus sont stockés de façon chiffrée en transit et protégés en repos.',
      'Vos données ne sont ni vendues, ni louées, ni partagées à des tiers à '
      'des fins commerciales. Les espaces Familiaux et Professionnels reposent '
      'sur des permissions explicites : rien n\'est partagé sans votre action '
      'délibérée, et vous pouvez révoquer un accès à tout moment.',
      'Conformément à la réglementation applicable en matière de protection '
      'des données, vous disposez d\'un droit d\'accès, de rectification, '
      'd\'export, d\'effacement et d\'opposition. Ces droits s\'exercent '
      'directement depuis l\'Application ou par écrit à l\'adresse de contact '
      'de l\'Éditeur.',
    ],
  ),
  (
    'Article 5 — Engagements de l\'utilisateur',
    [
      'Vous vous engagez à utiliser l\'Application de manière loyale et '
      'conforme à sa destination, à ne pas tenter d\'en perturber le '
      'fonctionnement, à ne pas accéder frauduleusement aux données d\'autrui '
      'ni à contourner les mécanismes d\'authentification et de permissions.',
      'Vous restez seul propriétaire et responsable des contenus que vous '
      'saisissez. Il vous appartient de ne pas consigner dans l\'Application '
      'des informations dont la conservation serait contraire à la loi.',
    ],
  ),
  (
    'Article 6 — Disponibilité et évolution du service',
    [
      'L\'Éditeur s\'efforce de maintenir l\'Application accessible et à jour. '
      'La sauvegarde en ligne peut être ponctuellement interrompue pour '
      'maintenance ; votre usage hors ligne et vos données locales ne sont '
      'pas affectés par ces interruptions.',
      'L\'Éditeur se réserve le droit de faire évoluer l\'Application et les '
      'fonctionnalités proposées. Les évolutions substantielles des CGU vous '
      'seront notifiées dans l\'Application ; la poursuite de l\'utilisation '
      'après notification vaut acceptation des conditions révisées.',
    ],
  ),
  (
    'Article 7 — Propriété intellectuelle',
    [
      'L\'Application, ses contenus éditoriaux, son identité visuelle, son '
      'logo, ses illustrations et ses éléments d\'interface sont protégés par '
      'le droit de la propriété intellectuelle et demeurent la propriété '
      'exclusive de l\'Éditeur. Toute reproduction, représentation ou '
      'adaptation non autorisée est interdite.',
      'Vous conservez l\'intégralité des droits sur vos propres contenus ; '
      'l\'Éditeur ne les utilise que pour exécuter le service de sauvegarde '
      'et de synchronisation que vous avez activé.',
    ],
  ),
  (
    'Article 8 — Limitation de responsabilité',
    [
      'L\'Application est fournie « en l\'état ». L\'Éditeur ne garantit pas '
      'l\'absence d\'erreurs ou d\'interruptions et sa responsabilité ne '
      'saurait être engagée au titre des décisions financières, budgétaires '
      'ou de toute autre nature que vous prendriez sur la base des '
      'informations que vous y consignez.',
      'Sauf faute lourde ou dolosive, la responsabilité de l\'Éditeur est '
      'limitée aux dommages directs, personnels et certains, dans la limite '
      'des sommes effectivement versées par vous au titre du service au cours '
      'des douze mois précédant le fait générateur.',
    ],
  ),
  (
    'Article 9 — Droit applicable et litiges',
    [
      'Les présentes CGU sont soumises au droit applicable dans le pays de '
      'résidence de l\'Éditeur. En cas de litige, les parties s\'engagent à '
      'rechercher en priorité une solution amiable. À défaut d\'accord, le '
      'litige sera porté devant les juridictions compétentes selon les règles '
      'de droit commun.',
    ],
  ),
];

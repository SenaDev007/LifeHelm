import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' show bootState;
import '../../core/net/api_client.dart';
import '../../core/net/sync_service.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart';
import '../auth/auth.dart';

/// Onboarding en 5 écrans : présentation, espaces, hors ligne, prénom,
/// sauvegarde multi-appareils (D01.2). Aucun compte requis ; aucune donnée
/// de démonstration n'est créée — l'application démarre vide et propre.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  final _nameController = TextEditingController();
  int _page = 0;
  bool _busy = false;
  bool _spacesCreated = false;
  String _ownerName = 'Vous';

  static const _pagesCount = 5;

  late final AnimationController _logoAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _logoAnim.dispose();
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Crée les espaces et les fondations (une seule fois) — SANS données de
  /// démonstration. Conserve le prénom pour la salutation du cockpit.
  Future<void> _createSpaces() async {
    if (_spacesCreated) return;
    setState(() => _busy = true);
    final db = ref.read(dbProvider);
    _ownerName = _nameController.text.trim().isEmpty
        ? 'Vous'
        : _nameController.text.trim();
    await db.initializeDefaultSpaces(ownerName: _ownerName);
    await db.maintenanceScan();
    await ref.read(activeSpaceIdProvider.notifier).reload();
    await db.setSetting('ownerName', _ownerName);
    _spacesCreated = true;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    await _createSpaces();
    bootState.onboarded = true;
    if (mounted) context.go('/');
  }

  /// « Passer » : saute les présentations vers le prénom, puis termine.
  Future<void> _skip() async {
    if (_page < 3) {
      _controller.jumpToPage(3);
    } else {
      await _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(children: [
              const SizedBox(width: 56),
              const Spacer(),
              Row(children: [
                for (var i = 0; i < _pagesCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? (isDark ? LHColors.or : LHColors.orDeep)
                          : theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ]),
              const Spacer(),
              SizedBox(
                width: 56,
                child: _page < _pagesCount - 1
                    ? TextButton(
                        onPressed: _skip, child: const Text('Passer'))
                    : null,
              ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _page1(context),
                _page2(context),
                _page3(context),
                _page4(context),
                _page5(context),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════ PAGE 1 — BIENVENUE YEYO TECH ══════════════════════

  /// Accueil : message de bienvenue de YEYO TECH, création de compte ou
  /// connexion en un geste — ou découverte locale en toute discrétion.
  Widget _page1(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final or = isDark ? LHColors.or : LHColors.orDeep;
    final connected = ref.watch(sessionProvider).isConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(children: [
        const SizedBox(height: LHSpacing.xl),
        // Logo animé : entrée scale + fondu + lueur or.
        ScaleTransition(
          scale: CurvedAnimation(
              parent: _logoAnim, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _logoAnim, curve: Curves.easeOut),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: LHColors.or.withValues(alpha: 0.30),
                    blurRadius: 70,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const HelmMark(size: 150),
            ),
          ),
        ),
        const SizedBox(height: LHSpacing.xl),
        Text('Bienvenue sur LifeHelm',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.sm),
        Text('Votre vie, un seul gouvernail.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: LHSpacing.md),
        // Message de bienvenue signé YEYO TECH.
        Container(
          padding: const EdgeInsets.all(LHSpacing.lg),
          decoration: BoxDecoration(
            color: or.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(LHRadius.lg),
            border: Border.all(color: or.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            Text('Un mot de notre équipe',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: or)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              '« Bienvenue ! Toute l\'équipe de YEYO TECH vous remercie de '
              'choisir LifeHelm. Nous avons conçu cette application pour que '
              'vous pilotiez vos journées, vos finances et vos projets avec '
              'élégance — où que vous soyez, même sans réseau. Bonne '
              'découverte ! »',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            const SizedBox(height: LHSpacing.sm),
            Text('— YEYO TECH',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: or)),
          ]),
        ),
        const SizedBox(height: LHSpacing.lg),
        LHIllustration(asset: 'assets/illustrations/onboard-welcome.png'),
        const SizedBox(height: LHSpacing.xl),
        if (connected) ...[
          Icon(Icons.cloud_done_outlined, color: LHColors.emeraudeClair,
              size: 32),
          const SizedBox(height: LHSpacing.sm),
          Text('Compte connecté — la sauvegarde est active.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: LHColors.emeraudeClair)),
          const SizedBox(height: LHSpacing.md),
          FilledButton(
            onPressed: _busy ? null : _finish,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Commencer'),
          ),
        ] else ...[
          // Création de compte — parcours complet guidé.
          FilledButton.icon(
            onPressed: _busy ? null : () => _openRegister(),
            icon: const Icon(Icons.person_add_alt_rounded, size: 20),
            label: const Text('Créer mon compte'),
          ),
          const SizedBox(height: LHSpacing.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openLogin(),
            icon: const Icon(Icons.login_rounded, size: 20),
            label: const Text('Se connecter'),
          ),
          const SizedBox(height: LHSpacing.md),
          TextButton(
            onPressed: () => _controller.nextPage(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic),
            child: const Text('Découvrir d\'abord l\'application'),
          ),
        ],
        const SizedBox(height: LHSpacing.lg),
      ]),
    );
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const RegisterScreen()));
    if (!mounted) return;
    if (ref.read(sessionProvider).isConnected) {
      ref.read(syncControllerProvider).syncNow();
      await _finish();
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const LoginScreen()));
    if (!mounted) return;
    if (ref.read(sessionProvider).isConnected) {
      ref.read(syncControllerProvider).syncNow();
      await _finish();
    }
  }

  Widget _feature(ThemeData theme, IconData icon, Color color, String title,
      String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LHSpacing.sm),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(LHRadius.md),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: LHSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  // ══════════════════════ PAGE 2 — ESPACES ══════════════════════

  Widget _page2(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(children: [
        const SizedBox(height: LHSpacing.lg),
        LHIllustration(asset: 'assets/illustrations/onboard-spaces.png'),
        const SizedBox(height: LHSpacing.xl),
        Text('Trois espaces, une application',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.sm),
        Text(
            'Chaque espace est totalement isolé : ses tâches, son budget, '
            'ses notes. Passez de l\'un à l\'autre en un geste.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: LHSpacing.xl),
        _spaceCard(theme, LHColors.espacePerso, Icons.person_outline,
            'Personnel', 'Votre vie privée : objectifs, budget, bien-être.'),
        const SizedBox(height: LHSpacing.md),
        _spaceCard(theme, LHColors.espaceFamille, Icons.family_restroom,
            'Famille', 'Courses, écolage, échéances et responsabilités communes.'),
        const SizedBox(height: LHSpacing.md),
        _spaceCard(theme, LHColors.espacePro, Icons.work_outline,
            'Professionnel', 'Clients, projets et finances d\'activité — séparés du reste.'),
      ]),
    );
  }

  Widget _spaceCard(ThemeData theme, Color color, IconData icon, String title,
      String subtitle) {
    return Container(
      padding: const EdgeInsets.all(LHSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(LHRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(LHRadius.md)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: LHSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  // ══════════════════════ PAGE 3 — HORS LIGNE ══════════════════════

  Widget _page3(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(children: [
        const SizedBox(height: LHSpacing.lg),
        LHIllustration(asset: 'assets/illustrations/onboard-offline.png'),
        const SizedBox(height: LHSpacing.xl),
        Text('Pensé pour le hors ligne',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.md),
        Text(
          'LifeHelm fonctionne d\'abord sur votre appareil. '
          'Chaque modification est enregistrée localement et synchronisée '
          'dès le retour du réseau — rien n\'est perdu, jamais.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: LHSpacing.xl),
        _feature(theme, Icons.currency_exchange, LHColors.or, 'FCFA (XOF) par défaut',
            'Le franc CFA est la devise de référence ; conversion explicite pour les autres devises.'),
        _feature(theme, Icons.smartphone_rounded, LHColors.espacePro,
            'Mobile Money intégré',
            'Suivez vos comptes espèces, bancaires et Mobile Money au même endroit.'),
        _feature(theme, Icons.lock_outline, LHColors.espaceFamille,
            'Vie privée d\'abord',
            'Aucune donnée ne quitte l\'appareil sans votre accord explicite.'),
      ]),
    );
  }

  // ══════════════════════ PAGE 4 — PRÉNOM ══════════════════════

  Widget _page4(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: LHSpacing.xxl),
        Text('Personnalisons un peu',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.sm),
        Text('Votre application démarre vide et propre — à vous de la remplir.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: LHSpacing.xxl),
        LabeledField(
          label: 'Votre prénom (optionnel)',
          child: TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                hintText: 'Ex. : Awa', prefixIcon: Icon(Icons.person_outline)),
          ),
        ),
        const SizedBox(height: LHSpacing.xl),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  await _createSpaces();
                  if (mounted) _controller.jumpToPage(4);
                },
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continuer'),
        ),
      ]),
    );
  }

  // ══════════════════════ PAGE 5 — DERNIÈRE ÉTAPE ══════════════════════

  /// Dernier écran : compte créé/connecté en page 1 ou usage local —
  /// l'application se prépare et démarre vide et propre.
  Widget _page5(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final or = isDark ? LHColors.or : LHColors.orDeep;
    final connected = ref.watch(sessionProvider).isConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: LHSpacing.xl),
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (connected ? LHColors.emeraudeClair : or)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                connected
                    ? Icons.cloud_done_outlined
                    : Icons.rocket_launch_outlined,
                size: 44,
                color: connected ? LHColors.emeraudeClair : or,
              ),
            ),
            const SizedBox(height: LHSpacing.lg),
            Text('Tout est prêt',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              connected
                  ? 'Votre compte est actif : vos espaces seront sauvegardés '
                      'et synchronisés sur tous vos appareils.'
                  : 'LifeHelm démarre vide et propre, sans aucune donnée '
                      'd\'exemple. Vous pourrez activer un compte à tout moment '
                      'depuis l\'onglet Plus.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: LHSpacing.xl),
            if (!connected)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openRegister(),
                  icon: const Icon(Icons.person_add_alt_outlined, size: 20),
                  label: const Text('Créer un compte maintenant'),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _finish,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Commencer'),
            ),
          ]),
    );
  }
}

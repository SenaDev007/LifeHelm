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

/// Onboarding en 3 écrans + configuration initiale (D01.2).
/// Aucun compte requis : les données restent locales (offline-first).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _nameController = TextEditingController();
  int _page = 0;
  bool _demoData = true;
  bool _busy = false;
  bool _spacesCreated = false;
  String _ownerName = 'Vous';
  bool _laterNotice = true; // coche informative de l'option locale

  static const _pagesCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Crée les espaces et les fondations (une seule fois) — conserve le
  /// prénom saisi pour la salutation du cockpit (réglage `ownerName`).
  Future<void> _createSpaces() async {
    if (_spacesCreated) return;
    setState(() => _busy = true);
    final db = ref.read(dbProvider);
    _ownerName = _nameController.text.trim().isEmpty
        ? 'Vous'
        : _nameController.text.trim();
    await db.initializeDefaultSpaces(ownerName: _ownerName);
    if (_demoData) {
      await db.seedDemoData();
    }
    await db.maintenanceScan();
    await ref.read(activeSpaceIdProvider.notifier).reload();
    // FIX : le cockpit salue l'utilisateur par son prénom (ownerName).
    await db.setSetting('ownerName', _ownerName);
    _spacesCreated = true;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    await _createSpaces();
    bootState.onboarded = true;
    if (mounted) context.go('/');
  }

  /// « Passer » : saute les présentations vers le dernier réglage, puis
  /// saute AUSSI l'étape de sauvegarde (reste local, défaut recommandé).
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
                        onPressed: _skip,
                        child: const Text('Passer'))
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

  Widget _page1(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(children: [
        const SizedBox(height: LHSpacing.xl),
        const HelmMark(size: 88),
        const SizedBox(height: LHSpacing.xl),
        Text('LifeHelm',
            style: theme.textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.sm),
        Text('Votre vie, un seul gouvernail.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: LHSpacing.xxl),
        _feature(theme, Icons.checklist_rounded, LHColors.or,
            'Tâches, agenda et projets', 'Chaque domaine à sa place, reliés sans confusion.'),
        _feature(theme, Icons.account_balance_wallet_rounded, LHColors.emeraudeClair,
            'Finances XOF & multi-devises', 'Espèces, banque, Mobile Money — même hors ligne.'),
        _feature(theme, Icons.nightlight_round, LHColors.info,
            'Confidentiel et hors ligne', 'Vos données restent sur votre appareil.'),
      ]),
    );
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

  Widget _page2(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(children: [
        const SizedBox(height: LHSpacing.xl),
        Text('Trois espaces, une application',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.sm),
        Text('Les données sont isolées par espace, sauf partage explicite.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: LHSpacing.xl),
        _spaceCard(theme, LHColors.espacePerso, Icons.person_outline,
            'Personnel', 'Votre vie privée : tâches, budget, bien-être, objectifs.'),
        const SizedBox(height: LHSpacing.md),
        _spaceCard(theme, LHColors.espaceFamille, Icons.family_restroom,
            'Famille', 'Responsabilités partagées : courses, écolage, échéances communes.'),
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

  Widget _page3(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(children: [
        const SizedBox(height: LHSpacing.xl),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: LHColors.emeraudeClair.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.cloud_off_outlined,
              size: 42, color: LHColors.emeraudeClair),
        ),
        const SizedBox(height: LHSpacing.xl),
        Text('Pensé pour le hors ligne',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.md),
        Text(
          'LifeHelm fonctionne d\'abord sur votre appareil. '
          'Chaque modification est enregistrée localement et journalisée '
          'en attente de synchronisation — rien n\'est perdu, même sans réseau.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: LHSpacing.xl),
        _feature(theme, Icons.currency_exchange, LHColors.or, 'XOF par défaut',
            'Le franc CFA est la devise de référence ; les autres devises sont converties explicitement.'),
        _feature(theme, Icons.lock_outline, LHColors.espaceFamille,
            'Permissions d\'abord', 'Les espaces personnels restent privés par défaut.'),
      ]),
    );
  }

  Widget _page4(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: LHSpacing.lg),
        Text('Dernier réglage',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.xl),
        LabeledField(
          label: 'Votre prénom (optionnel)',
          child: TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                hintText: 'Ex. : Awa', prefixIcon: Icon(Icons.person_outline)),
          ),
        ),
        const SizedBox(height: LHSpacing.lg),
        LHCard(
          onTap: () => setState(() => _demoData = !_demoData),
          child: Row(children: [
            Icon(_demoData ? Icons.check_box_rounded : Icons.check_box_outline_blank,
                color: _demoData
                    ? LHColors.emeraudeClair
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Charger des données d\'exemple',
                    style: theme.textTheme.titleSmall),
                Text(
                  'Comptes, tâches, budget, habitudes… pour explorer l\'application immédiatement.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: LHSpacing.xl),
        FilledButton(
          onPressed: _busy ? null : () async {
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

  /// Étape « Sauvegarde multi-appareils » : créer un compte OU rester local.
  /// Aucun des deux choix ne bloque — la synchro est optionnelle (CDC §3).
  Widget _page5(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final or = isDark ? LHColors.or : LHColors.orDeep;
    final connected = ref.watch(sessionProvider).isConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: LHSpacing.lg),
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: or.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.devices_outlined, size: 38, color: or),
            ),
            const SizedBox(height: LHSpacing.lg),
            Text('Sauvegarde multi-appareils',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'Créez un compte pour retrouver vos espaces sur vos autres appareils. '
              'Vos données restent sur cet appareil tant que vous n\'activez pas la synchronisation.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: LHSpacing.xl),
            // Choix 1 — créer un compte maintenant
            LHCard(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const RegisterScreen()));
                if (!mounted) return;
                if (ref.read(sessionProvider).isConnected) {
                  // Compte créé : synchronisation initiale puis accueil.
                  ref.read(syncControllerProvider).syncNow();
                  await _finish();
                }
              },
              accent: or,
              child: Row(children: [
                Icon(Icons.person_add_alt_outlined, color: or),
                const SizedBox(width: LHSpacing.md),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Créer un compte',
                            style: theme.textTheme.titleMedium),
                        Text(
                            'Sauvegarde en ligne dès maintenant',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: LHSpacing.md),
            // Choix 2 — rester local (défaut recommandé)
            LHCard(
              onTap: _finish,
              accent: LHColors.emeraudeClair,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.cloud_off_outlined,
                          color: LHColors.emeraudeClair),
                      const SizedBox(width: LHSpacing.md),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Expanded(
                                  child: Text('Plus tard, rester local',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                                StatusChip(
                                  label: 'Recommandé',
                                  color: isDark
                                      ? LHColors.or
                                      : LHColors.orDeep,
                                  small: true,
                                ),
                              ]),
                              Text(
                                  'Tout fonctionne sans compte',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant)),
                            ]),
                      ),
                    ]),
                    const SizedBox(height: LHSpacing.md),
                    InkWell(
                      onTap: () =>
                          setState(() => _laterNotice = !_laterNotice),
                      borderRadius: BorderRadius.circular(LHRadius.sm),
                      child: Row(children: [
                        Icon(
                          _laterNotice
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: _laterNotice
                              ? LHColors.emeraudeClair
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: LHSpacing.sm),
                        Expanded(
                          child: Text(
                            'Je peux activer la synchronisation plus tard dans l\'onglet Plus',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ]),
                    ),
                  ]),
            ),
            const SizedBox(height: LHSpacing.lg),
            if (connected)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(
                  'Compte connecté — la synchronisation démarre automatiquement.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: LHColors.emeraudeClair),
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

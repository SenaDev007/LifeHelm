import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/net/api_client.dart';
import '../../core/net/sync_service.dart';
import '../../core/providers.dart';
import '../../core/taxonomy.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../main.dart' show bootState;
import '../../shell/widgets.dart' show HelmMark;
import '../onboarding/cgu.dart';

// ══════════════════════════ SOCLES COMMUNS ══════════════════════════

/// Hachage sha256 d'une réponse de sécurité (normalisée : trim + minuscules).
/// Identique côté profil (enregistrement) et récupération (vérification).
String sha256Hash(String answer) =>
    sha256.convert(utf8.encode(answer.trim().toLowerCase())).toString();

/// Écran d'authentification plein écran : marque + carte + formulaire.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Compte LifeHelm')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: LHSpacing.xl, vertical: LHSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: HelmMark(size: 56)),
                  const SizedBox(height: LHSpacing.lg),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: LHSpacing.sm),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5)),
                  const SizedBox(height: LHSpacing.xl),
                  child,
                  if (footer != null) ...[
                    const SizedBox(height: LHSpacing.lg),
                    footer!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau d'erreur serveur (français).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: LHSpacing.md),
      padding: const EdgeInsets.all(LHSpacing.md),
      decoration: BoxDecoration(
        color: LHColors.erreur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LHRadius.md),
        border: Border.all(color: LHColors.erreur.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: LHColors.erreur, size: 20),
        const SizedBox(width: LHSpacing.md),
        Expanded(
          child: Text(message!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: LHColors.erreur)),
        ),
      ]),
    );
  }
}

/// Succès d'authentification partagé login/register : session persistée +
/// snackbar de bienvenue + synchronisation initiale. À appeler depuis un
/// State (le snackbar utilise le contexte de l'État, garde `mounted`).
extension AuthSuccessState on ConsumerState {
  Future<void> _persistSessionAndWelcome(
      WidgetRef ref, LhAuthResult result) async {
    await ref.read(tokenStoreProvider).save(result.toSession());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(
              'Bienvenue, ${result.user.firstName.isEmpty ? 'vous' : result.user.firstName} !')));
    // Synchronisation initiale : push de la file locale puis pull serveur.
    ref.read(syncControllerProvider).syncNow();
  }
}

// ══════════════════════════ CONNEXION ══════════════════════════

/// Connexion : courriel ou téléphone + mot de passe (+ TOTP si 2FA active).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.loggedOut = false});

  /// Vrai quand on arrive depuis une déconnexion : affiche un bandeau
  /// informatif et l'option « continuer sans compte ».
  final bool loggedOut;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _totp = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _totpRequired = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty || _password.text.isEmpty) {
      setState(
          () => _error = 'Renseignez votre identifiant et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).login(
            identifier: identifier,
            password: _password.text,
            totpCode: _totpRequired && _totp.text.trim().isNotEmpty
                ? _totp.text.trim()
                : null,
          );
      await _persistSessionAndWelcome(ref, result);
      if (!mounted) return;
      // Retour fiable : pop si un écran attend dessous, sinon accueil.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/');
      }
    } on LhApiException catch (e) {
      setState(() {
        if (e.statusCode == 428 || e.code == 'TOTP_REQUIRED') {
          _totpRequired = true;
          _error =
              'Double authentification active — saisissez le code à 6 chiffres.';
        } else {
          _error = apiErrorText(e);
        }
      });
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (e) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Se connecter',
      subtitle:
          'Activez la sauvegarde multi-appareils de vos espaces LifeHelm.',
      footer: Column(children: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ForgotPasswordScreen())),
          child: const Text('Mot de passe oublié ?'),
        ),
        // Sortie propre pour les installations déjà configurées : l'app
        // reste utilisable sans compte (hors ligne) — on ne bloque personne.
        if (bootState.onboarded)
          TextButton(
            onPressed: _busy ? null : () => context.go('/'),
            child: const Text('Continuer sans compte'),
          ),
      ]),
      child: LHCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.loggedOut) ...[
              Container(
                padding: const EdgeInsets.all(LHSpacing.md),
                decoration: BoxDecoration(
                    color: LHColors.emeraudeClair.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(LHRadius.md),
                    border: Border.all(
                        color: LHColors.emeraudeClair.withValues(alpha: 0.4))),
                child: Row(children: [
                  const Icon(Icons.logout,
                      size: 18, color: LHColors.emeraudeClair),
                  const SizedBox(width: LHSpacing.sm),
                  Expanded(
                    child: Text(
                      'Vous êtes déconnecté. Vos données restent sur cet '
                      'appareil — reconnectez-vous pour reprendre la '
                      'synchronisation.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: LHSpacing.md),
            ],
            _ErrorBanner(_error),
            LabeledField(
              label: 'Courriel ou téléphone',
              child: TextField(
                controller: _identifier,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                    hintText: 'awa@exemple.com ou 01 97 12 34 56',
                    prefixIcon: Icon(Icons.alternate_email)),
              ),
            ),
            const SizedBox(height: LHSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Téléphone : numéro local (01 97…) ou avec indicatif (+229…) — '
                'les deux fonctionnent.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Mot de passe',
              child: TextField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Votre mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Afficher' : 'Masquer',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
            ),
            if (_totpRequired) ...[
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Code de vérification (2FA)',
                child: TextField(
                  controller: _totp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      hintText: 'Code à 6 chiffres',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: ''),
                ),
              ),
            ],
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Se connecter'),
            ),
            const SizedBox(height: LHSpacing.md),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Pas encore de compte ?',
                  style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const RegisterScreen())),
                child: const Text('Créer un compte'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ INSCRIPTION (assistant) ══════════════════════════

/// Inscription en six étapes fluides et illustrées : identité, téléphone
/// (tous pays, sélecteur d'indicatif), courriel, profession (liste quasi
/// exhaustive + saisie libre), mot de passe, puis acceptation des
/// Conditions Générales d'Utilisation.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _profession = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  CountryInfo _country = defaultCountry;
  int _step = 0;
  bool _obscure = true;
  bool _acceptedCgu = false;
  bool _busy = false;
  String? _error;

  static const _stepsCount = 6;

  static const _stepData = [
    (
      'Votre identité',
      'Comment devons-nous vous appeler ?',
      'assets/illustrations/onboard-spaces.png',
    ),
    (
      'Votre téléphone',
      'Choisissez votre pays et saisissez votre numéro.',
      'assets/illustrations/contacts.png',
    ),
    (
      'Votre adresse e-mail',
      'Pour sécuriser votre compte et récupérer l\'accès.',
      'assets/illustrations/messaging.png',
    ),
    (
      'Votre profession',
      'Sélectionnez dans la liste ou saisissez librement.',
      'assets/illustrations/career.png',
    ),
    (
      'Votre mot de passe',
      'Au moins 8 caractères, choisissez-le solide.',
      'assets/illustrations/notes.png',
    ),
    (
      'Conditions d\'utilisation',
      'Un dernier instant avant de créer votre compte.',
      'assets/illustrations/onboard-offline.png',
    ),
  ];

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _profession.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _fullPhone => normalizePhoneInput(_phone.text, _country);

  String? _stepError() {
    switch (_step) {
      case 0:
        if (_firstName.text.trim().isEmpty) return 'Le prénom est obligatoire.';
      case 1:
        if (!isPlausiblePhoneInput(_phone.text)) {
          return 'Numéro invalide — chiffres uniquement. L\'indicatif (${_country.dial}) '
              'est déjà sélectionné : tapez par ex. 01 97 12 34 56.';
        }
      case 2:
        final e = _email.text.trim();
        if (e.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e)) {
          return 'Cette adresse e-mail semble invalide.';
        }
      case 4:
        if (_password.text.length < 8) {
          return 'Le mot de passe doit contenir au moins 8 caractères.';
        }
        if (_password.text != _confirm.text) {
          return 'Les deux mots de passe ne correspondent pas.';
        }
      case 5:
        if (!_acceptedCgu) {
          return 'Veuillez accepter les Conditions Générales d\'Utilisation.';
        }
    }
    return null;
  }

  bool get _contactProvided =>
      _fullPhone != null || _email.text.trim().isNotEmpty;

  Future<void> _next() async {
    final err = _stepError();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    if (_step < _stepsCount - 1) {
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    if (!_contactProvided) {
      setState(() =>
          _error = 'Renseignez au moins un numéro de téléphone ou un e-mail.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).register(
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            phone: _fullPhone,
            password: _password.text,
            firstName: _firstName.text.trim(),
            lastName:
                _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
            profession: _profession.text.trim(),
            country: _country.iso,
          );
      await _persistSessionAndWelcome(ref, result);
      // Profession conservée aussi localement (profil hors ligne).
      await ref.read(dbProvider).saveLocalProfile(UserProfileCompanion(
            profession: Value(_profession.text.trim()),
            countryIso: Value(_country.iso),
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (e) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final or = isDark ? LHColors.or : LHColors.orDeep;
    final (title, subtitle, illustration) = _stepData[_step];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer mon compte'),
        leading: BackButton(onPressed: () {
          if (_step > 0) {
            setState(() {
              _step--;
              _error = null;
            });
          } else {
            Navigator.of(context).maybePop();
          }
        }),
      ),
      body: SafeArea(
        child: Column(children: [
          // Progression de l'assistant.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: Row(children: [
              for (var i = 0; i < _stepsCount; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step ? or : theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LHIllustration(asset: illustration, height: 150),
                  const SizedBox(height: LHSpacing.lg),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: LHSpacing.sm),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4)),
                  const SizedBox(height: LHSpacing.xl),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: LHSpacing.md),
                      padding: const EdgeInsets.all(LHSpacing.md),
                      decoration: BoxDecoration(
                        color: LHColors.erreur.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(LHRadius.md),
                        border: Border.all(
                            color: LHColors.erreur.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: LHColors.erreur, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: LHColors.erreur)),
                        ),
                      ]),
                    ),
                  _buildStep(theme),
                  const SizedBox(height: LHSpacing.xl),
                  FilledButton(
                    onPressed: _busy ? null : _next,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_step == _stepsCount - 1
                            ? 'Créer mon compte'
                            : 'Continuer'),
                  ),
                  if (_step == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: LHSpacing.md),
                      child: TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child:
                            const Text('J\'ai déjà un compte — me connecter'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStep(ThemeData theme) {
    switch (_step) {
      case 0:
        return Column(children: [
          Row(children: [
            Expanded(
              child: LabeledField(
                label: 'Prénom *',
                child: TextField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Ex. : Awa',
                      prefixIcon: Icon(Icons.person_outline)),
                ),
              ),
            ),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: LabeledField(
                label: 'Nom',
                child: TextField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Ex. : Diallo'),
                ),
              ),
            ),
          ]),
        ]);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledField(
              label: 'Pays (indicatif)',
              child: CountryPickerField(
                selected: _country,
                onChanged: (c) => setState(() => _country = c),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Numéro de téléphone',
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: _country.iso == 'BJ'
                      ? 'Ex. : 01 97 12 34 56'
                      : 'Ex. : numéro sans indicatif',
                  prefixText: '${_country.dial} ',
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'Sans l\'indicatif (${_country.dial} déjà inclus) — 10 chiffres '
              'au Bénin (ex. 01 97 12 34 56) ou 8 pour l\'ancien format. '
              'Facultatif si vous renseignez un e-mail à l\'étape suivante.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
      case 2:
        return LabeledField(
          label: 'Adresse e-mail',
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'awa@exemple.com',
                prefixIcon: Icon(Icons.alternate_email)),
          ),
        );
      case 3:
        return Column(children: [
          LabeledField(
            label: 'Profession (liste ou saisie libre)',
            child: ProfessionPickerField(controller: _profession),
          ),
          const SizedBox(height: LHSpacing.sm),
          Text(
            'Touchez le chevron pour parcourir les ${allProfessions.length} '
            'métiers du référentiel — ou écrivez librement la vôtre.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]);
      case 4:
        return Column(children: [
          LabeledField(
            label: 'Mot de passe (8 caractères minimum)',
            child: TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Choisissez un mot de passe solide',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Afficher' : 'Masquer',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(height: LHSpacing.md),
          LabeledField(
            label: 'Confirmer le mot de passe',
            child: TextField(
              controller: _confirm,
              obscureText: _obscure,
              onSubmitted: (_) => _next(),
              decoration: const InputDecoration(
                  hintText: 'Répétez le mot de passe',
                  prefixIcon: Icon(Icons.lock_outline)),
            ),
          ),
        ]);
      default:
        return Column(children: [
          InkWell(
            onTap: () => setState(() => _acceptedCgu = !_acceptedCgu),
            borderRadius: BorderRadius.circular(LHRadius.sm),
            child: Row(children: [
              Icon(
                _acceptedCgu
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank,
                color: _acceptedCgu
                    ? (theme.brightness == Brightness.dark
                        ? LHColors.or
                        : LHColors.orDeep)
                    : null,
                size: 22,
              ),
              const SizedBox(width: LHSpacing.sm),
              Expanded(
                child: Text(
                  'J\'ai lu et j\'accepte les Conditions Générales '
                  'd\'Utilisation de LifeHelm.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ]),
          ),
          const SizedBox(height: LHSpacing.md),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CguScreen())),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Lire les Conditions Générales'),
          ),
          const SizedBox(height: LHSpacing.md),
          Text(
            'Vos données restent sur votre appareil tant que la '
            'synchronisation n\'est pas active. Vous pouvez supprimer votre '
            'compte à tout moment depuis votre profil.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ]);
    }
  }
}

// ══════════════════════════ MOT DE PASSE OUBLIÉ ══════════════════════════

enum _RecoveryMode { link, questions }

/// Récupération du compte : par lien envoyé (démo : code affiché) OU par
/// les questions de sécurité définies dans le profil — les réponses
/// correctes ouvrent directement la réinitialisation du mot de passe.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _identifier = TextEditingController();
  final _answers = List.generate(3, (_) => TextEditingController());
  _RecoveryMode _mode = _RecoveryMode.link;

  List<String>? _questions; // questions du compte (mode sécurité)
  String? _resetToken; // jeton obtenu par les réponses correctes
  bool _busy = false;
  String? _error;
  String? _info;
  String? _devToken;

  @override
  void dispose() {
    _identifier.dispose();
    for (final a in _answers) {
      a.dispose();
    }
    super.dispose();
  }

  // ── Mode 1 : lien de réinitialisation ──
  Future<void> _submitLink() async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'Renseignez votre courriel ou votre téléphone.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _devToken = null;
    });
    try {
      final res = await ref.read(apiClientProvider).forgotPassword(identifier);
      final devToken = res['devResetToken'] as String?;
      if (!mounted) return;
      setState(() {
        if (devToken != null && devToken.isNotEmpty) {
          _devToken = devToken;
          _info =
              'Mode démonstration — code de réinitialisation ci-dessous.';
        } else {
          _info =
              'Si un compte existe, un lien de réinitialisation a été envoyé.';
        }
      });
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (e) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Mode 2 : questions de sécurité ──
  Future<void> _loadQuestions() async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'Renseignez d\'abord votre identifiant.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _questions = null;
      _resetToken = null;
    });
    try {
      final qs =
          await ref.read(apiClientProvider).securityQuestionsOf(identifier);
      if (!mounted) return;
      if (qs == null || qs.isEmpty) {
        setState(() =>
            _error = 'Ce compte n\'a pas défini de questions de sécurité. '
                'Utilisez le lien de réinitialisation.');
      } else {
        setState(() => _questions = qs);
      }
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitAnswers() async {
    final identifier = _identifier.text.trim();
    final qs = _questions;
    if (qs == null) return;
    if (_answers.any((a) => a.text.trim().isEmpty)) {
      setState(() => _error = 'Répondez à toutes les questions.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hashes = <int, String>{};
      for (var i = 0; i < qs.length && i < 3; i++) {
        hashes[i] = sha256Hash(_answers[i].text);
      }
      final token = await ref
          .read(apiClientProvider)
          .recoverBySecurityQuestions(identifier, hashes);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _info = 'Réponses vérifiées — définissez votre nouveau mot de passe.';
      });
    } on LhApiException catch (e) {
      setState(() => _error = e.code == 'INVALID_ANSWERS'
          ? 'Les réponses ne correspondent pas. Réessayez.'
          : apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _AuthScaffold(
      title: 'Mot de passe oublié',
      subtitle:
          'Récupérez votre compte par lien envoyé, ou par vos questions de sécurité.',
      child: LHCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ErrorBanner(_error),
            if (_info != null)
              Container(
                margin: const EdgeInsets.only(bottom: LHSpacing.md),
                padding: const EdgeInsets.all(LHSpacing.md),
                decoration: BoxDecoration(
                  color: LHColors.emeraudeClair.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(LHRadius.md),
                  border: Border.all(
                      color: LHColors.emeraudeClair.withValues(alpha: 0.5)),
                ),
                child: Text(_info!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.emeraudeClair)),
              ),
            LhSegmented<_RecoveryMode>(
              value: _mode,
              items: const {
                _RecoveryMode.link: 'Par lien',
                _RecoveryMode.questions: 'Questions de sécurité',
              },
              onChanged: (m) => setState(() {
                _mode = m;
                _error = null;
                _info = null;
                _devToken = null;
                _questions = null;
                _resetToken = null;
              }),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Courriel ou téléphone du compte',
              child: TextField(
                controller: _identifier,
                onSubmitted: (_) => _mode == _RecoveryMode.link
                    ? _submitLink()
                    : _loadQuestions(),
                decoration: const InputDecoration(
                    hintText: 'awa@exemple.com',
                    prefixIcon: Icon(Icons.alternate_email)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),

            // ── Par lien ──
            if (_mode == _RecoveryMode.link) ...[
              if (_devToken != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: LHSpacing.md),
                  padding: const EdgeInsets.all(LHSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(LHRadius.md),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Code (démo) :',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            SelectableText(_devToken!,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                    IconButton(
                      tooltip: 'Copier le code',
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _devToken!));
                        lhToast(context, 'Code copié.');
                      },
                    ),
                  ]),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) =>
                        ResetPasswordScreen(initialToken: _devToken),
                  )),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Définir un nouveau mot de passe'),
                ),
                const SizedBox(height: LHSpacing.md),
              ],
              FilledButton(
                onPressed: _busy ? null : _submitLink,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Envoyer le lien'),
              ),
            ],

            // ── Par questions de sécurité ──
            if (_mode == _RecoveryMode.questions) ...[
              if (_questions == null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _loadQuestions,
                  icon: const Icon(Icons.quiz_outlined, size: 18),
                  label: const Text('Afficher mes questions de sécurité'),
                )
              else ...[
                for (var i = 0; i < _questions!.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LHSpacing.md),
                    child: LabeledField(
                      label: _questions![i],
                      child: TextField(
                        controller: _answers[i],
                        obscureText: true,
                        decoration: const InputDecoration(
                            hintText: 'Votre réponse',
                            prefixIcon: Icon(Icons.key_outlined)),
                      ),
                    ),
                  ),
                if (_resetToken == null)
                  FilledButton(
                    onPressed: _busy ? null : _submitAnswers,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Vérifier mes réponses'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          ResetPasswordScreen(initialToken: _resetToken),
                    )),
                    icon: const Icon(Icons.key_outlined, size: 18),
                    label: const Text('Définir un nouveau mot de passe'),
                  ),
              ],
            ],
            const SizedBox(height: LHSpacing.md),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Retour à la connexion'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ NOUVEAU MOT DE PASSE ══════════════════════════

/// Réinitialisation : code reçu + nouveau mot de passe.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final _code = TextEditingController(text: widget.initialToken ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Renseignez le code reçu.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() =>
          _error = 'Le mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).resetPassword(
            resetToken: _code.text.trim(),
            newPassword: _password.text,
          );
      if (!mounted) return;
      setState(
          () => _info = 'Mot de passe modifié — vous pouvez vous connecter.');
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (e) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Nouveau mot de passe',
      subtitle:
          'Collez le code reçu puis choisissez votre nouveau mot de passe.',
      child: LHCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ErrorBanner(_error),
            if (_info != null)
              Container(
                margin: const EdgeInsets.only(bottom: LHSpacing.md),
                padding: const EdgeInsets.all(LHSpacing.md),
                decoration: BoxDecoration(
                  color: LHColors.emeraudeClair.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(LHRadius.md),
                  border: Border.all(
                      color: LHColors.emeraudeClair.withValues(alpha: 0.5)),
                ),
                child: Text(_info!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: LHColors.emeraudeClair)),
              ),
            LabeledField(
              label: 'Code de réinitialisation',
              child: TextField(
                controller: _code,
                decoration: const InputDecoration(
                    hintText: 'Code reçu par courriel ou SMS',
                    prefixIcon: Icon(Icons.key_outlined)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Nouveau mot de passe (8 caractères minimum)',
              child: TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: 'Choisissez un mot de passe solide',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Afficher' : 'Masquer',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Confirmer le mot de passe',
              child: TextField(
                controller: _confirm,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                    hintText: 'Répétez le mot de passe',
                    prefixIcon: Icon(Icons.lock_outline)),
              ),
            ),
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Modifier le mot de passe'),
            ),
            const SizedBox(height: LHSpacing.md),
            TextButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                (route) => route.isFirst,
              ),
              child: const Text('Aller à la connexion'),
            ),
          ],
        ),
      ),
    );
  }
}

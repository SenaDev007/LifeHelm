import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_client.dart';
import '../../core/net/sync_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../main.dart' show bootState;
import '../../shell/widgets.dart' show HelmMark;

// ══════════════════════════ SOCLES COMMUNS ══════════════════════════

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
  Future<void> _persistSessionAndWelcome(WidgetRef ref, LhAuthResult result) async {
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
      setState(() => _error = 'Renseignez votre identifiant et votre mot de passe.');
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
          _error = 'Double authentification active — saisissez le code à 6 chiffres.';
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
                    hintText: 'awa@exemple.tg ou +228 90 12 34 56',
                    prefixIcon: Icon(Icons.alternate_email)),
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
                    icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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

// ══════════════════════════ INSCRIPTION ══════════════════════════

/// Inscription : prénom (requis), nom, courriel OU téléphone, mot de passe.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

enum _ContactMode { email, phone }

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _contact = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _ContactMode _mode = _ContactMode.email;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _contact.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _contactValid => switch (_mode) {
        _ContactMode.email => RegExp(
                r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
            .hasMatch(_contact.text.trim()),
        _ContactMode.phone =>
          _contact.text.trim().replaceAll(RegExp(r'[\s\-().]'), '').length >= 8,
      };

  Future<void> _submit() async {
    final first = _firstName.text.trim();
    if (first.isEmpty) {
      setState(() => _error = 'Le prénom est obligatoire.');
      return;
    }
    if (!_contactValid) {
      setState(() => _error = _mode == _ContactMode.email
          ? 'Renseignez un courriel valide ou basculez sur téléphone.'
          : 'Renseignez un numéro de téléphone valide ou basculez sur courriel.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 8 caractères.');
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
      final contact = _contact.text.trim();
      final result = await ref.read(apiClientProvider).register(
            email: _mode == _ContactMode.email ? contact : null,
            phone: _mode == _ContactMode.phone
                ? contact.replaceAll(RegExp(r'[\s\-().]'), '')
                : null,
            password: _password.text,
            firstName: first,
            lastName:
                _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
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
      title: 'Créer un compte',
      subtitle:
          'Vos données restent sur votre appareil tant que vous n\'activez pas la synchronisation.',
      child: LHCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ErrorBanner(_error),
            Row(children: [
              Expanded(
                child: LabeledField(
                  label: 'Prénom *',
                  child: TextField(
                    controller: _firstName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        hintText: 'Ex. : Awa', prefixIcon: Icon(Icons.person_outline)),
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
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Moyen de contact (au moins un)',
              child: LhSegmented<_ContactMode>(
                value: _mode,
                items: const {
                  _ContactMode.email: 'Courriel',
                  _ContactMode.phone: 'Téléphone',
                },
                onChanged: (m) => setState(() => _mode = m),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            TextField(
              controller: _contact,
              keyboardType: _mode == _ContactMode.email
                  ? TextInputType.emailAddress
                  : TextInputType.phone,
              decoration: InputDecoration(
                hintText: _mode == _ContactMode.email
                    ? 'awa@exemple.tg'
                    : '+228 90 12 34 56',
                prefixIcon: Icon(_mode == _ContactMode.email
                    ? Icons.alternate_email
                    : Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Mot de passe (8 caractères minimum)',
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
                  : const Text('Créer mon compte'),
            ),
            const SizedBox(height: LHSpacing.md),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Déjà un compte ?',
                  style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen())),
                child: const Text('Se connecter'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ MOT DE PASSE OUBLIÉ ══════════════════════════

/// Demande de réinitialisation : identifiant → 202. En mode démo, le serveur
/// renvoie un `devResetToken` affiché discrètement avec bouton copier.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _identifier = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  String? _devToken;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
      final res = await ref
          .read(apiClientProvider)
          .forgotPassword(identifier);
      final devToken = res['devResetToken'] as String?;
      if (!mounted) return;
      setState(() {
        if (devToken != null && devToken.isNotEmpty) {
          _devToken = devToken;
          _info = 'Serveur de démonstration — code de réinitialisation ci-dessous.';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _AuthScaffold(
      title: 'Mot de passe oublié',
      subtitle:
          'Nous enverrons un lien de réinitialisation à votre courriel ou par SMS.',
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
            LabeledField(
              label: 'Courriel ou téléphone du compte',
              child: TextField(
                controller: _identifier,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                    hintText: 'awa@exemple.tg',
                    prefixIcon: Icon(Icons.alternate_email)),
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
                  : const Text('Envoyer le lien'),
            ),
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
      setState(() => _error = 'Le mot de passe doit contenir au moins 8 caractères.');
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
      setState(() => _info =
          'Mot de passe modifié — vous pouvez vous connecter.');
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
      subtitle: 'Collez le code reçu puis choisissez votre nouveau mot de passe.',
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LHColors.emeraudeClair)),
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
                MaterialPageRoute<void>(
                    builder: (_) => const LoginScreen()),
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

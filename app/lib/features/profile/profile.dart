import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/db/database.dart';
import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../core/taxonomy.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../main.dart' show bootState;

// ═══════════════════════════ PROFIL DU COMPTE ═══════════════════════════

/// Profil complet : photo modifiable, identité (prénom, nom, courriel,
/// téléphone, profession, pays), questions de sécurité de récupération,
/// changement de mot de passe, déconnexion et suppression définitive
/// du compte.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final theme = Theme.of(context);

    if (!session.isConnected || user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon profil')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          message: 'Aucun compte connecté',
          hint: 'Créez un compte pour activer la sauvegarde multi-appareils.',
          action: FilledButton.icon(
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Se connecter ou créer un compte'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: LHSpacing.lg),
          _ProfileHeader(user: user),
          SectionHeader('Identité & coordonnées',
              inset: LHSpacing.screen, overline: 'Vos informations'),
          _InfoTile(
            icon: Icons.badge_outlined,
            label: 'Prénom',
            value: user.firstName,
          ),
          _InfoTile(
            icon: Icons.badge_outlined,
            label: 'Nom',
            value: user.lastName?.isEmpty ?? true ? '—' : user.lastName!,
          ),
          _InfoTile(
            icon: Icons.alternate_email,
            label: 'Adresse e-mail',
            value: user.email ?? 'Non renseignée',
            chip: user.email != null
                ? (user.emailVerifiedAt != null ? 'Vérifié' : 'Non vérifié')
                : null,
            chipColor: user.emailVerifiedAt != null
                ? LHColors.emeraudeClair
                : LHColors.alerte,
          ),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: 'Téléphone',
            value: user.phone ?? 'Non renseigné',
            chip: user.phone != null
                ? (user.phoneVerifiedAt != null ? 'Vérifié' : 'Non vérifié')
                : null,
            chipColor: user.phoneVerifiedAt != null
                ? LHColors.emeraudeClair
                : LHColors.alerte,
          ),
          _InfoTile(
            icon: Icons.work_outline,
            label: 'Profession',
            value: user.profession ?? 'Non renseignée',
          ),
          SectionHeader('Gestion du compte',
              inset: LHSpacing.screen, overline: 'Actions'),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Modifier mon profil'),
            subtitle: const Text('Prénom, nom, téléphone, profession, pays'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => _editProfileSheet(context, ref, user),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Changer mon mot de passe'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => _changePasswordSheet(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.quiz_outlined),
            title: const Text('Questions de sécurité'),
            subtitle: const Text(
                'Récupérez vos données en cas d\'oubli du mot de passe'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => _securityQuestionsSheet(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Sessions & appareils'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => context.push('/sessions'),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Sécurité & double authentification'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => context.push('/security'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Synchronisation'),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: LHColors.neutre),
            onTap: () => context.push('/sync'),
          ),
          SectionHeader('Zone sensible',
              inset: LHSpacing.screen, overline: 'À manier avec précaution'),
          ListTile(
            leading: const Icon(Icons.logout, color: LHColors.erreur),
            title: const Text('Se déconnecter',
                style: TextStyle(color: LHColors.erreur)),
            subtitle: const Text(
                'Vos données restent sur cet appareil, la synchronisation s\'arrête'),
            onTap: () => _logout(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined,
                color: LHColors.erreur),
            title: const Text('Supprimer définitivement mon compte',
                style: TextStyle(color: LHColors.erreur)),
            subtitle: Text(
                'Compte et données en ligne effacés pour toujours — action '
                'irréversible.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: LHColors.erreur)),
            onTap: () => _deleteAccountSheet(context, ref),
          ),
        ],
      ),
    );
  }

  // ── Déconnexion : jetons révoqués + retour écran de connexion ──
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await lhConfirm(
      context,
      title: 'Se déconnecter ?',
      message: 'Vos données restent sur cet appareil — seule la sauvegarde en '
          'ligne est interrompue.',
      confirmLabel: 'Se déconnecter',
    );
    if (!ok) return;
    final store = ref.read(tokenStoreProvider);
    final session = await store.load();
    try {
      if (session != null) {
        await ref.read(apiClientProvider).logout(session.refreshToken);
      }
    } catch (_) {
      // Serveur injoignable : la déconnexion locale prime.
    }
    await store.clear();
    if (context.mounted) {
      context.go('/login?loggedOut=1');
    }
  }

  Future<void> _editProfileSheet(
      BuildContext context, WidgetRef ref, LhUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditProfileSheet(user: user),
    );
  }

  Future<void> _changePasswordSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _securityQuestionsSheet(
      BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _SecurityQuestionsSheet(),
    );
  }

  Future<void> _deleteAccountSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _DeleteAccountSheet(),
    );
  }
}

// ═══════════════════════════ EN-TÊTE : PHOTO + NOM ═══════════════════════════

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});
  final LhUser user;

  Future<void> _pickPhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 82);
    if (picked == null) return;

    String stored;
    if (kIsWeb) {
      // Web : on conserve l'image sous forme d'URI de données.
      final bytes = await picked.readAsBytes();
      stored = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } else {
      // Natif : copie dans le dossier documents de l'application.
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/avatar_lifehelm.jpg');
      await picked.saveTo(dest.path);
      stored = dest.path;
    }
    await ref
        .read(dbProvider)
        .saveLocalProfile(UserProfileCompanion(avatarPath: Value(stored)));
    if (context.mounted) lhToast(context, 'Photo de profil mise à jour.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(localProfileProvider).valueOrNull;

    return Center(
      child: Column(children: [
        Stack(children: [
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? LHColors.or
                      : LHColors.orDeep,
                  width: 2.5),
            ),
            child: ClipOval(
              child: _avatarWidget(profile?.avatarPath, user.displayName),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: theme.brightness == Brightness.dark
                  ? LHColors.or
                  : LHColors.orDeep,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _pickPhoto(context, ref),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.photo_camera_outlined,
                      size: 18, color: LHColors.noir),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: LHSpacing.md),
        Text(user.displayName, style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          user.profession ?? 'Profession non renseignée',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          'Membre depuis ${fmt.formatMonthYear(user.createdAt)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Widget _avatarWidget(String? path, String fallbackName) {
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('data:')) {
        return Image.network(path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                InitialsAvatar(name: fallbackName, size: 112));
      }
      if (!kIsWeb) {
        return Image.file(File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                InitialsAvatar(name: fallbackName, size: 112));
      }
    }
    return InitialsAvatar(name: fallbackName, size: 112);
  }
}

/// Profil local (photo, profession, questions de sécurité).
final localProfileProvider = StreamProvider<UserProfileData>(
    (ref) => ref.watch(dbProvider).watchLocalProfile());

// ═══════════════════════════ TUILE D'INFORMATION ═══════════════════════════

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.chip,
    this.chipColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? chip;
  final Color? chipColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(value, style: theme.textTheme.bodyLarge),
      subtitle: Text(label, style: theme.textTheme.bodySmall),
      trailing: chip != null
          ? StatusChip(
              label: chip!, color: chipColor ?? LHColors.neutre, small: true)
          : null,
    );
  }
}

// ═══════════════════════════ MODIFIER LE PROFIL ═══════════════════════════

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});
  final LhUser user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _firstName = TextEditingController(text: widget.user.firstName);
  late final _lastName =
      TextEditingController(text: widget.user.lastName ?? '');
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _profession =
      TextEditingController(text: widget.user.profession ?? '');
  late CountryInfo _country = countryByIso(widget.user.country);

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _profession.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _firstName.text.trim();
    if (first.isEmpty) {
      setState(() => _error = 'Le prénom ne peut pas être vide.');
      return;
    }
    final phoneInput = _phone.text.trim();
    if (!isPlausiblePhoneInput(phoneInput)) {
      setState(() => _error =
          'Numéro invalide — chiffres uniquement (l\'indicatif est déjà sélectionné).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fullPhone = normalizePhoneInput(phoneInput, _country);
      final updated = await ref.read(apiClientProvider).updateProfile(
            firstName: first,
            lastName: _lastName.text.trim(),
            phone: fullPhone,
            profession: _profession.text.trim(),
            country: _country.iso,
          );
      await ref.read(tokenStoreProvider).updateUser(updated);
      await ref.read(dbProvider).saveLocalProfile(UserProfileCompanion(
            profession: Value(_profession.text.trim()),
            countryIso: Value(_country.iso),
          ));
      if (mounted) {
        lhToast(context, 'Profil mis à jour.');
        Navigator.pop(context);
      }
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
    } on LhNetworkException catch (e) {
      setState(() => _error = apiErrorText(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Modifier mon profil',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            Row(children: [
              Expanded(
                child: LabeledField(
                  label: 'Prénom *',
                  child: TextField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words),
                ),
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'Nom',
                  child: TextField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words),
                ),
              ),
            ]),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Adresse e-mail (non modifiable ici)',
              child: TextField(
                controller:
                    TextEditingController(text: widget.user.email ?? '—'),
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.alternate_email)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Pays (indicatif téléphonique)',
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
            const SizedBox(height: LHSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sans l\'indicatif (${_country.dial} déjà inclus) — 10 chiffres '
                'au Bénin, 8 pour l\'ancien format.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Profession (liste ou saisie libre)',
              child: ProfessionPickerField(controller: _profession),
            ),
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer les modifications'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ CHANGER LE MOT DE PASSE ═══════════════════════════

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_new.text.length < 8) {
      setState(() => _error =
          'Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      setState(() => _info =
          'Mot de passe modifié — vos autres sessions ont été déconnectées.');
      _current.clear();
      _new.clear();
      _confirm.clear();
    } on LhApiException catch (e) {
      setState(() => _error = apiErrorText(e));
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
    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Changer mon mot de passe',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_info!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.emeraudeClair)),
              ),
            LabeledField(
              label: 'Mot de passe actuel',
              child: TextField(
                controller: _current,
                obscureText: _obscure,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    )),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Nouveau mot de passe (8 caractères minimum)',
              child: TextField(
                controller: _new,
                obscureText: _obscure,
                decoration:
                    const InputDecoration(prefixIcon: Icon(Icons.lock_outline)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Confirmer le nouveau mot de passe',
              child: TextField(
                controller: _confirm,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration:
                    const InputDecoration(prefixIcon: Icon(Icons.lock_outline)),
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
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ QUESTIONS DE SÉCURITÉ ═══════════════════════════

class _SecurityQuestionsSheet extends ConsumerStatefulWidget {
  const _SecurityQuestionsSheet();

  @override
  ConsumerState<_SecurityQuestionsSheet> createState() =>
      _SecurityQuestionsSheetState();
}

class _SecurityQuestionsSheetState
    extends ConsumerState<_SecurityQuestionsSheet> {
  final _answers = List.generate(3, (_) => TextEditingController());
  String? _q1, _q2, _q3;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(localProfileProvider).valueOrNull;
    if (profile != null) {
      _q1 = profile.securityQuestion1;
      _q2 = profile.securityQuestion2;
      _q3 = profile.securityQuestion3;
    }
  }

  @override
  void dispose() {
    for (final a in _answers) {
      a.dispose();
    }
    super.dispose();
  }

  String _hash(String answer) =>
      sha256.convert(utf8.encode(answer.trim().toLowerCase())).toString();

  Future<void> _save() async {
    final questions = [_q1, _q2, _q3];
    if (questions.any((q) => q == null)) {
      setState(() => _error = 'Choisissez les trois questions.');
      return;
    }
    if (_answers.any((a) => a.text.trim().isEmpty)) {
      setState(() => _error = 'Répondez aux trois questions.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final items = [
      for (var i = 0; i < 3; i++)
        (
          question: questions[i]!,
          answerHash: _hash(_answers[i].text),
        ),
    ];
    // Persistance locale (hors ligne d'abord — offline-first).
    await ref.read(dbProvider).saveLocalProfile(UserProfileCompanion(
          securityQuestion1: Value(items[0].question),
          securityQuestion2: Value(items[1].question),
          securityQuestion3: Value(items[2].question),
          securityAnswer1: Value(items[0].answerHash),
          securityAnswer2: Value(items[1].answerHash),
          securityAnswer3: Value(items[2].answerHash),
        ));
    // Puis serveur (si joignable — silencieux sinon).
    var serverSynced = false;
    try {
      await ref.read(apiClientProvider).setSecurityQuestions(items);
      serverSynced = true;
    } catch (_) {
      // Hors ligne : les questions restent valides localement.
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _info = serverSynced
            ? 'Questions enregistrées (appareil + serveur).'
            : 'Questions enregistrées sur cet appareil — elles seront '
                'synchronisées à la prochaine connexion au serveur.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Questions de sécurité',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'En cas d\'oubli de votre mot de passe, ces questions vous '
              'permettent de récupérer l\'accès à vos données. Choisissez des '
              'réponses que vous serez seul à connaître.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_info!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.emeraudeClair)),
              ),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LabeledField(
                      label: 'Question ${i + 1}',
                      child: DropdownButtonFormField<String>(
                        value: switch (i) {
                          0 => _q1,
                          1 => _q2,
                          _ => _q3,
                        },
                        isExpanded: true,
                        menuMaxHeight: 320,
                        items: [
                          for (final q in securityQuestions)
                            DropdownMenuItem(
                                value: q,
                                child: Text(q,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2)),
                        ],
                        onChanged: (v) => setState(() {
                          switch (i) {
                            case 0:
                              _q1 = v;
                            case 1:
                              _q2 = v;
                            default:
                              _q3 = v;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: LHSpacing.sm),
                    TextField(
                      controller: _answers[i],
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Votre réponse (confidentielle)',
                        prefixIcon: const Icon(Icons.key_outlined),
                        enabled: switch (i) {
                          0 => _q1 != null,
                          1 => _q2 != null,
                          _ => _q3 != null,
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: LHSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer les questions'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ SUPPRESSION DÉFINITIVE ═══════════════════════════

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_acknowledged) {
      setState(() => _error = 'Cochez la case de reconnaissance finale.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Confirmez avec votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).deleteAccount(_password.text);
    } on LhApiException catch (e) {
      setState(() {
        _busy = false;
        _error = apiErrorText(e);
      });
      return;
    } on LhNetworkException catch (e) {
      setState(() {
        _busy = false;
        _error =
            '${apiErrorText(e)} La suppression exige une connexion Internet.';
      });
      return;
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Une erreur inattendue est survenue.';
      });
      return;
    }

    // Compte supprimé côté serveur : effacement local complet puis retour
    // à l'écran d'accueil (nouvelle vie, données propres).
    final db = ref.read(dbProvider);
    for (final table in db.allTables) {
      await db.delete(table).go();
    }
    await ref.read(tokenStoreProvider).clear();
    bootState.onboarded = false;
    if (mounted) {
      Navigator.pop(context);
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: LHColors.erreur, size: 44),
            const SizedBox(height: LHSpacing.md),
            Text('Supprimer définitivement mon compte',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: LHColors.erreur)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'Votre compte, vos sessions et toutes vos données synchronisées '
              'seront effacés du serveur, pour toujours. Cette action est '
              'IRRÉVERSIBLE. Les données présentes uniquement sur cet appareil '
              'seront également supprimées.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            InkWell(
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              borderRadius: BorderRadius.circular(LHRadius.sm),
              child: Row(children: [
                Icon(
                  _acknowledged
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank,
                  color: _acknowledged ? LHColors.erreur : null,
                ),
                const SizedBox(width: LHSpacing.sm),
                Expanded(
                  child: Text(
                    'Je comprends que cette suppression est définitive et '
                    'que mes données ne pourront pas être récupérées.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Confirmez avec votre mot de passe',
              child: TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LHColors.erreur),
              onPressed: _busy ? null : _delete,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Supprimer mon compte pour toujours'),
            ),
            const SizedBox(height: LHSpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler — garder mon compte'),
            ),
          ],
        ),
      ),
    );
  }
}

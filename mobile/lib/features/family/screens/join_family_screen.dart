import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';
import '../providers/family_providers.dart';

class JoinFamilyScreen extends ConsumerStatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  ConsumerState<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends ConsumerState<JoinFamilyScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(8, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text.trim().toUpperCase()).join();

  Future<void> _submit() async {
    final code = _code;
    if (code.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le code d\'invitation doit faire 8 caractères'),
          backgroundColor: LifeHelmColors.danger,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final family = await ref.read(familyRepositoryProvider).joinFamily(code);
      ref.invalidate(familiesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bienvenue dans « ${family.name} »'),
            backgroundColor: LifeHelmColors.success,
          ),
        );
        context.go('/family/${family.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presse-papier vide')),
      );
      return;
    }
    for (var i = 0; i < 8 && i < text.length; i++) {
      _ctrls[i].text = text[i];
    }
    if (text.length < 8) {
      _nodes[text.length].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rejoindre une famille'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Coller le code',
            onPressed: _pasteFromClipboard,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: LifeHelmColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_add, color: LifeHelmColors.primary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Saisis le code d\'invitation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demande le code à 8 caractères à l\'administrateur de la famille que tu veux rejoindre.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(8, (i) {
                return SizedBox(
                  width: 38,
                  height: 56,
                  child: TextFormField(
                    controller: _ctrls[i],
                    focusNode: _nodes[i],
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: LifeHelmColors.primary,
                    ),
                    textInputAction: i < 7 ? TextInputAction.next : TextInputAction.done,
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: LifeHelmColors.textTertiary, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: LifeHelmColors.textTertiary, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: LifeHelmColors.primary, width: 2),
                      ),
                    ),
                    onChanged: (v) {
                      final upper = v.toUpperCase();
                      if (v != upper) _ctrls[i].text = upper;
                      if (upper.isNotEmpty && i < 7) {
                        _nodes[i + 1].requestFocus();
                      }
                      // Auto-submit quand 8 caractères sont remplis
                      if (_code.length == 8 && i == 7) {
                        FocusScope.of(context).unfocus();
                      }
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            LifeHelmButton(
              label: 'Rejoindre la famille',
              icon: Icons.group_add,
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _submit,
            ),
            const SizedBox(height: 12),
            LifeHelmButton(
              label: 'Annuler',
              variant: LifeHelmButtonVariant.outline,
              onPressed: _isLoading ? null : () => context.pop(),
            ),
            const SizedBox(height: 24),
            // Alternative simple field pour coller un code long
            TextButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Coller depuis le presse-papier'),
            ),
          ],
        ),
      ),
    );
  }
}

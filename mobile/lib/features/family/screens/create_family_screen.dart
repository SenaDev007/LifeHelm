import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/family_providers.dart';

class CreateFamilyScreen extends ConsumerStatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le nom de la famille est requis'),
          backgroundColor: LifeHelmColors.danger,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final family = await ref.read(familyRepositoryProvider).createFamily(
            name: name,
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          );
      ref.invalidate(familiesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Famille « ${family.name} » créée'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer une famille'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    LifeHelmColors.primary.withValues(alpha: 0.1),
                    LifeHelmColors.accent.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: LifeHelmColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.family_restroom, color: LifeHelmColors.primary),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crée ta famille',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Partagez budget, objectifs et avancées. Un code d\'invitation sera généré pour inviter tes proches.',
                          style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LifeHelmTextField(
              controller: _nameCtrl,
              label: 'Nom de la famille *',
              hint: 'Ex: Famille Adjovi, Les Héros, etc.',
              prefixIcon: const Icon(Icons.label),
            ),
            const SizedBox(height: 16),
            LifeHelmTextField(
              controller: _descCtrl,
              label: 'Description (optionnel)',
              hint: 'Quelques mots sur votre famille...',
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 24),
            LifeHelmButton(
              label: 'Créer la famille',
              icon: Icons.check,
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _submit,
            ),
            const SizedBox(height: 12),
            LifeHelmButton(
              label: 'Annuler',
              variant: LifeHelmButtonVariant.outline,
              onPressed: _isLoading ? null : () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

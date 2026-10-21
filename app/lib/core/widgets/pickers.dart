import 'dart:async';

import 'package:flutter/material.dart';

import '../taxonomy.dart';
import '../theme/tokens.dart';

// ═══════════════════════════ SÉLECTEUR DE PAYS (indicatif) ═══════════════════════════

/// Champ « pays + indicatif » : bouton affichant le pays sélectionné,
/// ouvrant une feuille de recherche parmi tous les pays du monde.
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final CountryInfo selected;
  final ValueChanged<CountryInfo> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(LHRadius.md),
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.public_outlined),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              '${selected.name} (${selected.dial})',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const Icon(Icons.expand_more, size: 20),
        ]),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<CountryInfo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _CountryPickerSheet(),
    );
    if (picked != null) onChanged(picked);
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? countries
        : countries
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.dial.contains(q) ||
                c.iso.toLowerCase() == q)
            .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              LHSpacing.screen, LHSpacing.md, LHSpacing.screen, LHSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Votre pays',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Rechercher un pays ou un indicatif (ex. : 229)',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (ctx, i) {
              final c = results[i];
              final isDefault = c.iso == defaultCountry.iso;
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 34,
                  child: Text(c.iso,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.brightness == Brightness.dark
                              ? LHColors.or
                              : LHColors.orDeep)),
                ),
                title: Text(c.name),
                trailing: Text(c.dial,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: isDefault ? const Text('Par défaut') : null,
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ SÉLECTEUR DE PROFESSION ═══════════════════════════

/// Champ profession : autocomplétion sur le référentiel quasi exhaustif,
/// avec libre saisie manuelle si la profession est absente de la liste.
class ProfessionPickerField extends StatelessWidget {
  const ProfessionPickerField({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        hintText: 'Ex. : Commerçante, Médecin, Développeur…',
        prefixIcon: Icon(Icons.badge_outlined),
        suffixIcon: _ProfessionHint(),
      ),
    );
  }
}

class _ProfessionHint extends StatelessWidget {
  const _ProfessionHint();
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Liste prédéfinie + saisie manuelle libre',
        child: Icon(Icons.help_outline,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Boîte de suggestions de professions filtrées par préfixe/sous-chaîne.
/// Affichée sous le champ, pilotée par un OverlayEntry simple : la liste
/// déroulante de Material (Autocomplete) est préférée ici pour sa
/// robustesse clavier.
class ProfessionAutocomplete extends StatelessWidget {
  const ProfessionAutocomplete({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.length < 2) return const Iterable<String>.empty();
        return allProfessions
            .where((p) => p.toLowerCase().contains(q))
            .take(12);
      },
      onSelected: onSelected,
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Ex. : Commerçante, Médecin, Développeur…',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(LHRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 340),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

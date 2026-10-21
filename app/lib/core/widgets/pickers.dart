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

/// Champ profession : trois moyens complémentaires de choisir —
/// 1. saisie libre au clavier (la valeur suit directement le contrôleur) ;
/// 2. suggestions filtrées en direct dès 2 caractères saisis ;
/// 3. bouton « parcourir » (chevron) ouvrant la liste complète des métiers,
///    groupée par domaine et défilable, avec recherche intégrée.
class ProfessionPickerField extends StatefulWidget {
  const ProfessionPickerField({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  State<ProfessionPickerField> createState() => _ProfessionPickerFieldState();
}

class _ProfessionPickerFieldState extends State<ProfessionPickerField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      // Le contrôleur externe pilote le champ : la saisie libre n'est jamais
      // perdue (contrairement à un contrôleur interne recopié à la sélection).
      // RawAutocomplete exige un focusNode accompagnant le contrôleur externe
      // (assertion du SDK) ; le pattern est stable de Flutter 3.5 à 3.13+.
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final q = _foldFr(value.text.trim());
        if (q.length < 2) return const Iterable<String>.empty();
        return allProfessions
            .where((p) => _foldFr(p).contains(q))
            .take(8);
      },
      onSelected: (p) => widget.onChanged?.call(p),
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onChanged: widget.onChanged,
          onSubmitted: (_) => onFieldSubmitted(),
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Ex. : Commerçante, Médecin, Développeur…',
            prefixIcon: const Icon(Icons.badge_outlined),
            suffixIcon: IconButton(
              tooltip: 'Parcourir la liste des professions',
              icon: const Icon(Icons.expand_more),
              onPressed: () => _openSheet(context),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(LHRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 340),
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

  /// Ouvre la feuille plein écran : liste complète défilable + recherche.
  /// La sélection (référentiel ou saisie libre) remplit le champ.
  Future<void> _openSheet(BuildContext context) async {
    // Ferme le panneau de suggestions et le clavier avant d'ouvrir la
    // feuille : sinon le panneau flotterait au-dessus du voile modal.
    _focusNode.unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _ProfessionPickerSheet(current: widget.controller.text.trim()),
    );
    if (!context.mounted) return;
    if (picked == null || picked.isEmpty) return;
    // Retire le focus avant d'écrire la valeur : évite que le panneau de
    // suggestions ne se rouvre juste après la sélection dans la feuille.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.controller.value = TextEditingValue(
      text: picked,
      selection: TextSelection.collapsed(offset: picked.length),
    );
    widget.onChanged?.call(picked);
  }
}

/// Une ligne de la liste de navigation : en-tête de domaine ou métier.
class _ProfRow {
  const _ProfRow.header(this.domain) : profession = null;
  const _ProfRow.item(this.profession, this.domain);
  final String? profession; // null → ligne d'en-tête de domaine
  final String domain;
}

/// Minuscules + pliage des accents (ç→c, é→e…) : taper « commerc »
/// retrouve « Commerçant », « medecin » retrouve « Médecin ».
String _foldFr(String s) {
  var r = s.toLowerCase();
  for (final e in _accentsFr.entries) {
    r = r.replaceAll(e.key, e.value);
  }
  return r;
}

const Map<String, String> _accentsFr = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
};

/// Feuille modale : titre + recherche + liste intégrale des professions
/// groupées par domaine (mode navigation) ou résultats triés par pertinence
/// (mode recherche), avec option de saisie libre en tête.
class _ProfessionPickerSheet extends StatefulWidget {
  const _ProfessionPickerSheet({this.current});

  final String? current;

  @override
  State<_ProfessionPickerSheet> createState() =>
      _ProfessionPickerSheetState();
}

class _ProfessionPickerSheetState extends State<_ProfessionPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Toutes les lignes du mode navigation (en-têtes + métiers), à plat.
  static final List<_ProfRow> _rows = [
    for (final d in professionDomains.entries) ...[
      _ProfRow.header(d.key),
      for (final p in d.value) _ProfRow.item(p, d.key),
    ],
  ];

  /// Métier → domaine, pour le sous-titre des résultats de recherche.
  static final Map<String, String> _professionToDomain = {
    for (final d in professionDomains.entries)
      for (final p in d.value) p: d.key,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? LHColors.or : LHColors.orDeep;
    final q = _query.trim();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              LHSpacing.screen, LHSpacing.md, LHSpacing.screen, LHSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.badge_outlined, color: accent, size: 20),
                const SizedBox(width: LHSpacing.sm),
                Expanded(
                  child: Text('Votre profession',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('${allProfessions.length} métiers',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: accent, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Rechercher une profession…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: q.isEmpty
              ? _browseList(theme, accent)
              : _searchList(theme, accent, q),
        ),
      ]),
    );
  }

  /// Mode navigation : tous les domaines et métiers, défilables.
  Widget _browseList(ThemeData theme, Color accent) {
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (ctx, i) {
        final row = _rows[i];
        if (row.profession == null) {
          return Container(
            padding: const EdgeInsets.fromLTRB(LHSpacing.screen,
                LHSpacing.md, LHSpacing.screen, LHSpacing.xs),
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.06),
            child: Text(
              row.domain.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: accent),
            ),
          );
        }
        final selected = row.profession == widget.current;
        return ListTile(
          dense: true,
          title: Text(row.profession!,
              style: selected
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null),
          trailing: selected
              ? Icon(Icons.check_circle, color: accent, size: 20)
              : null,
          onTap: () => Navigator.pop(ctx, row.profession),
        );
      },
    );
  }

  /// Mode recherche : saisie libre en tête, puis correspondances triées
  /// (préfixe d'abord, sous-chaîne ensuite) avec leur domaine en sous-titre.
  /// Insensible à la casse et aux accents.
  Widget _searchList(ThemeData theme, Color accent, String q) {
    final ql = _foldFr(q);
    final starts = <String>[];
    final contains = <String>[];
    for (final p in allProfessions) {
      final lp = _foldFr(p);
      if (lp.startsWith(ql)) {
        starts.add(p);
      } else if (lp.contains(ql)) {
        contains.add(p);
      }
    }
    final matches = [...starts, ...contains];
    final exact = matches.any((p) => _foldFr(p) == ql);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: LHSpacing.lg),
      itemCount: matches.length + (exact ? 0 : 1),
      itemBuilder: (ctx, i) {
        if (!exact && i == 0) {
          return ListTile(
            leading: Icon(Icons.edit_note_outlined, color: accent),
            title: Text('Utiliser « $q »'),
            subtitle: const Text('Saisie libre — profession personnalisée'),
            onTap: () => Navigator.pop(ctx, q),
          );
        }
        final p = matches[exact ? i : i - 1];
        final selected = p == widget.current;
        return ListTile(
          dense: true,
          leading: const Icon(Icons.badge_outlined, size: 20),
          title: Text(p,
              style: selected
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null),
          subtitle: Text(_professionToDomain[p] ?? ''),
          trailing: selected
              ? Icon(Icons.check_circle, color: accent, size: 20)
              : null,
          onTap: () => Navigator.pop(ctx, p),
        );
      },
    );
  }
}

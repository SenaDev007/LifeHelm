import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;

// ═══════════════════════════ LABELS CARRIÈRE (D10) ═══════════════════════════

/// Autoévaluée ≠ prouvée ≠ certifiée — états distincts (D10 §15.2).
const skillStatuses = ['SELFASSESSED', 'PROVEN', 'CERTIFIED'];

String skillStatusLabel(String s) {
  switch (s) {
    case 'PROVEN':
      return 'Prouvée';
    case 'CERTIFIED':
      return 'Certifiée';
    default:
      return 'Autoévaluée';
  }
}

Color skillStatusColor(String s) {
  switch (s) {
    case 'PROVEN':
      return LHColors.or;
    case 'CERTIFIED':
      return LHColors.emeraudeClair;
    default:
      return LHColors.neutre;
  }
}

const pathStatuses = ['NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'PAUSED'];

String pathStatusLabel(String s) {
  switch (s) {
    case 'IN_PROGRESS':
      return 'En cours';
    case 'COMPLETED':
      return 'Terminé';
    case 'PAUSED':
      return 'En pause';
    default:
      return 'Non commencé';
  }
}

Color pathStatusColor(String s) {
  switch (s) {
    case 'IN_PROGRESS':
      return LHColors.info;
    case 'COMPLETED':
      return LHColors.emeraudeClair;
    case 'PAUSED':
      return LHColors.alerte;
    default:
      return LHColors.neutre;
  }
}

/// Déclarée ≠ justificatif fourni ≠ vérifiée — états distincts (D10 §15.2).
const certStatuses = ['DECLARED', 'EVIDENCE', 'VERIFIED'];

String certStatusLabel(String s) {
  switch (s) {
    case 'EVIDENCE':
      return 'Justificatif fourni';
    case 'VERIFIED':
      return 'Vérifiée';
    default:
      return 'Déclarée';
  }
}

Color certStatusColor(String s) {
  switch (s) {
    case 'EVIDENCE':
      return LHColors.or;
    case 'VERIFIED':
      return LHColors.emeraudeClair;
    default:
      return LHColors.neutre;
  }
}

// ═══════════════════════════ REQUÊTES D10 ═══════════════════════════

extension CareerQueries on AppDatabase {
  // —— Profil ——
  Stream<CareerProfile?> watchCareerProfile(String spaceId) {
    return (select(careerProfiles)
          ..where((p) => p.spaceId.equals(spaceId)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  Future<void> upsertCareerProfile(String spaceId, String? existingId,
      {String? headline,
      String? summary,
      String? location,
      String? email,
      String? phone}) async {
    if (existingId == null) {
      final id = 'cp_${DateTime.now().microsecondsSinceEpoch}';
      await into(careerProfiles).insert(CareerProfile(
          id: id,
          spaceId: spaceId,
          headline: headline,
          summary: summary,
          location: location,
          email: email,
          phone: phone));
      logOp('CareerProfile', id, 'CREATE', {'spaceId': spaceId});
    } else {
      await (update(careerProfiles)..where((p) => p.id.equals(existingId)))
          .write(CareerProfilesCompanion(
              headline: Value(headline),
              summary: Value(summary),
              location: Value(location),
              email: Value(email),
              phone: Value(phone)));
      logOp('CareerProfile', existingId, 'UPDATE', {});
    }
  }

  // —— Compétences ——
  /// Compétences de l'utilisateur avec leur référence Skills (jointure).
  Stream<List<(UserSkill, Skill)>> watchUserSkillsDetailed() {
    final query = select(userSkills).join([
      innerJoin(skills, skills.id.equalsExp(userSkills.skillId)),
    ]);
    return query.watch().map((rows) =>
        rows.map((r) => (r.readTable(userSkills), r.readTable(skills))).toList());
  }

  Future<Skill?> findSkillByName(String name) async {
    final all = await select(skills).get();
    final lower = name.trim().toLowerCase();
    for (final s in all) {
      if (s.name.trim().toLowerCase() == lower) return s;
    }
    return null;
  }

  /// Crée l'entrée Skills si le nom n'existe pas, puis upsert le UserSkill.
  Future<void> upsertUserSkill({
    String? userSkillId,
    required String name,
    String? category,
    required int level,
    required String status,
  }) async {
    var skill = await findSkillByName(name);
    if (skill == null) {
      final skillId = 'skl_${DateTime.now().microsecondsSinceEpoch}';
      skill = Skill(id: skillId, name: name.trim(), category: category);
      await into(skills).insert(skill);
      logOp('Skill', skillId, 'CREATE', {'name': name});
    } else if (category != null && category != skill.category) {
      final sid = skill.id;
      await (update(skills)..where((s) => s.id.equals(sid)))
          .write(SkillsCompanion(category: Value(category)));
    }
    if (userSkillId == null) {
      final id = 'usk_${DateTime.now().microsecondsSinceEpoch}';
      await into(userSkills).insert(UserSkill(
          id: id, skillId: skill.id, level: level, status: status));
      logOp('UserSkill', id, 'CREATE',
          {'skill': name, 'level': level, 'status': status});
    } else {
      await (update(userSkills)..where((u) => u.id.equals(userSkillId))).write(
          UserSkillsCompanion(
              skillId: Value(skill.id),
              level: Value(level),
              status: Value(status)));
      logOp('UserSkill', userSkillId, 'UPDATE',
          {'skill': name, 'level': level, 'status': status});
    }
  }

  Future<void> deleteUserSkill(String id) async {
    await (delete(userSkills)..where((u) => u.id.equals(id))).go();
    logOp('UserSkill', id, 'DELETE', {});
  }

  // —— Parcours d'apprentissage ——
  Stream<List<LearningPath>> watchLearningPaths(String spaceId) {
    return (select(learningPaths)
          ..where((p) => p.spaceId.equals(spaceId))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .watch();
  }

  Future<void> saveLearningPath(LearningPath p, {required bool isNew}) async {
    await into(learningPaths).insert(p, mode: InsertMode.insertOrReplace);
    logOp('LearningPath', p.id, isNew ? 'CREATE' : 'UPDATE', {'title': p.title});
  }

  Future<void> setPathStatus(String pathId, String status) async {
    await (update(learningPaths)..where((p) => p.id.equals(pathId)))
        .write(LearningPathsCompanion(status: Value(status)));
    logOp('LearningPath', pathId, 'UPDATE', {'status': status});
  }

  Future<void> deleteLearningPath(String id) async {
    await (delete(learningPathSteps)..where((s) => s.pathId.equals(id))).go();
    await (delete(learningPaths)..where((p) => p.id.equals(id))).go();
    logOp('LearningPath', id, 'DELETE', {'cascade': true});
  }

  Stream<List<LearningPathStep>> watchPathSteps(String pathId) {
    return (select(learningPathSteps)
          ..where((s) => s.pathId.equals(pathId))
          ..orderBy([(s) => OrderingTerm.asc(s.position)]))
        .watch();
  }

  Future<void> addPathStep(String pathId, String label) async {
    final existing = await (select(learningPathSteps)
          ..where((s) => s.pathId.equals(pathId)))
        .get();
    final id = 'lpstep_${DateTime.now().microsecondsSinceEpoch}';
    await into(learningPathSteps).insert(LearningPathStep(
        id: id, pathId: pathId, label: label, done: false,
        position: existing.length));
    logOp('LearningPathStep', id, 'CREATE', {'label': label});
  }

  /// Coche une étape ; une première coche fait passer le parcours
  /// de « Non commencé » à « En cours ».
  Future<void> setPathStepDone(String stepId, bool done) async {
    await (update(learningPathSteps)..where((s) => s.id.equals(stepId)))
        .write(LearningPathStepsCompanion(done: Value(done)));
    logOp('LearningPathStep', stepId, 'UPDATE', {'done': done});
    if (!done) return;
    final step = await (select(learningPathSteps)
          ..where((s) => s.id.equals(stepId)))
        .getSingle();
    final path = await (select(learningPaths)
          ..where((p) => p.id.equals(step.pathId)))
        .getSingleOrNull();
    if (path != null && path.status == 'NOT_STARTED') {
      await setPathStatus(path.id, 'IN_PROGRESS');
    }
  }

  Future<void> deletePathStep(String id) async {
    await (delete(learningPathSteps)..where((s) => s.id.equals(id))).go();
    logOp('LearningPathStep', id, 'DELETE', {});
  }

  // —— Expériences ——
  Stream<List<ProfessionalExperience>> watchExperiences(String spaceId) {
    return (select(professionalExperiences)
          ..where((e) => e.spaceId.equals(spaceId))
          ..orderBy([(e) => OrderingTerm.desc(e.startDate)]))
        .watch();
  }

  Future<void> saveExperience(ProfessionalExperience e,
      {required bool isNew}) async {
    await into(professionalExperiences)
        .insert(e, mode: InsertMode.insertOrReplace);
    logOp('ProfessionalExperience', e.id, isNew ? 'CREATE' : 'UPDATE',
        {'organization': e.organization, 'role': e.role});
  }

  Future<void> deleteExperience(String id) async {
    await (delete(professionalExperiences)..where((e) => e.id.equals(id))).go();
    logOp('ProfessionalExperience', id, 'DELETE', {});
  }

  // —— Portfolio ——
  Stream<List<PortfolioItem>> watchPortfolioItems(String spaceId) {
    return (select(portfolioItems)
          ..where((p) => p.spaceId.equals(spaceId))
          ..orderBy([(p) => OrderingTerm.asc(p.title)]))
        .watch();
  }

  Future<void> savePortfolioItem(PortfolioItem p, {required bool isNew}) async {
    await into(portfolioItems).insert(p, mode: InsertMode.insertOrReplace);
    logOp('PortfolioItem', p.id, isNew ? 'CREATE' : 'UPDATE', {'title': p.title});
  }

  Future<void> deletePortfolioItem(String id) async {
    await (delete(portfolioItems)..where((p) => p.id.equals(id))).go();
    logOp('PortfolioItem', id, 'DELETE', {});
  }

  // —— Certifications ——
  Stream<List<Certification>> watchCertifications() {
    return (select(certifications)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<void> saveCertification(Certification c, {required bool isNew}) async {
    await into(certifications).insert(c, mode: InsertMode.insertOrReplace);
    logOp('Certification', c.id, isNew ? 'CREATE' : 'UPDATE', {'name': c.name});
  }

  Future<void> deleteCertification(String id) async {
    await (delete(certifications)..where((c) => c.id.equals(id))).go();
    logOp('Certification', id, 'DELETE', {});
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final careerProfileProvider = StreamProvider.family<CareerProfile?, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchCareerProfile(spaceId));

final userSkillsDetailedProvider =
    StreamProvider<List<(UserSkill, Skill)>>(
        (ref) => ref.watch(dbProvider).watchUserSkillsDetailed());

final learningPathsProvider = StreamProvider.family<List<LearningPath>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchLearningPaths(spaceId));

final pathStepsProvider = StreamProvider.family<List<LearningPathStep>, String>(
    (ref, pathId) => ref.watch(dbProvider).watchPathSteps(pathId));

final experiencesProvider =
    StreamProvider.family<List<ProfessionalExperience>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchExperiences(spaceId));

final portfolioProvider = StreamProvider.family<List<PortfolioItem>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchPortfolioItems(spaceId));

final certificationsProvider = StreamProvider<List<Certification>>(
    (ref) => ref.watch(dbProvider).watchCertifications());

// ═══════════════════════════ ÉCRAN : CARRIÈRE ═══════════════════════════

/// Carrière — profil, compétences, parcours, expériences, portfolio &
/// certifications (D10). Un seul écran, onglets.
class CareerScreen extends StatelessWidget {
  const CareerScreen({super.key});

  static const _tabs = [
    Tab(text: 'Profil'),
    Tab(text: 'Compétences'),
    Tab(text: 'Parcours'),
    Tab(text: 'Expériences'),
    Tab(text: 'Portfolio & Certifs'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: LhAppBar(title: 'Carrière'),
        body: Column(children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _tabs,
          ),
          const Expanded(
            child: TabBarView(children: [
              _ProfileTab(),
              _SkillsTab(),
              _PathsTab(),
              _ExperiencesTab(),
              _PortfolioTab(),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ———————— Onglet Profil ————————

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final profileAsync = ref.watch(careerProfileProvider(spaceId));

    return ListView(
      padding: const EdgeInsets.all(LHSpacing.screen),
      children: [
        // Confidentialité (D10 §15.1-7 : privé par défaut, partage explicite).
        Row(children: [
          Icon(Icons.lock_outline,
              size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Privé par défaut — partage explicite, ressource par ressource.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ]),
        const SizedBox(height: LHSpacing.md),

        profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Erreur : $e'),
          data: (profile) {
            final headline = profile?.headline;
            final summary = profile?.summary;
            final hasHeadline = headline != null && headline.isNotEmpty;
            final hasSummary = summary != null && summary.isNotEmpty;
            return LHCard(
              accent: LHColors.or.withValues(alpha: 0.85),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  hasHeadline ? headline : 'Aucun titre professionnel',
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: hasHeadline ? null : theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  hasSummary ? summary : '—',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const Divider(height: LHSpacing.xl),
                _profileRow(context, Icons.place_outlined,
                    profile?.location, 'Localisation'),
                _profileRow(context, Icons.mail_outline, profile?.email,
                    'E-mail'),
                _profileRow(
                    context, Icons.phone_outlined, profile?.phone, 'Téléphone'),
                const SizedBox(height: LHSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _ProfileDialog.show(context, profile),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier le profil'),
                ),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _profileRow(
      BuildContext context, IconData icon, String? value, String label) {
    final theme = Theme.of(context);
    final empty = value == null || value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            empty ? '— ($label)' : value,
            style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    empty ? theme.colorScheme.outline : null),
          ),
        ),
      ]),
    );
  }
}

/// Dialogue d'édition du profil (consommé sous ProviderScope → ConsumerState).
class _ProfileDialog extends ConsumerStatefulWidget {
  const _ProfileDialog({this.profile});

  final CareerProfile? profile;

  static Future<void> show(BuildContext context, CareerProfile? profile) {
    return showDialog<void>(
        context: context, builder: (_) => _ProfileDialog(profile: profile));
  }

  @override
  ConsumerState<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends ConsumerState<_ProfileDialog> {
  late final TextEditingController _headline;
  late final TextEditingController _summary;
  late final TextEditingController _location;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _headline = TextEditingController(text: p?.headline ?? '');
    _summary = TextEditingController(text: p?.summary ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
  }

  @override
  void dispose() {
    _headline.dispose();
    _summary.dispose();
    _location.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le profil'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _headline,
            decoration: const InputDecoration(
                labelText: 'Titre professionnel',
                hintText: 'ex. Développeur mobile senior'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _summary,
            maxLines: 3,
            decoration:
                const InputDecoration(labelText: 'Résumé', hintText: 'Profil, spécialités…'),
          ),
          const SizedBox(height: 10),
          TextField(
              controller: _location,
              decoration: const InputDecoration(
                  labelText: 'Localisation', hintText: 'ex. Lomé, Togo')),
          const SizedBox(height: 10),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail')),
          const SizedBox(height: 10),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            await ref.read(dbProvider).upsertCareerProfile(
              ref.read(activeSpaceIdProvider),
              widget.profile?.id,
              headline: _headline.text.trim().isEmpty ? null : _headline.text.trim(),
              summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
              email: _email.text.trim().isEmpty ? null : _email.text.trim(),
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            );
            nav.pop();
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ———————— Onglet Compétences ————————

class _SkillsTab extends ConsumerWidget {
  const _SkillsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final skillsAsync = ref.watch(userSkillsDetailedProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        SectionHeader('Compétences',
            overline: 'Niveaux & preuves',
            action: IconButton(
              tooltip: 'Ajouter une compétence',
              onPressed: () => _SkillDialog.show(context),
              icon: const Icon(Icons.add_circle_outline),
            )),
        skillsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Erreur : $e'),
          data: (pairs) {
            if (pairs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                    icon: Icons.psychology_outlined,
                    message:
                        'Aucune compétence enregistrée.\nAutoévaluée, prouvée ou certifiée : ajoutez la première.'),
              );
            }
            final sorted = [...pairs];
            sorted.sort((a, b) {
              final c = (a.$2.category ?? '')
                  .compareTo(b.$2.category ?? '');
              if (c != 0) return c;
              return a.$2.name.compareTo(b.$2.name);
            });
            return Column(children: [
              for (final (us, sk) in sorted)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: LHCard(
                    onTap: () => _SkillDialog.show(context,
                        userSkillId: us.id,
                        name: sk.name,
                        category: sk.category,
                        level: us.level,
                        status: us.status),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(sk.name,
                              style: theme.textTheme.titleSmall),
                        ),
                        StatusChip(
                            label: skillStatusLabel(us.status),
                            color: skillStatusColor(us.status),
                            small: true),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (sk.category != null && sk.category!.isNotEmpty) ...[
                          Text(sk.category!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(width: 12),
                        ],
                        // Niveau 0..5 : 5 pastilles remplies.
                        for (var i = 1; i <= 5; i++)
                          Container(
                            width: 11,
                            height: 11,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i <= us.level
                                  ? LHColors.or
                                  : null,
                              border: i <= us.level
                                  ? null
                                  : Border.all(
                                      color: theme.colorScheme.outline),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Text('niveau ${us.level}/5',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Supprimer',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: LHColors.erreur),
                          onPressed: () async {
                            final ok = await lhConfirm(
                              context,
                              title: 'Supprimer cette compétence ?',
                              message:
                                  '« ${sk.name} » sera retirée de votre profil.',
                              confirmLabel: 'Supprimer',
                              destructive: true,
                            );
                            if (ok) {
                              await ref
                                  .read(dbProvider)
                                  .deleteUserSkill(us.id);
                            }
                          },
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// Dialogue ajout/édition de compétence.
class _SkillDialog extends ConsumerStatefulWidget {
  const _SkillDialog({
    this.userSkillId,
    this.name,
    this.category,
    this.level = 3,
    this.status = 'SELFASSESSED',
  });

  final String? userSkillId;
  final String? name;
  final String? category;
  final int level;
  final String status;

  static Future<void> show(BuildContext context,
      {String? userSkillId,
      String? name,
      String? category,
      int? level,
      String? status}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _SkillDialog(
        userSkillId: userSkillId,
        name: name,
        category: category,
        level: level ?? 3,
        status: status ?? 'SELFASSESSED',
      ),
    );
  }

  @override
  ConsumerState<_SkillDialog> createState() => _SkillDialogState();
}

class _SkillDialogState extends ConsumerState<_SkillDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late int _level;
  late String _status;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name ?? '');
    _category = TextEditingController(text: widget.category ?? '');
    _level = widget.level;
    _status = widget.status;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title:
          Text(widget.userSkillId == null ? 'Ajouter une compétence' : 'Modifier la compétence'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Nom', hintText: 'ex. Flutter, Négociation…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _category,
            decoration: const InputDecoration(
                labelText: 'Catégorie', hintText: 'ex. Technique, Transversal…'),
          ),
          const SizedBox(height: 14),
          Text('Niveau (0 à 5)',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Wrap(
            spacing: 6,
            children: [
              for (var l = 0; l <= 5; l++)
                ChoiceChip(
                  label: Text('$l'),
                  selected: _level == l,
                  onSelected: (_) => setState(() => _level = l),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Statut de preuve',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Wrap(
            spacing: 6,
            children: [
              for (final s in skillStatuses)
                ChoiceChip(
                  label: Text(skillStatusLabel(s)),
                  selected: _status == s,
                  labelStyle: TextStyle(
                      color: _status == s ? skillStatusColor(s) : null,
                      fontWeight: _status == s ? FontWeight.w700 : null),
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) {
              lhToast(context, 'Le nom est obligatoire.');
              return;
            }
            final category = _category.text.trim();
            await ref.read(dbProvider).upsertUserSkill(
              userSkillId: widget.userSkillId,
              name: name,
              category: category.isEmpty ? null : category,
              level: _level,
              status: _status,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.userSkillId == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

// ———————— Onglet Parcours ————————

class _PathsTab extends ConsumerWidget {
  const _PathsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final pathsAsync = ref.watch(learningPathsProvider(spaceId));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        SectionHeader("Parcours d'apprentissage",
            overline: 'Progression',
            action: IconButton(
              tooltip: 'Nouveau parcours',
              onPressed: () => _PathDialog.show(context),
              icon: const Icon(Icons.add_circle_outline),
            )),
        pathsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Erreur : $e'),
          data: (paths) {
            if (paths.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                    icon: Icons.school_outlined,
                    message:
                        'Aucun parcours.\nCréez un parcours pour structurer votre apprentissage.'),
              );
            }
            return Column(children: [
              for (final p in paths) _PathCard(path: p),
            ]);
          },
        ),
      ],
    );
  }
}

class _PathCard extends ConsumerWidget {
  const _PathCard({required this.path});

  final LearningPath path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final stepsAsync = ref.watch(pathStepsProvider(path.id));
    final steps = stepsAsync.valueOrNull ?? const <LearningPathStep>[];
    final done = steps.where((s) => s.done).length;
    final total = steps.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: LHCard(
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: false,
          leading: ProgressRing(
            progress: progress,
            size: 42,
            stroke: 3.5,
            color: pathStatusColor(path.status),
            child: Text('$done/$total',
                style: const TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
          title: Text(path.title,
              style: theme.textTheme.titleSmall),
          subtitle: Row(children: [
            StatusChip(
                label: pathStatusLabel(path.status),
                color: pathStatusColor(path.status),
                small: true),
            if (path.targetDate != null) ...[
              const SizedBox(width: 8),
              Text('→ ${fmt.formatMedium(fmt.parseKey(path.targetDate!))}',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ]),
          children: [
            if (path.description != null && path.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Text(path.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            for (final s in steps)
              Row(children: [
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: s.done,
                    activeColor: LHColors.emeraudeClair,
                    onChanged: (_) => db.setPathStepDone(s.id, !s.done),
                  ),
                ),
                Expanded(
                  child: Text(s.label,
                      style: TextStyle(
                          fontSize: 14,
                          decoration:
                              s.done ? TextDecoration.lineThrough : null)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18, color: LHColors.erreur),
                  onPressed: () => db.deletePathStep(s.id),
                ),
              ]),
            _AddStepRow(pathId: path.id),
            const Divider(height: 1),
            Row(children: [
              PopupMenuButton<String>(
                tooltip: 'Changer le statut',
                initialValue: path.status,
                onSelected: (v) => db.setPathStatus(path.id, v),
                itemBuilder: (_) => [
                  for (final s in pathStatuses)
                    PopupMenuItem(value: s, child: Text(pathStatusLabel(s))),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.flag_outlined,
                        size: 16, color: pathStatusColor(path.status)),
                    const SizedBox(width: 6),
                    Text('Statut : ${pathStatusLabel(path.status)}',
                        style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: LHColors.erreur),
                onPressed: () async {
                  final ok = await lhConfirm(
                    context,
                    title: 'Supprimer ce parcours ?',
                    message:
                        '« ${path.title} » et ses étapes seront supprimés.',
                    confirmLabel: 'Supprimer',
                    destructive: true,
                  );
                  if (ok) db.deleteLearningPath(path.id);
                },
                child: const Text('Supprimer'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Champ d'ajout d'étape inline (parcours).
class _AddStepRow extends ConsumerStatefulWidget {
  const _AddStepRow({required this.pathId});

  final String pathId;

  @override
  ConsumerState<_AddStepRow> createState() => _AddStepRowState();
}

class _AddStepRowState extends ConsumerState<_AddStepRow> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
                isDense: true, hintText: 'Nouvelle étape…'),
            onSubmitted: (v) => _add(v),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _add(_ctrl.text),
        ),
      ]),
    );
  }

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    ref.read(dbProvider).addPathStep(widget.pathId, v);
    setState(() => _ctrl.clear());
  }
}

/// Dialogue nouveau parcours.
class _PathDialog extends ConsumerStatefulWidget {
  const _PathDialog();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
        context: context, builder: (_) => const _PathDialog());
  }

  @override
  ConsumerState<_PathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends ConsumerState<_PathDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _targetDate;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau parcours'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Titre', hintText: 'ex. Maîtriser Flutter'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _targetDate != null
                    ? fmt.parseKey(_targetDate!)
                    : fmt.addDays(fmt.today(), 60),
                firstDate: fmt.today(),
                lastDate: DateTime(2100),
                locale: const Locale('fr'),
              );
              if (picked != null) {
                setState(() => _targetDate = fmt.dateKey(picked));
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Date cible (facultative)',
                  icon: Icon(Icons.flag_outlined)),
              child: Text(_targetDate == null
                  ? '—'
                  : fmt.formatLong(fmt.parseKey(_targetDate!))),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final title = _title.text.trim();
            if (title.isEmpty) {
              lhToast(context, 'Le titre est obligatoire.');
              return;
            }
            final db = ref.read(dbProvider);
            final spaceId = ref.read(activeSpaceIdProvider);
            await db.saveLearningPath(
              LearningPath(
                id: 'lp_${DateTime.now().microsecondsSinceEpoch}',
                spaceId: spaceId,
                title: title,
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
                status: 'NOT_STARTED',
                targetDate: _targetDate,
                createdAt: DateTime.now(),
              ),
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

// ———————— Onglet Expériences ————————

class _ExperiencesTab extends ConsumerWidget {
  const _ExperiencesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final experiencesAsync = ref.watch(experiencesProvider(spaceId));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        SectionHeader('Expériences',
            overline: 'Parcours professionnel',
            action: IconButton(
              tooltip: 'Ajouter une expérience',
              onPressed: () => _ExperienceDialog.show(context),
              icon: const Icon(Icons.add_circle_outline),
            )),
        experiencesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Erreur : $e'),
          data: (exps) {
            if (exps.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                    icon: Icons.work_history_outlined,
                    message:
                        'Aucune expérience.\nAjoutez vos postes pour construire votre timeline.'),
              );
            }
            return Column(children: [
              for (final (i, e) in exps.indexed)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Rail de timeline
                      SizedBox(
                        width: 22,
                        child: Column(children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(top: 22),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: e.isCurrent
                                  ? LHColors.emeraudeClair
                                  : null,
                              border: Border.all(
                                  color: e.isCurrent
                                      ? LHColors.emeraudeClair
                                      : theme.colorScheme.outline,
                                  width: 2),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              width: 2,
                              color: i == exps.length - 1
                                  ? Colors.transparent
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: LHCard(
                            accent: e.isCurrent ? LHColors.emeraudeClair : null,
                            onTap: () => _ExperienceDialog.show(context, existing: e),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(e.role,
                                          style: theme.textTheme.titleSmall),
                                    ),
                                    if (e.isCurrent)
                                      const StatusChip(
                                          label: 'En poste',
                                          color: LHColors.emeraudeClair,
                                          small: true),
                                  ]),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.business_outlined,
                                        size: 14,
                                        color: theme
                                            .colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(e.organization,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant)),
                                    ),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${fmt.formatMonthYear(fmt.parseKey(e.startDate))} → '
                                    '${e.isCurrent ? "aujourd'hui" : (e.endDate != null ? fmt.formatMonthYear(fmt.parseKey(e.endDate!)) : '—')}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme
                                            .colorScheme.onSurfaceVariant),
                                  ),
                                  if (e.description != null &&
                                      e.description!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(e.description!,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall),
                                  ],
                                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                    IconButton(
                                      tooltip: 'Supprimer',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20, color: LHColors.erreur),
                                      onPressed: () async {
                                        final ok = await lhConfirm(
                                          context,
                                          title: 'Supprimer cette expérience ?',
                                          message:
                                              '« ${e.role} — ${e.organization} » sera supprimée.',
                                          confirmLabel: 'Supprimer',
                                          destructive: true,
                                        );
                                        if (ok) {
                                          await ref
                                              .read(dbProvider)
                                              .deleteExperience(e.id);
                                        }
                                      },
                                    ),
                                  ]),
                                ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// Dialogue ajout/édition d'expérience.
class _ExperienceDialog extends ConsumerStatefulWidget {
  const _ExperienceDialog({this.existing});

  final ProfessionalExperience? existing;

  static Future<void> show(BuildContext context,
      {ProfessionalExperience? existing}) {
    return showDialog<void>(
        context: context,
        builder: (_) => _ExperienceDialog(existing: existing));
  }

  @override
  ConsumerState<_ExperienceDialog> createState() => _ExperienceDialogState();
}

class _ExperienceDialogState extends ConsumerState<_ExperienceDialog> {
  final _organization = TextEditingController();
  final _role = TextEditingController();
  final _description = TextEditingController();
  String? _startDate;
  String? _endDate;
  bool _isCurrent = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _organization.text = e?.organization ?? '';
    _role.text = e?.role ?? '';
    _description.text = e?.description ?? '';
    _startDate = e?.startDate;
    _endDate = e?.endDate;
    _isCurrent = e?.isCurrent ?? false;
  }

  @override
  void dispose() {
    _organization.dispose();
    _role.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = fmt.parseKey(
        (isStart ? _startDate : _endDate) ?? fmt.dateKey(fmt.today()));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = fmt.dateKey(picked);
        } else {
          _endDate = fmt.dateKey(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ajouter une expérience'
          : 'Modifier l\'expérience'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _organization,
            decoration: const InputDecoration(labelText: 'Organisation'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _role,
            decoration: const InputDecoration(labelText: 'Rôle'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(isStart: true),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Début'),
                  child: Text(_startDate == null
                      ? '—'
                      : fmt.formatMedium(fmt.parseKey(_startDate!))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _isCurrent ? null : () => _pickDate(isStart: false),
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: 'Fin',
                      helperText: _isCurrent ? 'En poste' : null),
                  child: Text(
                    _isCurrent
                        ? '—'
                        : (_endDate == null
                            ? '—'
                            : fmt.formatMedium(fmt.parseKey(_endDate!))),
                    style: TextStyle(
                        color: _isCurrent
                            ? Theme.of(context).hintColor
                            : null),
                  ),
                ),
              ),
            ),
          ]),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('En poste actuellement'),
            value: _isCurrent,
            onChanged: (v) => setState(() {
              _isCurrent = v;
              if (v) _endDate = null;
            }),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final org = _organization.text.trim();
            final role = _role.text.trim();
            if (org.isEmpty || role.isEmpty) {
              lhToast(context, 'Organisation et rôle sont obligatoires.');
              return;
            }
            if (_startDate == null) {
              lhToast(context, 'Indiquez la date de début.');
              return;
            }
            final db = ref.read(dbProvider);
            final spaceId = ref.read(activeSpaceIdProvider);
            final e = widget.existing;
            await db.saveExperience(
              ProfessionalExperience(
                id: e?.id ?? 'exp_${DateTime.now().microsecondsSinceEpoch}',
                spaceId: e?.spaceId ?? spaceId,
                organization: org,
                role: role,
                startDate: _startDate!,
                endDate: _isCurrent ? null : _endDate,
                isCurrent: _isCurrent,
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
              ),
              isNew: e == null,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.existing == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

// ———————— Onglet Portfolio & Certifications ————————

class _PortfolioTab extends ConsumerWidget {
  const _PortfolioTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final portfolioAsync = ref.watch(portfolioProvider(spaceId));
    final certsAsync = ref.watch(certificationsProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        SectionHeader('Portfolio',
            overline: 'Réalisations',
            action: IconButton(
              tooltip: 'Ajouter une réalisation',
              onPressed: () => _PortfolioDialog.show(context),
              icon: const Icon(Icons.add_circle_outline),
            )),
        portfolioAsync.when(
          loading: () => const SizedBox(),
          error: (e, _) => Text('Erreur : $e'),
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune réalisation au portfolio.'),
              );
            }
            return Column(children: [
              for (final item in items)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: LHCard(
                    onTap: () => _PortfolioDialog.show(context, existing: item),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, style: theme.textTheme.titleSmall),
                      if (item.description != null &&
                          item.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.description!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      if (item.link != null && item.link!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.link_outlined,
                              size: 15, color: LHColors.info),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(item.link!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: LHColors.info)),
                          ),
                        ]),
                      ],
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(
                          tooltip: 'Supprimer',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: LHColors.erreur),
                          onPressed: () async {
                            final ok = await lhConfirm(
                              context,
                              title: 'Supprimer cette réalisation ?',
                              message: '« ${item.title} » sera supprimée du portfolio.',
                              confirmLabel: 'Supprimer',
                              destructive: true,
                            );
                            if (ok) {
                              await ref
                                  .read(dbProvider)
                                  .deletePortfolioItem(item.id);
                            }
                          },
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),

        SectionHeader('Certifications',
            overline: 'Justificatifs',
            action: IconButton(
              tooltip: 'Ajouter une certification',
              onPressed: () => _CertDialog.show(context),
              icon: const Icon(Icons.add_circle_outline),
            )),
        certsAsync.when(
          loading: () => const SizedBox(),
          error: (e, _) => Text('Erreur : $e'),
          data: (certs) {
            if (certs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune certification.'),
              );
            }
            return Column(children: [
              for (final c in certs)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: LHCard(
                    onTap: () => _CertDialog.show(context, existing: c),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(c.name, style: theme.textTheme.titleSmall),
                        ),
                        StatusChip(
                            label: certStatusLabel(c.status),
                            color: certStatusColor(c.status),
                            small: true),
                      ]),
                      const SizedBox(height: 4),
                      if (c.issuer != null && c.issuer!.isNotEmpty)
                        Row(children: [
                          Icon(Icons.workspace_premium_outlined,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(c.issuer!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                        ]),
                      const SizedBox(height: 4),
                      Text(
                        'Délivrée le ${c.issueDate != null ? fmt.formatMedium(fmt.parseKey(c.issueDate!)) : '—'}'
                        '${c.expiryDate != null ? ' · expire le ${fmt.formatMedium(fmt.parseKey(c.expiryDate!))}' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (c.credentialId != null &&
                          c.credentialId!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('N° ${c.credentialId}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: LHColors.neutre)),
                      ],
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(
                          tooltip: 'Supprimer',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: LHColors.erreur),
                          onPressed: () async {
                            final ok = await lhConfirm(
                              context,
                              title: 'Supprimer cette certification ?',
                              message: '« ${c.name} » sera supprimée.',
                              confirmLabel: 'Supprimer',
                              destructive: true,
                            );
                            if (ok) {
                              await ref
                                  .read(dbProvider)
                                  .deleteCertification(c.id);
                            }
                          },
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// Dialogue ajout/édition de réalisation (portfolio).
class _PortfolioDialog extends ConsumerStatefulWidget {
  const _PortfolioDialog({this.existing});

  final PortfolioItem? existing;

  static Future<void> show(BuildContext context, {PortfolioItem? existing}) {
    return showDialog<void>(
        context: context,
        builder: (_) => _PortfolioDialog(existing: existing));
  }

  @override
  ConsumerState<_PortfolioDialog> createState() => _PortfolioDialogState();
}

class _PortfolioDialogState extends ConsumerState<_PortfolioDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    _title.text = widget.existing?.title ?? '';
    _description.text = widget.existing?.description ?? '';
    _link.text = widget.existing?.link ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ajouter une réalisation'
          : 'Modifier la réalisation'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Lien (facultatif)', hintText: 'https://…'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final title = _title.text.trim();
            if (title.isEmpty) {
              lhToast(context, 'Le titre est obligatoire.');
              return;
            }
            final db = ref.read(dbProvider);
            final spaceId = ref.read(activeSpaceIdProvider);
            final e = widget.existing;
            await db.savePortfolioItem(
              PortfolioItem(
                id: e?.id ?? 'pf_${DateTime.now().microsecondsSinceEpoch}',
                spaceId: e?.spaceId ?? spaceId,
                title: title,
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
                link: _link.text.trim().isEmpty ? null : _link.text.trim(),
              ),
              isNew: e == null,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.existing == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

/// Dialogue ajout/édition de certification (statut distinct à 3 états).
class _CertDialog extends ConsumerStatefulWidget {
  const _CertDialog({this.existing});

  final Certification? existing;

  static Future<void> show(BuildContext context, {Certification? existing}) {
    return showDialog<void>(
        context: context,
        builder: (_) => _CertDialog(existing: existing));
  }

  @override
  ConsumerState<_CertDialog> createState() => _CertDialogState();
}

class _CertDialogState extends ConsumerState<_CertDialog> {
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _credentialId = TextEditingController();
  String? _issueDate;
  String? _expiryDate;
  late String _status;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name.text = c?.name ?? '';
    _issuer.text = c?.issuer ?? '';
    _credentialId.text = c?.credentialId ?? '';
    _issueDate = c?.issueDate;
    _expiryDate = c?.expiryDate;
    _status = c?.status ?? 'DECLARED';
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _credentialId.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isIssue}) async {
    final initial =
        fmt.parseKey((isIssue ? _issueDate : _expiryDate) ?? fmt.dateKey(fmt.today()));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() {
        if (isIssue) {
          _issueDate = fmt.dateKey(picked);
        } else {
          _expiryDate = fmt.dateKey(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ajouter une certification'
          : 'Modifier la certification'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Intitulé'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _issuer,
            decoration: const InputDecoration(labelText: 'Émetteur'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(isIssue: true),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Délivrée le'),
                  child: Text(_issueDate == null
                      ? '—'
                      : fmt.formatMedium(fmt.parseKey(_issueDate!))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(isIssue: false),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Expire le'),
                  child: Text(_expiryDate == null
                      ? '—'
                      : fmt.formatMedium(fmt.parseKey(_expiryDate!))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _credentialId,
            decoration: const InputDecoration(
                labelText: 'N° de justificatif', hintText: 'ex. GFC-2024-8842'),
          ),
          const SizedBox(height: 12),
          Text('Statut',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Wrap(
            spacing: 6,
            children: [
              for (final s in certStatuses)
                ChoiceChip(
                  label: Text(certStatusLabel(s)),
                  selected: _status == s,
                  labelStyle: TextStyle(
                      color: _status == s ? certStatusColor(s) : null,
                      fontWeight: _status == s ? FontWeight.w700 : null),
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) {
              lhToast(context, 'L\'intitulé est obligatoire.');
              return;
            }
            final db = ref.read(dbProvider);
            final c = widget.existing;
            await db.saveCertification(
              Certification(
                id: c?.id ?? 'cert_${DateTime.now().microsecondsSinceEpoch}',
                name: name,
                issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
                issueDate: _issueDate,
                expiryDate: _expiryDate,
                status: _status,
                credentialId: _credentialId.text.trim().isEmpty
                    ? null
                    : _credentialId.text.trim(),
              ),
              isNew: c == null,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.existing == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

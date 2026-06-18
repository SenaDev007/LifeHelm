import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/family_providers.dart';

class FamilyDetailScreen extends ConsumerWidget {
  const FamilyDetailScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(familyDashboardProvider(familyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Famille'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Partager',
            onPressed: () async {
              final dash = dashAsync.valueOrNull;
              if (dash == null) return;
              await Share.share(
                'Rejoins ma famille « ${dash.name} » sur LifeHelm avec le code d\'invitation : ${dash.inviteCode}',
                subject: 'Invitation LifeHelm Famille',
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(familyDashboardProvider(familyId)),
        child: dashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 16),
              Text('Erreur: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(familyDashboardProvider(familyId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
          data: (dash) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _FamilyHeader(dash: dash),
                const SizedBox(height: 16),
                if (dash.isAdmin) _AdminActions(familyId: familyId, dash: dash),
                if (dash.isAdmin) const SizedBox(height: 16),

                // Members
                _SectionTitle(
                  title: 'Membres (${dash.members.length})',
                  icon: Icons.people,
                  trailing: dash.isAdmin
                      ? TextButton.icon(
                          onPressed: () => _showShareCode(context, dash),
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Ajouter'),
                        )
                      : null,
                ),
                Card(
                  child: Column(
                    children: dash.members.map((m) => _MemberTile(
                      member: m,
                      canRemove: dash.isAdmin && !m.isAdmin,
                      onRemove: () async {
                        final confirm = await _confirmRemove(context, m.fullName);
                        if (confirm != true) return;
                        try {
                          await ref.read(familyRepositoryProvider).removeMember(familyId, m.id);
                          ref.invalidate(familyDashboardProvider(familyId));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Membre exclu'),
                                backgroundColor: LifeHelmColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                            );
                          }
                        }
                      },
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Budget
                _SectionTitle(title: 'Budget du mois', icon: Icons.account_balance_wallet),
                _BudgetSection(familyId: familyId, budget: dash.currentBudget),
                const SizedBox(height: 16),

                // Goals
                _SectionTitle(
                  title: 'Objectifs familiaux',
                  icon: Icons.flag,
                  trailing: TextButton.icon(
                    onPressed: () => _showAddGoalDialog(context, ref, familyId, dash.members),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                  ),
                ),
                _GoalsSection(familyId: familyId, goals: dash.goals),
                const SizedBox(height: 24),

                // Quitter
                LifeHelmButton(
                  label: 'Quitter la famille',
                  icon: Icons.logout,
                  variant: LifeHelmButtonVariant.danger,
                  onPressed: () async {
                    final confirm = await _confirmLeave(context, dash.name);
                    if (confirm != true) return;
                    try {
                      await ref.read(familyRepositoryProvider).leaveFamily(familyId);
                      ref.invalidate(familiesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tu as quitté la famille'),
                            backgroundColor: LifeHelmColors.success,
                          ),
                        );
                        context.go('/family');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showShareCode(BuildContext context, FamilyDashboard dash) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LifeHelmColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Invite un membre',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Partage ce code à 8 caractères avec la personne que tu veux inviter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: LifeHelmColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LifeHelmColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                dash.inviteCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: LifeHelmColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LifeHelmButton(
                    label: 'Copier',
                    icon: Icons.copy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: dash.inviteCode));
                      if (context.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Code copié'),
                            backgroundColor: LifeHelmColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LifeHelmButton(
                    label: 'Partager',
                    icon: Icons.share,
                    variant: LifeHelmButtonVariant.accent,
                    onPressed: () async {
                      await Share.share(
                        'Rejoins ma famille « ${dash.name} » sur LifeHelm avec le code : ${dash.inviteCode}',
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddGoalDialog(BuildContext context, WidgetRef ref, String familyId, List<FamilyMember> members) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? assignedTo;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nouvel objectif familial'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LifeHelmTextField(
                  controller: titleCtrl,
                  label: 'Titre *',
                  hint: 'Ex: Voyage à Cotonou',
                ),
                const SizedBox(height: 12),
                LifeHelmTextField(
                  controller: amountCtrl,
                  label: 'Montant cible (FCFA) *',
                  hint: 'Ex: 500000',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Assigné à',
                    border: OutlineInputBorder(),
                  ),
                  value: assignedTo,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toute la famille')),
                    ...members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.fullName))),
                  ],
                  onChanged: (v) => setState(() => assignedTo = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final amount = num.tryParse(amountCtrl.text.trim());
                if (title.isEmpty || amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Titre et montant requis'),
                      backgroundColor: LifeHelmColors.danger,
                    ),
                  );
                  return;
                }
                try {
                  await ref.read(familyRepositoryProvider).createGoal(
                        familyId,
                        title: title,
                        targetAmount: amount,
                        assignedTo: assignedTo,
                      );
                  ref.invalidate(familyDashboardProvider(familyId));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Objectif créé'),
                        backgroundColor: LifeHelmColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                    );
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmLeave(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la famille'),
        content: Text('Tu es sur le point de quitter « $name ». Tu perdras l\'accès au budget familial, aux objectifs partagés et aux contributions. Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exclure un membre'),
        content: Text('Veux-tu vraiment exclure $name de cette famille ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
            child: const Text('Exclure'),
          ),
        ],
      ),
    );
  }
}

// ---------- SUB-WIDGETS ----------

class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({required this.dash});
  final FamilyDashboard dash;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: LifeHelmColors.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.family_restroom, color: LifeHelmColors.primary, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dash.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      if (dash.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          dash.description!,
                          style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (dash.isAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: LifeHelmColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ADMIN',
                                style: TextStyle(
                                  color: LifeHelmColors.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (dash.isAdmin) const SizedBox(width: 8),
                          Text(
                            '${dash.members.length} membres',
                            style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Code d'invitation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LifeHelmColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key, color: LifeHelmColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Code d\'invitation',
                          style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 11),
                        ),
                        Text(
                          dash.inviteCode.isEmpty ? '—' : dash.inviteCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: 2,
                            color: LifeHelmColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: dash.inviteCode));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Code copié'),
                            backgroundColor: LifeHelmColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminActions extends ConsumerWidget {
  const _AdminActions({required this.familyId, required this.dash});
  final String familyId;
  final FamilyDashboard dash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showEditDialog(context, ref),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Modifier'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                final newCode = await ref.read(familyRepositoryProvider).regenerateCode(familyId);
                ref.invalidate(familyDashboardProvider(familyId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Nouveau code : $newCode'),
                      backgroundColor: LifeHelmColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Nouveau code'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: dash.name);
    final descCtrl = TextEditingController(text: dash.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier la famille'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LifeHelmTextField(
              controller: nameCtrl,
              label: 'Nom *',
            ),
            const SizedBox(height: 12),
            LifeHelmTextField(
              controller: descCtrl,
              label: 'Description',
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(familyRepositoryProvider).updateFamily(
                      familyId,
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                    );
                ref.invalidate(familyDashboardProvider(familyId));
                ref.invalidate(familiesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon, this.trailing});
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: LifeHelmColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: LifeHelmColors.textSecondary,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.canRemove, required this.onRemove});
  final FamilyMember member;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (member.isAdmin ? LifeHelmColors.accent : LifeHelmColors.primary).withValues(alpha: 0.15),
        child: Text(
          member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '?',
          style: TextStyle(
            color: member.isAdmin ? LifeHelmColors.accent : LifeHelmColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        member.fullName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        member.joinedAt != null
            ? '${member.isAdmin ? "Admin • " : ""}Membre depuis ${FormatUtils.formatDate(member.joinedAt!)}'
            : (member.isAdmin ? 'Administrateur' : 'Membre'),
        style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
      ),
      trailing: canRemove
          ? IconButton(
              icon: const Icon(Icons.person_remove, color: LifeHelmColors.danger, size: 20),
              onPressed: onRemove,
              tooltip: 'Exclure',
            )
          : (member.isAdmin
              ? const Icon(Icons.shield, color: LifeHelmColors.accent, size: 18)
              : null),
    );
  }
}

class _BudgetSection extends ConsumerWidget {
  const _BudgetSection({required this.familyId, required this.budget});
  final String familyId;
  final FamilyBudget? budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (budget == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 40, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 8),
              const Text(
                'Aucun budget ce mois-ci',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'L\'admin peut créer un budget mensuel pour suivre les revenus et dépenses de la famille.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              LifeHelmButton(
                label: 'Créer un budget',
                icon: Icons.add,
                onPressed: () => _showCreateBudgetDialog(context, ref),
              ),
            ],
          ),
        ),
      );
    }
    final b = budget!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mois: ${b.month}',
                        style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                      ),
                      Text(
                        FormatUtils.formatFCFA(b.balance),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: b.balance >= 0 ? LifeHelmColors.success : LifeHelmColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+ ${FormatUtils.formatCompact(b.totalIncome)}',
                      style: const TextStyle(color: LifeHelmColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '- ${FormatUtils.formatCompact(b.totalExpense)}',
                      style: const TextStyle(color: LifeHelmColors.danger, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
            if (b.contributions.isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Contributions (${b.contributions.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              ...b.contributions.map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: LifeHelmColors.finance.withValues(alpha: 0.15),
                          child: Text(
                            (c.userName?.isNotEmpty == true ? c.userName![0] : '?').toUpperCase(),
                            style: const TextStyle(fontSize: 12, color: LifeHelmColors.finance, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.userName ?? 'Membre',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              if (c.note?.isNotEmpty == true)
                                Text(
                                  c.note!,
                                  style: const TextStyle(fontSize: 11, color: LifeHelmColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          FormatUtils.formatCompact(c.amount),
                          style: const TextStyle(
                            color: LifeHelmColors.finance,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              LifeHelmButton(
                label: 'Ajouter une contribution',
                icon: Icons.add,
                variant: LifeHelmButtonVariant.outline,
                onPressed: () => _showContributionDialog(context, ref, b.id),
              ),
            ] else ...[
              const SizedBox(height: 12),
              LifeHelmButton(
                label: 'Contribuer au budget',
                icon: Icons.add,
                variant: LifeHelmButtonVariant.outline,
                onPressed: () => _showContributionDialog(context, ref, b.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCreateBudgetDialog(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final monthCtrl = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}');
    final incomeCtrl = TextEditingController();
    final expenseCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer un budget familial'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LifeHelmTextField(
              controller: monthCtrl,
              label: 'Mois (YYYY-MM) *',
              hint: '2024-12',
            ),
            const SizedBox(height: 12),
            LifeHelmTextField(
              controller: incomeCtrl,
              label: 'Revenus du mois',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            LifeHelmTextField(
              controller: expenseCtrl,
              label: 'Dépenses du mois',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(familyRepositoryProvider).createBudget(
                      familyId,
                      month: monthCtrl.text.trim(),
                      totalIncome: num.tryParse(incomeCtrl.text.trim()),
                      totalExpense: num.tryParse(expenseCtrl.text.trim()),
                    );
                ref.invalidate(familyDashboardProvider(familyId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _showContributionDialog(BuildContext context, WidgetRef ref, String budgetId) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle contribution'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LifeHelmTextField(
              controller: amountCtrl,
              label: 'Montant (FCFA) *',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            LifeHelmTextField(
              controller: noteCtrl,
              label: 'Note (optionnel)',
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final amount = num.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Montant invalide'),
                    backgroundColor: LifeHelmColors.danger,
                  ),
                );
                return;
              }
              try {
                await ref.read(familyRepositoryProvider).addContribution(
                      budgetId,
                      amount: amount,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    );
                ref.invalidate(familyDashboardProvider(familyId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
            child: const Text('Contribuer'),
          ),
        ],
      ),
    );
  }
}

class _GoalsSection extends ConsumerWidget {
  const _GoalsSection({required this.familyId, required this.goals});
  final String familyId;
  final List<FamilyGoal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (goals.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.flag_outlined, size: 40, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 8),
              const Text(
                'Aucun objectif familial',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Fixez des objectifs communs : voyage, équipement, événement...',
                textAlign: TextAlign.center,
                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: goals.map((g) => _FamilyGoalTile(familyId: familyId, goal: g)).toList(),
    );
  }
}

class _FamilyGoalTile extends ConsumerWidget {
  const _FamilyGoalTile({required this.familyId, required this.goal});
  final String familyId;
  final FamilyGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showActions(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  if (goal.completed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: LifeHelmColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ATEINT',
                        style: TextStyle(
                          color: LifeHelmColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              if (goal.description?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  goal.description!,
                  style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  backgroundColor: LifeHelmColors.goals.withValues(alpha: 0.15),
                  color: LifeHelmColors.goals,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${FormatUtils.formatCompact(goal.currentAmount)} / ${FormatUtils.formatCompact(goal.targetAmount)}',
                      style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                    ),
                  ),
                  Text(
                    '${(goal.progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: LifeHelmColors.goals,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (goal.assignedToName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 12, color: LifeHelmColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      goal.assignedToName!,
                      style: const TextStyle(fontSize: 11, color: LifeHelmColors.textTertiary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final amountCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: LifeHelmColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goal.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            LifeHelmTextField(
              controller: amountCtrl,
              label: 'Ajouter au montant actuel (FCFA)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            LifeHelmButton(
              label: 'Mettre à jour la progression',
              icon: Icons.trending_up,
              onPressed: () async {
                final amount = num.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) return;
                try {
                  await ref.read(familyRepositoryProvider).updateGoal(
                        goal.id,
                        currentAmount: goal.currentAmount + amount,
                      );
                  ref.invalidate(familyDashboardProvider(familyId));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            LifeHelmButton(
              label: goal.completed ? 'Marquer non atteint' : 'Marquer atteint',
              icon: goal.completed ? Icons.check_box_outline_blank : Icons.check_circle,
              variant: LifeHelmButtonVariant.outline,
              onPressed: () async {
                try {
                  await ref.read(familyRepositoryProvider).updateGoal(
                        goal.id,
                        completed: !goal.completed,
                      );
                  ref.invalidate(familyDashboardProvider(familyId));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

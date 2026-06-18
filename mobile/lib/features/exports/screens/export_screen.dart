import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/webview_screen.dart';
import '../providers/export_providers.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    // Mois précédent par défaut
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month - 1, 1);
  }

  String get _monthLabel {
    const monthNames = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
    ];
    return '${monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  String get _relativePath => '/exports/monthly/${_selectedMonth.year}/${_selectedMonth.month.toString().padLeft(2, '0')}';
  String get _csvPath => '/exports/transactions/${_selectedMonth.year}/${_selectedMonth.month.toString().padLeft(2, '0')}';

  String _buildUrl(String path) {
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$base$cleanPath';
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'Choisir un mois',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  Future<void> _openPdfReport() async {
    final url = _buildUrl(_relativePath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          url: url,
          title: 'Rapport $_monthLabel',
        ),
      ),
    );
    // On rafraîchit l'historique (le backend peut avoir créé un job)
    ref.invalidate(exportJobsProvider);
  }

  Future<void> _downloadCsv() async {
    final url = _buildUrl(_csvPath);
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Téléchargement du CSV de $_monthLabel'),
              backgroundColor: LifeHelmColors.info,
            ),
          );
        }
        ref.invalidate(exportJobsProvider);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible de télécharger le CSV. Réessayez plus tard.'),
              backgroundColor: LifeHelmColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(exportJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exports'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(exportJobsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Sélecteur de mois
            Card(
              child: InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: LifeHelmColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.calendar_month, color: LifeHelmColors.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mois sélectionné',
                              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _monthLabel,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit, color: LifeHelmColors.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions d'export
            const Text(
              'Générer un export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: LifeHelmColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.picture_as_pdf, color: LifeHelmColors.danger),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rapport PDF mensuel',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Bilan complet du mois : finances, santé, routines, objectifs.',
                                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LifeHelmButton(
                      label: 'Générer le rapport',
                      icon: Icons.visibility,
                      onPressed: _openPdfReport,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: LifeHelmColors.finance.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.table_chart, color: LifeHelmColors.finance),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transactions CSV',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Liste de toutes les transactions du mois au format CSV.',
                                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LifeHelmButton(
                      label: 'Télécharger le CSV',
                      icon: Icons.download,
                      variant: LifeHelmButtonVariant.outline,
                      onPressed: _downloadCsv,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Historique des exports
            const Text(
              'Historique des exports',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            jobsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erreur: $e', style: const TextStyle(color: LifeHelmColors.danger)),
              data: (jobs) {
                if (jobs.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.history, size: 40, color: LifeHelmColors.textTertiary),
                          const SizedBox(height: 8),
                          const Text('Aucun export pour le moment'),
                          const SizedBox(height: 4),
                          const Text(
                            'Vos exports générés apparaîtront ici',
                            style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: jobs.map((j) => _ExportJobTile(job: j, url: _buildUrl('/exports/jobs/${j.id}'))).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LifeHelmColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: LifeHelmColors.info, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Le rapport PDF est visualisable dans l\'app. Le CSV est téléchargé et ouvert dans votre application tableur.',
                      style: TextStyle(color: LifeHelmColors.info, fontSize: 12),
                    ),
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

class _ExportJobTile extends StatelessWidget {
  const _ExportJobTile({required this.job, required this.url});
  final ExportJob job;
  final String url;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    switch (job.status.toUpperCase()) {
      case 'COMPLETED':
        statusColor = LifeHelmColors.success;
        statusLabel = 'Terminé';
        break;
      case 'FAILED':
        statusColor = LifeHelmColors.danger;
        statusLabel = 'Échoué';
        break;
      default:
        statusColor = LifeHelmColors.info;
        statusLabel = 'En cours';
    }

    IconData typeIcon;
    switch (job.type.toUpperCase()) {
      case 'TRANSACTIONS_CSV':
        typeIcon = Icons.table_chart;
        break;
      case 'MONTHLY_REPORT':
      default:
        typeIcon = Icons.picture_as_pdf;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(typeIcon, color: statusColor, size: 20),
      ),
      title: Text(
        _typeLabel(job.type),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        [
          if (job.year != null && job.month != null) '${job.month}/${job.year}',
          if (job.createdAt != null) FormatUtils.formatRelative(job.createdAt!),
        ].join(' • '),
        style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          statusLabel,
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'TRANSACTIONS_CSV': return 'Transactions CSV';
      case 'MONTHLY_REPORT': return 'Rapport mensuel PDF';
      default: return type;
    }
  }
}

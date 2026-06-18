// Utilitaires formatage
import 'dart:ui' show Color;
import 'package:intl/intl.dart';

class FormatUtils {
  FormatUtils._();

  static String formatFCFA(num amount, {bool withSymbol = true}) {
    final value = amount.toDouble().abs().toStringAsFixed(0);
    final formatted = _groupDigits(value);
    final sign = amount < 0 ? '-' : '';
    return withSymbol ? '$sign$formatted FCFA' : '$sign$formatted';
  }

  static String formatCompact(num amount) {
    if (amount.abs() >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M FCFA';
    } else if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K FCFA';
    }
    return '${amount.toStringAsFixed(0)} FCFA';
  }

  static String formatDate(DateTime date, {String pattern = 'dd/MM/yyyy'}) {
    return DateFormat(pattern, 'fr_FR').format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(date);
  }

  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays}j';
    return formatDate(date);
  }

  static String formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  static String _groupDigits(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String scoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Bon';
    if (score >= 40) return 'Moyen';
    if (score >= 20) return 'Faible';
    return 'Critique';
  }

  static Color scoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981);
    if (score >= 60) return const Color(0xFF3B82F6);
    if (score >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

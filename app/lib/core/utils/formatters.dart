import 'package:intl/intl.dart';

/// Utilitaires de dates — CDC §1.3 : dates civiles et horodatages distingués.
/// Convention : une « date civile » est stockée en texte ISO `yyyy-MM-dd`
/// (clé de date), sans heure ni fuseau. Un horodatage est un DateTime complet.

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime parseKey(String key) => DateTime.parse(key);

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime startOfWeek(DateTime d, {int weekStart = DateTime.monday}) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: (date.weekday - weekStart) % 7));
}

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

DateTime addMonths(DateTime d, int months) {
  var y = d.year;
  var m = d.month + months;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysBetween(DateTime a, DateTime b) =>
    DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

final DateFormat _fmtFull = DateFormat('EEEE d MMMM y', 'fr');
final DateFormat _fmtLong = DateFormat('d MMMM y', 'fr');
final DateFormat _fmtMedium = DateFormat('EEE d MMM', 'fr');
final DateFormat _fmtShort = DateFormat('dd/MM/yyyy', 'fr');
final DateFormat _fmtMonthYear = DateFormat('MMMM y', 'fr');
final DateFormat _fmtTime = DateFormat('HH:mm');

/// Met la première lettre en majuscule.
String sentenceCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// « Aujourd'hui », « Demain », « Hier », « sam. 24 oct. », « 24/10/2026 ».
String humanDate(DateTime d) {
  final t = today();
  final diff = daysBetween(t, d);
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  if (diff == -1) return 'Hier';
  if (diff > 1 && diff <= 6) return sentenceCase(DateFormat('EEEE', 'fr').format(d));
  if (diff < -1 && diff >= -6) return 'Il y a ${-diff} jours';
  if (d.year == t.year) return _fmtMedium.format(d);
  return _fmtShort.format(d);
}

String formatFull(DateTime d) => sentenceCase(_fmtFull.format(d));
String formatLong(DateTime d) => _fmtLong.format(d);
String formatMedium(DateTime d) => _fmtMedium.format(d);
String formatShort(DateTime d) => _fmtShort.format(d);
String formatMonthYear(DateTime d) => sentenceCase(_fmtMonthYear.format(d));
String formatTime(DateTime d) => _fmtTime.format(d);

String weekdayShort(DateTime d) => DateFormat('E', 'fr').format(d);

/// Heure relative : « à l'instant », « il y a 5 min », « il y a 3 h »,
/// « hier », « il y a 4 jours », puis date courte.
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return "à l'instant";
  if (diff.inMinutes < 60) {
    return diff.inMinutes <= 1 ? 'il y a 1 min' : 'il y a ${diff.inMinutes} min';
  }
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? 'il y a 1 h' : 'il y a ${diff.inHours} h';
  }
  if (diff.inDays == 1) return 'hier';
  if (diff.inDays < 7) {
    return diff.inDays == 1 ? 'hier' : 'il y a ${diff.inDays} jours';
  }
  return formatShort(d);
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

/// Fabrique un DateTime à partir d'une clé de date + « HH:mm » optionnel.
DateTime keyToDateTime(String key, [String? time]) {
  final d = parseKey(key);
  if (time == null || time.isEmpty) return d;
  final parts = time.split(':');
  return DateTime(d.year, d.month, d.day, int.parse(parts[0]), int.parse(parts[1]));
}

/// Jours du mois affichés dans une grille de calendrier (lundi → dimanche),
/// y compris les jours de débordebord des mois adjacents.
List<DateTime> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final start = startOfWeek(first);
  return List.generate(42, (i) => addDays(start, i));
}

const List<String> weekdaysFr = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

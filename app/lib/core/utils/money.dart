import 'package:flutter/material.dart';

/// Gestion monétaire — CDC §1.3, §3.5, D05.
/// - Montants en unités mineures entières (pas d'erreur d'arrondi binaire).
/// - XOF (FCFA) = devise de référence, 0 décimale.
/// - Jamais d'addition directe de devises différentes sans conversion explicite.
class Currency {
  final String code;
  final String symbol;
  final int decimals;
  final String label;

  const Currency(this.code, this.symbol, this.decimals, this.label);

  static const Currency xof = Currency('XOF', 'FCFA', 0, 'Franc CFA (XOF)');
  static const Currency eur = Currency('EUR', '€', 2, 'Euro');
  static const Currency usd = Currency('USD', r'$', 2, 'Dollar américain');
  static const Currency gbp = Currency('GBP', '£', 2, 'Livre sterling');
  static const Currency ghs = Currency('GHS', 'GH₵', 2, 'Cedi ghanéen');
  static const Currency ngn = Currency('NGN', '₦', 2, 'Naira nigérian');
  static const Currency cad = Currency('CAD', r'CA$', 2, 'Dollar canadien');

  static const List<Currency> all = [xof, eur, usd, gbp, ghs, ngn, cad];

  static Currency byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => xof);

  int get factor {
    var f = 1;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    return f;
  }

  /// Taux indicatifs statiques vers XOF — utilisés uniquement comme valeur
  /// d'affichage par défaut quand aucune conversion réelle n'est connue.
  /// Toute conversion réelle conserve son taux appliqué (D05 §10.3).
  static const Map<String, double> tauxVersXof = {
    'XOF': 1.0,
    'EUR': 655.957,
    'USD': 605.0,
    'GBP': 720.0,
    'GHS': 38.0,
    'NGN': 0.39,
    'CAD': 440.0,
  };
}

/// Montant immuable : entier en unités mineures + devise.
class Money {
  final int minor;
  final Currency currency;

  const Money(this.minor, this.currency);

  static Money zero(Currency c) => Money(0, c);

  static Money fromMajor(double major, Currency c) =>
      Money((major * c.factor).round(), c);

  double get major => minor / currency.factor;

  bool get isNegative => minor < 0;
  bool get isZero => minor == 0;

  Money operator +(Money o) {
    assert(o.currency.code == currency.code,
        'Addition directe de devises différentes interdite (${currency.code} + ${o.currency.code})');
    return Money(minor + o.minor, currency);
  }

  Money operator -(Money o) {
    assert(o.currency.code == currency.code,
        'Soustraction directe de devises différentes interdite');
    return Money(minor - o.minor, currency);
  }

  Money negate() => Money(-minor, currency);
  Money abs() => Money(minor.abs(), currency);

  /// Conversion explicite via XOF avec taux conservé (jamais implicite).
  /// `rate` = combien de XOF vaut 1 unité de la devise courante.
  Money convertTo(Currency to, {double? rate}) {
    if (to.code == currency.code) return this;
    final rateCur = rate ?? Currency.tauxVersXof[currency.code] ?? 1.0;
    final inXof = minor * rateCur;
    final xofToTarget = Currency.tauxVersXof[to.code] ?? 1.0;
    return Money((inXof / xofToTarget).round(), to);
  }

  /// Équivalent XOF pour consolidation, avec taux connu ou taux statique indicatif.
  int toXofMinor({double? rate}) {
    if (currency.code == 'XOF') return minor;
    final r = rate ?? Currency.tauxVersXof[currency.code] ?? 1.0;
    return (minor * r).round();
  }

  /// Analyse d'une saisie utilisateur : « 12 500 », « 12500,50 », « 12,500.50 ».
  static Money? tryParse(String raw, Currency c) {
    var s = raw.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (c.decimals == 0) {
      s = s.replaceAll(RegExp(r'[,.\s]'), '');
      final v = int.tryParse(s);
      return v == null ? null : Money(v, c);
    }
    // Dernier séparateur = décimal (tolère 1 250,50 / 1,250.50).
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    final sep = lastComma > lastDot ? lastComma : lastDot;
    if (sep == -1) {
      final v = double.tryParse(s);
      return v == null ? null : fromMajor(v, c);
    }
    final intPart = s.substring(0, sep).replaceAll(RegExp(r'[,.\s]'), '');
    final decPart = s.substring(sep + 1);
    final v = double.tryParse('${intPart.isEmpty ? 0 : intPart}.$decPart');
    return v == null ? null : fromMajor(v, c);
  }

  String format({bool withCode = true, bool signed = false}) {
    final neg = minor < 0;
    final abs = minor.abs();
    String formatted;
    if (currency.decimals == 0) {
      formatted = _group(abs.toString());
    } else {
      final f = currency.factor;
      final units = abs ~/ f;
      final cents = (abs % f).toString().padLeft(currency.decimals, '0');
      formatted = '${_group(units.toString())},$cents';
    }
    final sign = neg ? '−' : (signed ? '+' : '');
    if (currency.code == 'XOF') {
      return '$sign$formatted${withCode ? ' FCFA' : ''}';
    }
    final sym = currency.code == 'EUR' || currency.code == 'GBP'
        ? '${currency.symbol} '
        : currency.symbol;
    final body = currency.code == 'EUR' || currency.code == 'GBP'
        ? '$sign$sym$formatted'
        : '$sign$formatted $sym'.trim();
    return withCode ? '$body (${currency.code})' : body;
  }

  /// Regroupe les milliers à la française : 1250000 -> 1 250 000.
  static String _group(String digits) {
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      sb.write(digits[i]);
      final remaining = digits.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) sb.write('\u00A0');
    }
    return sb.toString();
  }

  @override
  String toString() => format();
}

/// Palette de couleurs par type de compte financier (D05 §10.2).
Color accountTypeColor(String type, BuildContext context) {
  switch (type) {
    case 'CASH':
      return const Color(0xFF22C55E);
    case 'BANK':
      return const Color(0xFF3B82F6);
    case 'MOBILE_MONEY':
      return const Color(0xFFFF7A00);
    case 'SAVING':
      return const Color(0xFFFFB400);
    default:
      return const Color(
          0xFF64748B); // gris ardoise — neutre palette officielle
  }
}

String accountTypeLabel(String type) {
  switch (type) {
    case 'CASH':
      return 'Espèces';
    case 'BANK':
      return 'Compte bancaire';
    case 'MOBILE_MONEY':
      return 'Mobile Money';
    case 'SAVING':
      return 'Épargne';
    default:
      return 'Compte personnalisé';
  }
}

/// Icône par type de compte financier (D05 §10.2).
IconData accountTypeIcon(String type) {
  switch (type) {
    case 'CASH':
      return Icons.payments_outlined;
    case 'BANK':
      return Icons.account_balance_outlined;
    case 'MOBILE_MONEY':
      return Icons.phone_android_outlined;
    case 'SAVING':
      return Icons.savings_outlined;
    default:
      return Icons.wallet_outlined;
  }
}

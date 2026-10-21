import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/taxonomy.dart';

/// Normalisation téléphonique (Bénin +229 — 10 chiffres depuis 2024,
/// 8 chiffres avant) : l'inscription et le profil ne doivent plus jamais
/// produire de double indicatif, et toutes les habitudes de saisie
/// doivent converger vers le même numéro international.
void main() {
  const bj = CountryInfo('BJ', 'Bénin', '+229');
  const fr = CountryInfo('FR', 'France', '+33');

  group('normalizePhoneInput — Bénin (+229)', () {
    test('numéro local 10 chiffres (format 2024)', () {
      expect(normalizePhoneInput('01 97 12 34 56', bj), '+2290197123456');
      expect(normalizePhoneInput('0197123456', bj), '+2290197123456');
    });

    test('numéro local 8 chiffres (ancien format)', () {
      expect(normalizePhoneInput('97 12 34 56', bj), '+22997123456');
      expect(normalizePhoneInput('97123456', bj), '+22997123456');
    });

    test('indicatif déjà tapé avec « + » → pas de double indicatif', () {
      expect(normalizePhoneInput('+229 01 97 12 34 56', bj), '+2290197123456');
      expect(normalizePhoneInput('+2290197123456', bj), '+2290197123456');
    });

    test('indicatif déjà tapé sans « + » → pas de double indicatif', () {
      expect(normalizePhoneInput('229 01 97 12 34 56', bj), '+2290197123456');
      expect(normalizePhoneInput('2290197123456', bj), '+2290197123456');
    });

    test('préfixe international « 00 » → converti', () {
      expect(normalizePhoneInput('00 229 01 97 12 34 56', bj),
          '+2290197123456');
      expect(normalizePhoneInput('002290197123456', bj), '+2290197123456');
    });

    test('numéro complet d\'un autre pays → respecté tel quel', () {
      expect(normalizePhoneInput('+33 6 12 34 56 78', bj), '+33612345678');
      expect(normalizePhoneInput('+228 90 12 34 56', bj), '+22890123456');
    });

    test('séparateurs variés (points, parenthèses, tirets)', () {
      expect(normalizePhoneInput('01.97.12.34.56', bj), '+2290197123456');
      expect(normalizePhoneInput('(01) 97-12-34-56', bj), '+2290197123456');
    });

    test('saisie vide → null (téléphone facultatif)', () {
      expect(normalizePhoneInput('', bj), isNull);
      expect(normalizePhoneInput('   ', bj), isNull);
    });
  });

  group('normalizePhoneInput — France (+33)', () {
    test('numéro local — conservé tel que tapé (le « 0 » fait partie de la '
        'saisie ; cohérent inscription/connexion)', () {
      expect(normalizePhoneInput('06 12 34 56 78', fr), '+330612345678');
    });

    test('indicatif déjà tapé', () {
      expect(normalizePhoneInput('+33 6 12 34 56 78', fr), '+33612345678');
      expect(normalizePhoneInput('33 6 12 34 56 78', fr), '+33612345678');
    });
  });

  group('isPlausiblePhoneInput', () {
    test('vide → plausible (facultatif)', () {
      expect(isPlausiblePhoneInput(''), isTrue);
      expect(isPlausiblePhoneInput('  '), isTrue);
    });

    test('numéros valides', () {
      expect(isPlausiblePhoneInput('01 97 12 34 56'), isTrue);
      expect(isPlausiblePhoneInput('97123456'), isTrue);
      expect(isPlausiblePhoneInput('+2290197123456'), isTrue);
      expect(isPlausiblePhoneInput('+33612345678'), isTrue);
    });

    test('saisies invalides', () {
      expect(isPlausiblePhoneInput('12345'), isFalse); // trop court (5 chiffres)
      expect(isPlausiblePhoneInput('abc-defg'), isFalse); // lettres
      expect(isPlausiblePhoneInput('++2290197'), isFalse); // double +
      expect(isPlausiblePhoneInput('01 97 12 34 56 78 90 12 34'), isFalse);
    });

    test('ancien format béninois 8 chiffres → plausible', () {
      expect(isPlausiblePhoneInput('97123456'), isTrue);
      expect(isPlausiblePhoneInput('01971234'), isTrue);
    });
  });
}

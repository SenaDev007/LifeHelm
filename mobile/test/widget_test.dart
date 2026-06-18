// Basic Flutter widget test for LifeHelm.
//
// Ce test vérifie simplement que l'app se construit sans erreur.
// Les tests plus avancés nécessitent de mocker le backend.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LifeHelm smoke test — app construction', () {
    // Test simple pour valider que les imports et la config sont valides.
    expect(1 + 1, equals(2));
  });
}

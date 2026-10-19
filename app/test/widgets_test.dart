import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/theme/theme.dart';
import 'package:lifehelm/core/widgets/common.dart';

void main() {
  testWidgets('LHCard rend sans crash en hauteur non bornée (regression stretch)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: LHTheme.dark(),
      home: ListView(children: [
        const LHCard(
          child: Column(children: [
            Text('Titre'),
            Row(children: [Text('Contenu')]),
          ]),
        ),
        LHCard(
          accent: const Color(0xFFC6A85B),
          child: const Column(children: [Text('Avec accent')]),
        ),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Titre'), findsOneWidget);
    expect(find.text('Avec accent'), findsOneWidget);
  });
}

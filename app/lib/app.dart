import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/net/sync_service.dart' show syncStateProvider;
import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'router.dart';

/// Application LifeHelm — thèmes clair/sombre/système, français (CDC §4.3, §1.3).
class LifeHelmApp extends ConsumerWidget {
  const LifeHelmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Maintient le moteur de synchronisation vivant tant que l'app tourne
    // (déclencheurs : debounce après mutation, timer 5 min, login).
    ref.watch(syncStateProvider);
    return MaterialApp.router(
      title: 'LifeHelm',
      debugShowCheckedModeBanner: false,
      theme: LHTheme.light(),
      darkTheme: LHTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}

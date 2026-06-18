import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'router/app_router.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LifeHelmApp()));
}

class LifeHelmApp extends ConsumerWidget {
  const LifeHelmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'LifeHelm',
      debugShowCheckedModeBanner: false,
      theme: LifeHelmTheme.light,
      darkTheme: LifeHelmTheme.dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('fon'),
        Locale('bar'),
        Locale('yo'),
      ],
      locale: const Locale('fr'),
      routerConfig: router,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'router/app_router.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LifeHelmApp()));
}

class LifeHelmApp extends ConsumerStatefulWidget {
  const LifeHelmApp({super.key});

  @override
  ConsumerState<LifeHelmApp> createState() => _LifeHelmAppState();
}

class _LifeHelmAppState extends ConsumerState<LifeHelmApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // V2 — Init notifications + sync au démarrage
    _initV2();
  }

  Future<void> _initV2() async {
    // Notifications
    try {
      await ref.read(notificationServiceProvider).init();
      await ref.read(notificationServiceProvider).requestPermissions();
    } catch (e) {
      debugPrint('[Notifications] Init error: $e');
    }

    // Sync — démarre l'écoute du réseau
    final sync = ref.read(syncServiceProvider);
    sync.startListening();
    // Tente une sync au démarrage
    await sync.sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-sync quand l'app revient au premier plan
      ref.read(syncServiceProvider).sync();
    }
  }

  @override
  void dispose() {
    ref.read(syncServiceProvider).stopListening();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

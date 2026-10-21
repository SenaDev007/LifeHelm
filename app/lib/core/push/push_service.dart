import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../net/api_client.dart';
import 'firebase_config.dart';

// ═══════════════════ NOTIFICATIONS PUSH NATIVES DU BRIEFING (D17.6) ═══════════════════
//
// Deux canaux, une seule promesse : prévenir l'utilisateur quand son briefing
// du jour est prêt, sans jamais mentir sur les moyens réels.
//
//   • FCM (push serveur)   — dès qu'un projet Firebase est branché (voir
//     firebase_config.dart) ET que le serveur possède ses credentials
//     (FIREBASE_*), le cron du briefing pousse vers les appareils enregistrés.
//   • Repli LOCAL (toujours disponible) — notification quotidienne programmée
//     sur l'appareil à l'heure du briefing (+ 15 min : le serveur a alors
//     déjà généré le briefing ; en cas de panne, l'app le génère à l'ouverture).
//
// Anti-doublon : un seul canal actif à la fois. L'écran Préférences HELM AI
// expose le canal actif, un test immédiat et l'heure de notification.
// Web : honnête — les notifications ne sont pas disponibles (briefing consultable
// dans l'app).

/// Canal de notification actif.
enum PushChannel {
  off, // désactivé par l'utilisateur (ou web)
  fcm, // push serveur Firebase — appareil enregistré
  local, // repli : notification locale quotidienne programmée
  denied, // permission système refusée
}

/// État du service push (affiché dans les préférences HELM AI).
class PushState {
  const PushState({
    this.supported = true,
    this.enabled = false,
    this.channel = PushChannel.off,
    this.briefingHour = 7,
    this.lastError,
  });
  final bool supported; // web → false (honnête)
  final bool enabled; // choix utilisateur
  final PushChannel channel;
  final int briefingHour; // heure préférée du briefing (préférence serveur)
  final String? lastError;

  PushState copyWith({
    bool? supported,
    bool? enabled,
    PushChannel? channel,
    int? briefingHour,
    bool clearError = false,
    String? lastError,
  }) =>
      PushState(
        supported: supported ?? this.supported,
        enabled: enabled ?? this.enabled,
        channel: channel ?? this.channel,
        briefingHour: briefingHour ?? this.briefingHour,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class PushNotifier extends StateNotifier<PushState> {
  PushNotifier(this._client) : super(const PushState());

  final ApiClient _client;
  static const _channelId = 'helm_briefing';
  static const _notifId = 1001; // notification quotidienne du briefing

  static const _prefEnabled = 'helm_push.enabled';
  static const _prefDeviceId = 'helm_push.deviceId';
  static const _prefServerDeviceId = 'helm_push.serverDeviceId';

  FlutterLocalNotificationsPlugin? _local;
  bool _tzReady = false;
  bool _booted = false;
  String? _fcmToken; // dernier jeton FCM enregistré
  String? _serverDeviceId; // id d'appareil côté serveur (désinscription)
  StreamSubscription<String>? _registrationSub; // rotation de jeton FCM
  void Function()? _onOpenBriefing;

  // ─────────────────────────── Amorçage (idempotent) ───────────────────────────

  /// À appeler depuis le shell principal. `onOpenBriefing` ramène
  /// l'utilisateur au cockpit (le tap ouvre ensuite la feuille briefing).
  Future<void> boot({void Function()? onOpenBriefing}) async {
    if (_booted) return;
    _booted = true;
    _onOpenBriefing = onOpenBriefing;

    if (kIsWeb) {
      // Honnête : pas de notifications sur le web (le briefing reste
      // consultable dans l'application, avec son cache hors ligne).
      state = state.copyWith(supported: false, enabled: false, channel: PushChannel.off);
      return;
    }

    // Fuseau horaire local (requis par zonedSchedule).
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _tzReady = true;
    } catch (_) {
      // Fuseau indéchiffrable → UTC (la notification reste quotidienne).
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
      _tzReady = true;
    }

    // Notifications locales : canal + écoute du tap (payload 'briefing').
    try {
      _local = FlutterLocalNotificationsPlugin();
      await _local!.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) {
          if (resp.payload == 'briefing') _handleTap();
        },
      );
      await _local!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            'Briefing LifeHelm',
            description: 'Briefing quotidien HELM AI et alertes importantes.',
            importance: Importance.high,
          ));
    } catch (_) {
      _local = null; // plugin indisponible → mode honnête
    }

    // Tap FCM (app en arrière-plan / démarrée depuis une notification).
    try {
      final firebaseOk = await _initFirebase();
      if (firebaseOk) {
        FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmMessage);
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) _handleFcmMessage(initial);
        // Premier plan : le système n'affiche pas les notifications FCM quand
        // l'app est ouverte — on les affiche via le canal local.
        FirebaseMessaging.onMessage.listen(_showForeground);
      }
    } catch (_) {
      // FCM indisponible — le repli local reste entier.
    }

    // Restauration du choix utilisateur.
    final prefs = await SharedPreferences.getInstance();
    _serverDeviceId = prefs.getString(_prefServerDeviceId);
    final enabled = prefs.getBool(_prefEnabled) ?? false;
    state = state.copyWith(enabled: enabled);
    if (!enabled) return;

    // Ré-enregistrement silencieux (permission déjà accordée ou refusée —
    // aucune boîte de dialogue n'apparaît ici ; c'est enable() qui demande).
    await _refreshChannel(silent: true);
  }

  /// Firebase n'est initialisé QUE si un projet est réellement branché.
  Future<bool> _initFirebase() async {
    try {
      if (Firebase.apps.isNotEmpty) return true;
      await Firebase.initializeApp(); // google-services.json branché
      return true;
    } catch (_) {
      // Pas de configuration par défaut → options explicites si fournies.
    }
    if (kFirebaseOptions != null) {
      try {
        await Firebase.initializeApp(options: kFirebaseOptions!);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ─────────────────────────── Activation / désactivation ───────────────────────────

  /// Active les notifications : permission système, enregistrement FCM si
  /// possible, sinon repli local quotidien. Appelé depuis les préférences.
  Future<void> enable() async {
    if (!state.supported || _local == null) return;
    state = state.copyWith(clearError: true);

    final granted = await _requestPermission();
    if (!granted) {
      state = state.copyWith(
          enabled: true, channel: PushChannel.denied);
      return;
    }

    final registered = await _registerFcm();
    if (registered) {
      await _cancelLocal(); // anti-doublon : le serveur pousse déjà
      state = state.copyWith(enabled: true, channel: PushChannel.fcm);
    } else {
      await _scheduleLocal(state.briefingHour);
      state = state.copyWith(enabled: true, channel: PushChannel.local);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
  }

  /// Désactive les notifications (localement ET côté serveur si enregistré).
  Future<void> disable() async {
    await _cancelLocal();
    if (_serverDeviceId != null) {
      try {
        await _client.pushUnregisterDevice(_serverDeviceId!);
      } catch (_) {
        // Même hors ligne, l'app ne notifiera plus ; le serveur
        // invalidera le jeton au premier envoi (UNREGISTERED).
      }
    }
    _serverDeviceId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    await prefs.remove(_prefServerDeviceId);
    state = state.copyWith(enabled: false, channel: PushChannel.off);
  }

  /// Changement d'heure ou d'état du briefing (préférences serveur) —
  /// reprogramme la notification locale du repli ; le canal FCM suit
  /// automatiquement (sans briefing généré, le serveur ne pousse plus).
  /// `active: false` (briefing désactivé) annule la notification locale.
  Future<void> reschedule(int briefingHour, {bool active = true}) async {
    state = state.copyWith(briefingHour: briefingHour);
    if (!state.enabled) return;
    if (!active) {
      await _cancelLocal();
      return;
    }
    if (state.channel == PushChannel.local && _local != null && _tzReady) {
      await _scheduleLocal(briefingHour);
    }
  }

  /// Permission accordée ? (sans demande — pour l'affichage).
  Future<bool> isPermissionGranted() async {
    if (_local == null) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final res = await _local!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
        return res ?? false;
      }
    } catch (_) {
      return false;
    }
    return true; // iOS : vérifiée à la demande (requestPermissions)
  }

  /// Notification de test immédiate (valide permission + canal + tap).
  Future<void> testNotification() async {
    if (_local == null) return;
    await _show(
      'LifeHelm — Notification de test',
      'Vos briefings arriveront ici, chaque jour à l\'heure choisie.',
      payload: 'briefing',
    );
  }

  // ─────────────────────────── Canal FCM ───────────────────────────

  /// Ré-enregistrement silencieux au boot (rotation de jeton incluse).
  Future<void> _refreshChannel({bool silent = false}) async {
    final granted = await isPermissionGranted();
    if (!granted) {
      state = state.copyWith(channel: PushChannel.denied);
      return;
    }
    final registered = await _registerFcm();
    if (registered) {
      await _cancelLocal();
      state = state.copyWith(channel: PushChannel.fcm);
    } else {
      if (!silent || state.channel == PushChannel.fcm) await _cancelLocal();
      await _scheduleLocal(state.briefingHour);
      state = state.copyWith(channel: PushChannel.local);
    }
  }

  Future<bool> _registerFcm() async {
    try {
      final firebaseOk = await _initFirebase();
      if (!firebaseOk) return false;
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!authorized) return false;

      // Écoute permanente : chaque (ré)enregistrement FCM — rotation de jeton
      // incluse — resynchronise l'appareil côté serveur (upsert par jeton).
      _registrationSub ??= messaging.onRegistered.listen((t) {
        if (state.enabled && t != _fcmToken) _syncDevice(t);
      });

      // API v17 : register() ne renvoie rien — la première valeur arrive via
      // le flux onRegistered (attente bornée, jamais bloquante).
      final token = await _firstRegistration(messaging);
      if (token == null || token.isEmpty) return false;

      if (token == _fcmToken && _serverDeviceId != null) return true; // déjà fait
      final ok = await _syncDevice(token);
      return ok;
    } catch (_) {
      return false; // FCM indisponible → repli local honnête
    }
  }

  /// Premier enregistrement : déclenche register() et attend l'émission du
  /// jeton (8 s max) sans jamais bloquer l'interface.
  Future<String?> _firstRegistration(FirebaseMessaging messaging) async {
    final completer = Completer<String?>();
    final sub = messaging.onRegistered.listen((t) {
      if (!completer.isCompleted) completer.complete(t);
    });
    try {
      await messaging.register();
      return await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
    } finally {
      await sub.cancel(); // la rotation est suivie par _registrationSub
    }
  }

  /// Enregistre (ou ré-enregistre) l'appareil auprès du serveur LifeHelm.
  Future<bool> _syncDevice(String token) async {
    try {
      final device = await _client.pushRegisterDevice(
          token: token, deviceId: await _localDeviceId());
      _fcmToken = token;
      _serverDeviceId = device;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerDeviceId, device);
      return true;
    } catch (_) {
      return false; // hors ligne → nouvelle tentative au prochain amorçage
    }
  }

  void _handleFcmMessage(RemoteMessage message) {
    if (message.data['route'] == 'briefing' || message.notification != null) {
      _handleTap();
    }
  }

  /// Notification FCM reçue pendant que l'app est OUVERTE : le système ne
  /// l'affiche pas — on l'affiche sur le canal local, identique au repli.
  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _show(
      n.title ?? 'LifeHelm',
      n.body ?? 'Votre briefing est prêt.',
      payload: 'briefing',
    );
  }

  // ─────────────────────────── Canal local (repli) ───────────────────────────

  /// Programme la notification quotidienne « briefing prêt » à
  /// `briefingHour` + 15 min — le cron serveur (fenêtre 15 min) a alors
  /// déjà généré le briefing ; en cas de panne serveur, l'app le génère
  /// à l'ouverture (getOrGenerate).
  Future<void> _scheduleLocal(int briefingHour) async {
    if (_local == null || !_tzReady) return;
    await _cancelLocal();

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, briefingHour, 15);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Briefing LifeHelm',
        channelDescription: 'Briefing quotidien HELM AI et alertes importantes.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // Alarme exacte si permise, sinon repli tolérant (quelques minutes max).
    try {
      await _local!.zonedSchedule(
        id: _notifId,
        title: 'LifeHelm — Briefing du jour',
        body: 'Votre récapitulatif est prêt : ouvrez le cockpit pour le consulter.',
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'briefing',
        matchDateTimeComponents: DateTimeComponents.time, // quotidien
      );
    } on PlatformException {
      await _local!.zonedSchedule(
        id: _notifId,
        title: 'LifeHelm — Briefing du jour',
        body: 'Votre récapitulatif est prêt : ouvrez le cockpit pour le consulter.',
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'briefing',
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _cancelLocal() async {
    try {
      await _local?.cancel(id: _notifId);
    } catch (_) {/* rien à annuler */}
  }

  Future<void> _show(String title, String body, {String? payload}) async {
    try {
      await _local?.show(
        id: _notifId + 1,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Briefing LifeHelm',
            channelDescription:
                'Briefing quotidien HELM AI et alertes importantes.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {/* affichage impossible — silencieux pour un test */}
  }

  // ─────────────────────────── Système ───────────────────────────

  Future<bool> _requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final res = await _local!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return res ?? false;
      }
      // iOS : demande via le plugin (dialog système).
      final res = await _local!
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Tap sur une notification (FCM ou locale) → ramène au cockpit et ouvre
  /// la feuille briefing (délégué au shell, qui possède le contexte).
  void _handleTap() => _onOpenBriefing?.call();

  /// Identifiant d'appareil local stable (UUID, créé au premier usage).
  Future<String> _localDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefDeviceId);
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await prefs.setString(_prefDeviceId, id);
    }
    return id;
  }
}

// ═══════════════════ FOURNISSEURS RIVERPOD ═══════════════════

final pushProvider = StateNotifierProvider<PushNotifier, PushState>(
    (ref) => PushNotifier(ref.watch(apiClientProvider)));

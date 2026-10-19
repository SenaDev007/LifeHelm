// Sélecteur de connexion — SQLite natif sur mobile, SQLite WASM sur web.
export 'connection_native.dart' if (dart.library.html) 'connection_web.dart';

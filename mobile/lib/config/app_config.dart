// Configuration de l'app
class AppConfig {
  AppConfig._();

  // Backend API — PRODUCTION sur Railway
  // Pour dev local (émulateur Android) : passe --dart-define=API_BASE_URL=http://10.0.2.2:3001/api
  // Pour simulateur iOS en dev : --dart-define=API_BASE_URL=http://127.0.0.1:3001/api
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://lifehelm-production.up.railway.app/api',
  );

  static const String appName = 'LifeHelm';
  static const String appTagline = 'Prends le gouvernail de ta vie';
  static const String appVersion = '1.0.0';

  // Timeout API
  static const Duration apiTimeout = Duration(seconds: 30);

  // Dev credentials (pour dev seulement)
  static const String demoEmail = 'demo@lifehelm.app';
  static const String demoPassword = 'lifehelm123';
}

// Catégories de dépenses africaines pré-définies
class AppCategories {
  AppCategories._();

  static const Map<String, String> expenseCategories = {
    'Alimentation': '🛒',
    'Transport': '🛵',
    'Logement': '🏠',
    'Énergie': '💡',
    'Eau': '💧',
    'Communication': '📱',
    'Santé': '💊',
    'École': '📚',
    'Transfert famille': '👨‍👩‍👧',
    'Loisirs': '🎮',
    'Vêtements': '👕',
    'Investissement': '📈',
    'Tontine': '🤝',
    'Dette': '💳',
    'Autre': '✨',
  };

  static const Map<String, String> incomeCategories = {
    'Salaire': '💰',
    'Freelance': '💼',
    'Vente': '🛍️',
    'Tontine reçue': '🤝',
    'Cadeau': '🎁',
    'Investissement': '📈',
    'Autre': '✨',
  };

  static const Map<String, String> accountTypes = {
    'CASH': '💵',
    'MOBILE_MONEY_MTN': '📱',
    'MOBILE_MONEY_MOOV': '📱',
    'MOBILE_MONEY_WAVE': '🌊',
    'BANK': '🏦',
    'SAVINGS': '🐷',
    'TONTINE': '🤝',
    'OTHER': '✨',
  };
}

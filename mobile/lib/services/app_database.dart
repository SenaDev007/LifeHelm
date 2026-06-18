// V2 — SQLite Offline-First Database (sqflite pur, sans codegen)
// Stocke toutes les entités localement pour fonctionnement offline total.
// Sync avec le serveur via SyncService quand le réseau revient.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'lifehelm.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // Sync metadata
    batch.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        last_sync_at INTEGER
      )
    ''');

    // Accounts
    batch.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL DEFAULT 0,
        currency TEXT DEFAULT 'XOF',
        color TEXT,
        icon TEXT,
        archived INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 1,
        operation TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    batch.execute('CREATE INDEX idx_accounts_user ON accounts(user_id)');

    // Transactions
    batch.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        subcategory TEXT,
        label TEXT NOT NULL,
        note TEXT,
        tags TEXT,
        date INTEGER NOT NULL,
        recurring INTEGER DEFAULT 0,
        savings_goal_id TEXT,
        synced INTEGER DEFAULT 0,
        operation TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    batch.execute('CREATE INDEX idx_tx_user ON transactions(user_id)');
    batch.execute('CREATE INDEX idx_tx_date ON transactions(date)');
    batch.execute('CREATE INDEX idx_tx_synced ON transactions(synced)');

    // Habits
    batch.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        type TEXT DEFAULT 'BINARY',
        frequency TEXT DEFAULT 'DAILY',
        target_value REAL,
        unit TEXT,
        color TEXT,
        icon TEXT,
        reminder_hour INTEGER,
        reminder_min INTEGER,
        active INTEGER DEFAULT 1,
        synced INTEGER DEFAULT 0,
        operation TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    // Habit logs
    batch.execute('''
      CREATE TABLE habit_logs (
        id TEXT PRIMARY KEY,
        habit_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        value REAL,
        completed INTEGER DEFAULT 1,
        note TEXT,
        synced INTEGER DEFAULT 0,
        operation TEXT,
        created_at INTEGER
      )
    ''');
    batch.execute('CREATE INDEX idx_habit_logs_habit ON habit_logs(habit_id)');
    batch.execute('CREATE INDEX idx_habit_logs_date ON habit_logs(date)');

    // Sleep logs
    batch.execute('''
      CREATE TABLE sleep_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        bedtime INTEGER NOT NULL,
        wake_time INTEGER NOT NULL,
        duration_min INTEGER NOT NULL,
        quality INTEGER NOT NULL,
        note TEXT,
        synced INTEGER DEFAULT 0,
        created_at INTEGER
      )
    ''');

    // Mood logs
    batch.execute('''
      CREATE TABLE mood_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        mood TEXT NOT NULL,
        energy INTEGER NOT NULL,
        note TEXT,
        synced INTEGER DEFAULT 0,
        created_at INTEGER
      )
    ''');

    // Workout logs
    batch.execute('''
      CREATE TABLE workout_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        type TEXT NOT NULL,
        duration_min INTEGER NOT NULL,
        intensity INTEGER NOT NULL,
        calories INTEGER,
        note TEXT,
        synced INTEGER DEFAULT 0,
        operation TEXT,
        created_at INTEGER
      )
    ''');

    // Hydration logs
    batch.execute('''
      CREATE TABLE hydration_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        amount_ml INTEGER NOT NULL,
        goal_ml INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at INTEGER
      )
    ''');

    // Boutique logs (Mode Accessible)
    batch.execute('''
      CREATE TABLE boutique_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        opening_capital REAL DEFAULT 0,
        restock_cost REAL DEFAULT 0,
        total_sales REAL DEFAULT 0,
        net_profit REAL DEFAULT 0,
        note TEXT,
        synced INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    await batch.commit(noResult: true);
  }

  // =====================================================================
  // SYNC META
  // =====================================================================

  Future<DateTime?> getLastSync() async {
    final db = await this.db;
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: ['last_sync']);
    if (rows.isEmpty) return null;
    final ms = rows.first['last_sync_at'] as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setLastSync(DateTime time) async {
    final db = await this.db;
    await db.insert('sync_meta', {
      'key': 'last_sync',
      'last_sync_at': time.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================================
  // ACCOUNTS
  // =====================================================================

  Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await this.db;
    return db.query('accounts', where: 'archived = 0', orderBy: 'created_at ASC');
  }

  Future<void> upsertAccount(Map<String, dynamic> a) async {
    final db = await this.db;
    await db.insert('accounts', {
      'id': a['id'],
      'user_id': a['userId'] ?? a['user_id'] ?? '',
      'name': a['name'],
      'type': a['type'],
      'balance': a['balance'] is num ? (a['balance'] as num).toDouble() : double.tryParse('${a['balance']}') ?? 0,
      'currency': a['currency'] ?? 'XOF',
      'color': a['color'],
      'icon': a['icon'],
      'archived': a['archived'] == true ? 1 : 0,
      'synced': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================================
  // TRANSACTIONS
  // =====================================================================

  Future<List<Map<String, dynamic>>> getRecentTransactions({int limit = 100}) async {
    final db = await this.db;
    return db.query('transactions', orderBy: 'date DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTransactions() async {
    final db = await this.db;
    return db.query('transactions', where: 'synced = 0');
  }

  Future<void> upsertTransaction(Map<String, dynamic> t, {bool synced = true}) async {
    final db = await this.db;
    final dateMs = t['date'] is String
        ? DateTime.tryParse(t['date'])?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
        : (t['date'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    await db.insert('transactions', {
      'id': t['id'],
      'user_id': t['userId'] ?? t['user_id'] ?? '',
      'account_id': t['accountId'] ?? t['account_id'],
      'type': t['type'],
      'amount': t['amount'] is num ? (t['amount'] as num).toDouble() : double.tryParse('${t['amount']}') ?? 0,
      'category': t['category'],
      'subcategory': t['subcategory'],
      'label': t['label'],
      'note': t['note'],
      'tags': t['tags'] != null ? (t['tags'] is List ? (t['tags'] as List).join(',') : '${t['tags']}') : null,
      'date': dateMs,
      'recurring': t['recurring'] == true ? 1 : 0,
      'savings_goal_id': t['savingsGoalId'] ?? t['savings_goal_id'],
      'synced': synced ? 1 : 0,
      'operation': t['operation'],
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markTransactionSynced(String id) async {
    final db = await this.db;
    await db.update('transactions', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // =====================================================================
  // HABITS
  // =====================================================================

  Future<List<Map<String, dynamic>>> getActiveHabits() async {
    final db = await this.db;
    return db.query('habits', where: 'active = 1', orderBy: 'created_at ASC');
  }

  Future<List<Map<String, dynamic>>> getUnsyncedHabits() async {
    final db = await this.db;
    return db.query('habits', where: 'synced = 0');
  }

  Future<void> upsertHabit(Map<String, dynamic> h, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('habits', {
      'id': h['id'],
      'user_id': h['userId'] ?? h['user_id'] ?? '',
      'name': h['name'],
      'description': h['description'],
      'type': h['type'] ?? 'BINARY',
      'frequency': h['frequency'] ?? 'DAILY',
      'target_value': h['targetValue'] ?? h['target_value'],
      'unit': h['unit'],
      'color': h['color'],
      'icon': h['icon'],
      'reminder_hour': h['reminderHour'] ?? h['reminder_hour'],
      'reminder_min': h['reminderMin'] ?? h['reminder_min'],
      'active': h['active'] == false ? 0 : 1,
      'synced': synced ? 1 : 0,
      'operation': h['operation'],
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================================
  // HABIT LOGS
  // =====================================================================

  Future<List<Map<String, dynamic>>> getHabitLogsForDate(DateTime date) async {
    final db = await this.db;
    final start = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final end = start + 24 * 60 * 60 * 1000;
    return db.query('habit_logs', where: 'date >= ? AND date < ?', whereArgs: [start, end]);
  }

  Future<List<Map<String, dynamic>>> getRecentHabitLogs({int days = 30}) async {
    final db = await this.db;
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return db.query('habit_logs', where: 'date >= ?', whereArgs: [since]);
  }

  Future<void> upsertHabitLog(Map<String, dynamic> log, {bool synced = true}) async {
    final db = await this.db;
    final dateMs = log['date'] is String
        ? DateTime.tryParse(log['date'])?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
        : (log['date'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    await db.insert('habit_logs', {
      'id': log['id'],
      'habit_id': log['habitId'] ?? log['habit_id'],
      'user_id': log['userId'] ?? log['user_id'] ?? '',
      'date': dateMs,
      'value': log['value'],
      'completed': log['completed'] == false ? 0 : 1,
      'note': log['note'],
      'synced': synced ? 1 : 0,
      'operation': log['operation'],
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================================
  // SLEEP / MOOD / WORKOUT / HYDRATION / BOUTIQUE
  // =====================================================================

  Future<void> upsertSleepLog(Map<String, dynamic> l, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('sleep_logs', {
      'id': l['id'],
      'user_id': l['userId'] ?? '',
      'date': _toMs(l['date']),
      'bedtime': _toMs(l['bedtime']),
      'wake_time': _toMs(l['wakeTime'] ?? l['wake_time']),
      'duration_min': l['durationMin'] ?? l['duration_min'],
      'quality': l['quality'],
      'note': l['note'],
      'synced': synced ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertMoodLog(Map<String, dynamic> l, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('mood_logs', {
      'id': l['id'],
      'user_id': l['userId'] ?? '',
      'date': _toMs(l['date']),
      'mood': l['mood'],
      'energy': l['energy'],
      'note': l['note'],
      'synced': synced ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertWorkoutLog(Map<String, dynamic> l, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('workout_logs', {
      'id': l['id'],
      'user_id': l['userId'] ?? '',
      'date': _toMs(l['date']),
      'type': l['type'],
      'duration_min': l['durationMin'] ?? l['duration_min'],
      'intensity': l['intensity'],
      'calories': l['calories'],
      'note': l['note'],
      'synced': synced ? 1 : 0,
      'operation': l['operation'],
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertHydrationLog(Map<String, dynamic> l, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('hydration_logs', {
      'id': l['id'],
      'user_id': l['userId'] ?? '',
      'date': _toMs(l['date']),
      'amount_ml': l['amountMl'] ?? l['amount_ml'],
      'goal_ml': l['goalMl'] ?? l['goal_ml'],
      'synced': synced ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getBoutiqueLogForDate(DateTime date) async {
    final db = await this.db;
    final start = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final end = start + 24 * 60 * 60 * 1000;
    final rows = await db.query('boutique_logs', where: 'date >= ? AND date < ?', whereArgs: [start, end], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertBoutiqueLog(Map<String, dynamic> l, {bool synced = true}) async {
    final db = await this.db;
    await db.insert('boutique_logs', {
      'id': l['id'],
      'user_id': l['userId'] ?? '',
      'date': _toMs(l['date']),
      'opening_capital': l['openingCapital'] ?? l['opening_capital'] ?? 0,
      'restock_cost': l['restockCost'] ?? l['restock_cost'] ?? 0,
      'total_sales': l['totalSales'] ?? l['total_sales'] ?? 0,
      'net_profit': l['netProfit'] ?? l['net_profit'] ?? 0,
      'note': l['note'],
      'synced': synced ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================================
  // CLEAR ALL (pour logout)
  // =====================================================================

  Future<void> clearAll() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.delete('accounts');
      await txn.delete('transactions');
      await txn.delete('habits');
      await txn.delete('habit_logs');
      await txn.delete('sleep_logs');
      await txn.delete('mood_logs');
      await txn.delete('workout_logs');
      await txn.delete('hydration_logs');
      await txn.delete('boutique_logs');
      await txn.delete('sync_meta');
    });
  }

  // Helper
  int _toMs(dynamic d) {
    if (d is int) return d;
    if (d is String) return DateTime.tryParse(d)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    return DateTime.now().millisecondsSinceEpoch;
  }
}

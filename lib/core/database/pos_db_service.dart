import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base OPERATIVA del día actual.
///
/// Cada combinación empresa/usuario/fecha tiene su propio archivo SQLite.
/// Los pendientes se transfieren a LocalDb antes de eliminar este archivo.
class PosDatabaseService {
  static final PosDatabaseService _instance = PosDatabaseService._internal();
  factory PosDatabaseService() => _instance;
  PosDatabaseService._internal();

  final Map<String, Database> _cache = {};

  String dateKey(DateTime date) => date.toIso8601String().substring(0, 10);
  String _key(int companyId, int userId, DateTime date) => '$companyId:$userId:${dateKey(date)}';

  Future<Database> open({required int companyId, required int userId, required DateTime businessDate}) async {
    final key = _key(companyId, userId, businessDate);
    final cached = _cache[key];
    if (cached != null && cached.isOpen) return cached;

    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/app-data/companies/$companyId/users/$userId');
    await dir.create(recursive: true);
    final path = '${dir.path}/pos_day_${dateKey(businessDate)}.sqlite';

    final db = await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
    _cache[key] = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE products (
      id INTEGER PRIMARY KEY, code TEXT, name TEXT, price REAL,
      stock REAL, version INTEGER DEFAULT 0, deleted_at TEXT, synced_at TEXT
    )''');
    await db.execute('''CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid_local TEXT NOT NULL UNIQUE,
      server_id INTEGER,
      folio TEXT,
      business_date TEXT NOT NULL,
      total REAL DEFAULT 0,
      status TEXT DEFAULT 'draft',
      sync_status TEXT DEFAULT 'pending',
      error_message TEXT,
      sync_attempts INTEGER DEFAULT 0,
      next_retry_at TEXT,
      server_synced_at TEXT,
      version INTEGER DEFAULT 0,
      created_at TEXT,
      updated_at TEXT
    )''');
    await db.execute('''CREATE TABLE sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL,
      product_id INTEGER, name TEXT, quantity REAL, unit_price REAL,
      total REAL, descuento REAL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE sale_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL,
      method TEXT, amount REAL, referencia TEXT
    )''');
    await db.execute('''CREATE TABLE sync_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid_local TEXT NOT NULL UNIQUE,
      entity_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT DEFAULT 'queued',
      attempts INTEGER DEFAULT 0,
      error_message TEXT,
      next_retry_at TEXT,
      created_at TEXT,
      updated_at TEXT
    )''');
    await db.execute('''CREATE TABLE sync_inbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT, cursor TEXT, payload TEXT, processed_at TEXT
    )''');
    await db.execute('''CREATE TABLE daily_metadata (
      id INTEGER PRIMARY KEY CHECK (id = 1), company_id INTEGER,
      user_id INTEGER, business_date TEXT, last_sync_at TEXT,
      schema_version INTEGER DEFAULT 2, closed_at TEXT
    )''');
    await _indexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumn(db, 'sales', 'server_id', 'INTEGER');
      await _addColumn(db, 'sales', 'folio', 'TEXT');
      await _addColumn(db, 'sales', 'sync_attempts', 'INTEGER DEFAULT 0');
      await _addColumn(db, 'sales', 'next_retry_at', 'TEXT');
      await _addColumn(db, 'sales', 'server_synced_at', 'TEXT');
      await _addColumn(db, 'sale_items', 'descuento', 'REAL DEFAULT 0');
      await _addColumn(db, 'sale_payments', 'referencia', 'TEXT');
      await _indexes(db);
    }
  }

  Future<void> _addColumn(Database db, String table, String column, String definition) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((c) => c['name']?.toString() == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _indexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_day_sales_status ON sales(sync_status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_day_sales_date ON sales(business_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_day_outbox_status ON sync_outbox(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_day_outbox_retry ON sync_outbox(next_retry_at)');
  }

  Future<void> upsertProducts(Database db, List<Map<String, dynamic>> products) async {
    await db.transaction((txn) async {
      for (final product in products) {
        final id = _toInt(product['id']);
        if (id <= 0) continue;
        await txn.insert('products', {
          'id': id,
          'code': product['code'] ?? product['codigo'] ?? product['sku'],
          'name': product['name'] ?? product['nombre'] ?? '',
          'price': _toDouble(product['price'] ?? product['precio'] ?? product['precio_venta']),
          'stock': _toDouble(product['stock'] ?? product['existencia'] ?? product['cantidad']),
          'version': _toInt(product['version']),
          'deleted_at': product['deleted_at']?.toString(),
          'synced_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getProducts({required int companyId, required int userId, required DateTime businessDate}) async => (await open(companyId: companyId, userId: userId, businessDate: businessDate)).query('products', where: 'deleted_at IS NULL', orderBy: 'name ASC');

  Future<int> saveLocalSale({required int companyId, required int userId, required DateTime businessDate, required String uuidLocal, required List<Map<String, dynamic>> items, required List<Map<String, dynamic>> payments, required double total, String status = 'paid', int? serverId, String? folio, Map<String, dynamic>? extra}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    return db.transaction((txn) async {
      final existing = await txn.query('sales', where: 'uuid_local = ?', whereArgs: [uuidLocal], limit: 1);
      if (existing.isNotEmpty) return _toInt(existing.first['id']);
      final now = DateTime.now().toIso8601String();
      final saleId = await txn.insert('sales', {
        'uuid_local': uuidLocal, 'server_id': serverId, 'folio': folio,
        'business_date': dateKey(businessDate), 'total': total, 'status': status,
        'sync_status': serverId == null ? 'pending' : 'synced',
        'server_synced_at': serverId == null ? null : now,
        'created_at': now, 'updated_at': now,
      });
      for (final item in items) {
        await txn.insert('sale_items', {
          'sale_id': saleId, 'product_id': _toInt(item['product_id']),
          'name': item['name']?.toString(), 'quantity': _toDouble(item['quantity']),
          'unit_price': _toDouble(item['unit_price'] ?? item['precio']),
          'total': _toDouble(item['total']), 'descuento': _toDouble(item['descuento']),
        });
      }
      for (final payment in payments) {
        await txn.insert('sale_payments', {
          'sale_id': saleId, 'method': payment['method'] ?? payment['forma_pago'],
          'amount': _toDouble(payment['amount'] ?? payment['monto']),
          'referencia': payment['referencia'],
        });
      }
      if (serverId == null) {
        final payload = <String, dynamic>{
          'uuid_local': uuidLocal,
          'business_date': dateKey(businessDate),
          'total': total,
          'productos': items,
          'pagos': payments,
          ...?extra,
        };
        await txn.insert('sync_outbox', {
          'uuid_local': uuidLocal, 'entity_type': 'venta',
          'payload': jsonEncode(payload), 'status': 'queued',
          'attempts': 0, 'created_at': now, 'updated_at': now,
        });
      }
      return saleId;
    });
  }

  Future<List<Map<String, dynamic>>> getTodaySales({required int companyId, required int userId, required DateTime businessDate}) async => (await open(companyId: companyId, userId: userId, businessDate: businessDate)).query('sales', where: 'business_date = ?', whereArgs: [dateKey(businessDate)], orderBy: 'created_at DESC');

  Future<List<Map<String, dynamic>>> getPendingOutbox({required int companyId, required int userId, required DateTime businessDate, int? limit}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final now = DateTime.now().toIso8601String();
    return db.query('sync_outbox', where: "status IN ('queued','failed') AND (next_retry_at IS NULL OR next_retry_at <= ?)", whereArgs: [now], orderBy: 'created_at ASC', limit: limit);
  }

  Future<Map<String, dynamic>?> getSaleByUuid({required int companyId, required int userId, required DateTime businessDate, required String uuidLocal}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final r = await db.query('sales', where: 'uuid_local = ?', whereArgs: [uuidLocal], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> getPendingSales({required int companyId, required int userId, required DateTime businessDate}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    return db.query('sales', where: "sync_status IN ('pending','failed')", orderBy: 'created_at ASC');
  }

  Future<List<Map<String, dynamic>>> getSaleItems(Database db, int saleId) => db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
  Future<List<Map<String, dynamic>>> getSalePayments(Database db, int saleId) => db.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId]);

  Future<void> markOutboxSynced({required int companyId, required int userId, required DateTime businessDate, required String uuidLocal, Map<String, dynamic>? serverResponse}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final data = serverResponse?['data'] is Map ? Map<String, dynamic>.from(serverResponse!['data']) : (serverResponse ?? const {});
    final serverId = _nullableInt(data['server_id'] ?? data['venta_id'] ?? data['id']);
    final folio = data['folio']?.toString();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update('sync_outbox', {'status': 'synced', 'error_message': null, 'next_retry_at': null, 'updated_at': now}, where: 'uuid_local = ?', whereArgs: [uuidLocal]);
      await txn.update('sales', {'sync_status': 'synced', 'server_id': serverId, 'folio': folio, 'server_synced_at': now, 'error_message': null, 'next_retry_at': null, 'updated_at': now}, where: 'uuid_local = ?', whereArgs: [uuidLocal]);
    });
  }

  Future<void> markOutboxFailed({required int companyId, required int userId, required DateTime businessDate, required String uuidLocal, required String error, required int attempts}) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final retry = DateTime.now().add(Duration(minutes: (attempts.clamp(1, 30)) * 2));
    await db.transaction((txn) async {
      await txn.update('sync_outbox', {'status': 'failed', 'attempts': attempts, 'error_message': error, 'next_retry_at': retry.toIso8601String(), 'updated_at': DateTime.now().toIso8601String()}, where: 'uuid_local = ?', whereArgs: [uuidLocal]);
      await txn.update('sales', {'sync_status': 'failed', 'sync_attempts': attempts, 'error_message': error, 'next_retry_at': retry.toIso8601String(), 'updated_at': DateTime.now().toIso8601String()}, where: 'uuid_local = ?', whereArgs: [uuidLocal]);
    });
  }

  Future<void> markSaleSynced({required int companyId, required int userId, required DateTime businessDate, required String uuidLocal, Map<String, dynamic>? serverResponse}) => markOutboxSynced(companyId: companyId, userId: userId, businessDate: businessDate, uuidLocal: uuidLocal, serverResponse: serverResponse);

  Future<void> close({required int companyId, required int userId, required DateTime businessDate}) async {
    final key = _key(companyId, userId, businessDate);
    final db = _cache.remove(key);
    if (db != null && db.isOpen) await db.close();
  }

  Future<bool> isOpen({required int companyId, required int userId, required DateTime businessDate}) async => _cache[_key(companyId, userId, businessDate)]?.isOpen ?? false;

  Future<String> databasePath({required int companyId, required int userId, required DateTime businessDate}) async {
    final root = await getApplicationDocumentsDirectory();
    return '${root.path}/app-data/companies/$companyId/users/$userId/pos_day_${dateKey(businessDate)}.sqlite';
  }

  Future<void> deleteDatabaseFile({required int companyId, required int userId, required DateTime businessDate}) async {
    await close(companyId: companyId, userId: userId, businessDate: businessDate);
    final file = File(await databasePath(companyId: companyId, userId: userId, businessDate: businessDate));
    if (await file.exists()) await file.delete();
  }

  int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  int? _nullableInt(dynamic v) { final n = _toInt(v); return n > 0 ? n : null; }
  double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;
}

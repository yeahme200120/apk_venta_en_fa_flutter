import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class PosDatabaseService {
  static final PosDatabaseService _instance = PosDatabaseService._internal();

  factory PosDatabaseService() => _instance;

  PosDatabaseService._internal();

  final Map<String, Database> _cache = {};

  Future<Database> open({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final key = '$companyId:$userId:${businessDate.toIso8601String().substring(0, 10)}';
    if (_cache.containsKey(key)) return _cache[key]!;

    final dir = await getApplicationDocumentsDirectory();
    final companyDir = Directory('${dir.path}/app-data/companies/$companyId/users/$userId');
    await companyDir.create(recursive: true);

    final fileName = 'pos_day_${businessDate.toIso8601String().substring(0, 10)}.sqlite';
    final path = '${companyDir.path}/$fileName';

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            code TEXT,
            name TEXT,
            price REAL,
            stock REAL,
            version INTEGER DEFAULT 0,
            deleted_at TEXT,
            synced_at TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid_local TEXT UNIQUE,
            server_id INTEGER,
            folio TEXT,
            business_date TEXT,
            total REAL,
            sync_status TEXT DEFAULT 'draft',
            error_message TEXT,
            version INTEGER DEFAULT 0,
            created_at TEXT,
            updated_at TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER,
            product_id INTEGER,
            name TEXT,
            quantity REAL,
            unit_price REAL,
            total REAL
          )
        ''');

        await database.execute('''
          CREATE TABLE sale_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER,
            method TEXT,
            amount REAL
          )
        ''');

        await database.execute('''
          CREATE TABLE sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid_local TEXT UNIQUE,
            entity_type TEXT,
            payload TEXT,
            status TEXT DEFAULT 'queued',
            attempts INTEGER DEFAULT 0,
            error_message TEXT,
            next_retry_at TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE sync_inbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT,
            cursor TEXT,
            payload TEXT,
            processed_at TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE daily_metadata (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            company_id INTEGER,
            user_id INTEGER,
            business_date TEXT,
            last_sync_at TEXT,
            schema_version INTEGER DEFAULT 1,
            closed_at TEXT
          )
        ''');
      },
    );

    _cache[key] = db;
    return db;
  }

  Future<void> upsertProducts(Database db, List<Map<String, dynamic>> products) async {
    for (final product in products) {
      await db.insert(
        'products',
        {
          'id': int.tryParse('${product['id'] ?? product['product_id'] ?? 0}') ?? 0,
          'code': product['code'] ?? '',
          'name': product['name'] ?? '',
          'price': double.tryParse('${product['price'] ?? 0}') ?? 0.0,
          'stock': double.tryParse('${product['stock'] ?? 0}') ?? 0.0,
          'version': int.tryParse('${product['version'] ?? 0}') ?? 0,
          'deleted_at': product['deleted_at'],
          'synced_at': product['synced_at'] ?? DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getProducts({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    return db.query('products', orderBy: 'name ASC');
  }

  Future<int> saveLocalSale({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required String uuidLocal,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required double total,
    required String status,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final now = DateTime.now().toIso8601String();

    final saleId = await db.insert('sales', {
      'uuid_local': uuidLocal,
      'business_date': businessDate.toIso8601String().substring(0, 10),
      'total': total,
      'sync_status': status,
      'created_at': now,
      'updated_at': now,
    });

    for (final item in items) {
      await db.insert('sale_items', {
        'sale_id': saleId,
        'product_id': item['product_id'],
        'name': item['name'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
        'total': item['total'],
      });
    }

    for (final payment in payments) {
      await db.insert('sale_payments', {
        'sale_id': saleId,
        'method': payment['method'],
        'amount': payment['amount'],
      });
    }

    await db.insert(
      'sync_outbox',
      {
        'uuid_local': uuidLocal,
        'entity_type': 'sale',
        'payload': jsonEncode({
          'uuid_local': uuidLocal,
          'items': items,
          'payments': payments,
          'total': total,
          'status': status,
          'business_date': businessDate.toIso8601String().substring(0, 10),
        }),
        'status': 'queued',
        'attempts': 0,
        'next_retry_at': now,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return saleId;
  }

  Future<List<Map<String, dynamic>>> getTodaySales({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    return db.query('sales', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox({
    required int companyId,
    required int userId,
    required DateTime businessDate,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    return db.query(
      'sync_outbox',
      where: 'status IN (?, ?)',
      whereArgs: ['queued', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markOutboxSynced({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required String uuidLocal,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    await db.update(
      'sync_outbox',
      {
        'status': 'synced',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid_local = ?',
      whereArgs: [uuidLocal],
    );

    await db.update(
      'sales',
      {
        'sync_status': 'synced',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid_local = ?',
      whereArgs: [uuidLocal],
    );
  }

  Future<void> markOutboxFailed({
    required int companyId,
    required int userId,
    required DateTime businessDate,
    required String uuidLocal,
    required String error,
    required int attempts,
  }) async {
    final db = await open(companyId: companyId, userId: userId, businessDate: businessDate);
    final nextRetryAt = DateTime.now().add(Duration(minutes: attempts >= 1 ? (2 * attempts) : 1));

    await db.update(
      'sync_outbox',
      {
        'status': 'failed',
        'attempts': attempts,
        'error_message': error,
        'next_retry_at': nextRetryAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid_local = ?',
      whereArgs: [uuidLocal],
    );
  }
}

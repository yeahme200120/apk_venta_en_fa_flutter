import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static final LocalDb _instance = LocalDb._internal();

  factory LocalDb() => _instance;

  LocalDb._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final directory = await getApplicationDocumentsDirectory();
    final dbPath = '${directory.path}/pos_local.db';

    _database = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return _database!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sales ADD COLUMN sync_status TEXT DEFAULT "pending"');
      await db.execute('ALTER TABLE sales ADD COLUMN payment_method TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN cash_received REAL DEFAULT 0');
      await db.execute('ALTER TABLE sales ADD COLUMN change_due REAL DEFAULT 0');
      await db.execute('ALTER TABLE sales ADD COLUMN paid_at TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        name TEXT,
        price REAL,
        stock REAL,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_local TEXT,
        total REAL,
        status TEXT DEFAULT 'pending',
        sync_status TEXT DEFAULT 'pending',
        payment_method TEXT,
        cash_received REAL DEFAULT 0,
        change_due REAL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        paid_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        product_id INTEGER,
        name TEXT,
        quantity REAL,
        unit_price REAL,
        total REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        method TEXT,
        amount REAL
      )
    ''');

    await db.execute('''
      INSERT INTO products (code, name, price, stock, is_active) VALUES
        ('001', 'Café espresso', 25.0, 100, 1),
        ('002', 'Cookies', 18.5, 70, 1),
        ('003', 'Refresco 600ml', 32.0, 80, 1),
        ('004', 'Sandwich', 45.0, 60, 1);
    ''');
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return db.query('products', where: 'is_active = 1', orderBy: 'name ASC');
  }

  Future<int> createProduct({required String code, required String name, required double price, double stock = 0}) async {
    final db = await database;
    return db.insert('products', {'code': code, 'name': name, 'price': price, 'stock': stock, 'is_active': 1});
  }

  Future<int> updateProduct({required int id, required String code, required String name, required double price, required double stock}) async {
    final db = await database;
    return db.update(
      'products',
      {'code': code, 'name': name, 'price': price, 'stock': stock},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> cancelSale(int saleId) async {
    final db = await database;
    return db.transaction((txn) async {
      final sales = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (sales.isEmpty || sales.first['status'] == 'cancelled') return false;
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      for (final item in items) {
        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [item['quantity'], item['product_id']],
        );
      }
      await txn.update(
        'sales',
        {'status': 'cancelled', 'sync_status': 'pending', 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      return true;
    });
  }

  Future<int> saveSale({
    required String uuid,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required double total,
    required String status,
    String syncStatus = 'pending',
    String? paymentMethod,
    double cashReceived = 0,
    double changeDue = 0,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final saleId = await db.insert('sales', {
      'uuid_local': uuid,
      'total': total,
      'status': status,
      'sync_status': syncStatus,
      'payment_method': paymentMethod,
      'cash_received': cashReceived,
      'change_due': changeDue,
      'created_at': now,
      'updated_at': now,
      'paid_at': status == 'paid' ? now : null,
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
      await db.rawUpdate(
        'UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?',
        [item['quantity'], item['product_id'], item['quantity']],
      );
    }

    for (final payment in payments) {
      await db.insert('sale_payments', {
        'sale_id': saleId,
        'method': payment['method'],
        'amount': payment['amount'],
      });
    }

    return saleId;
  }

  Future<List<Map<String, dynamic>>> getTodaySales() async {
    final db = await database;
    return db.query(
      'sales',
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSales() async {
    final db = await database;
    return db.query(
      'sales',
      where: 'status IN (?, ?) OR sync_status IN (?, ?)',
      whereArgs: ['pending', 'paid', 'pending', 'failed'],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getSaleById(int saleId) async {
    final db = await database;
    final sales = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (sales.isEmpty) return null;
    return sales.first;
  }

  Future<List<Map<String, dynamic>>> getSaleItemsBySaleId(int saleId) async {
    final db = await database;
    return db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
  }

  Future<List<Map<String, dynamic>>> getSalePaymentsBySaleId(int saleId) async {
    final db = await database;
    return db.query(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
  }

  Future<void> updateSaleStatus(int saleId, String status, {String syncStatus = 'pending'}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sales',
      {
        'status': status,
        'sync_status': syncStatus,
        'updated_at': now,
        'paid_at': status == 'paid' ? (now) : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  Future<void> markSaleAsPaid(
    int saleId, {
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sales',
      {
        'status': 'paid',
        'sync_status': 'pending',
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_due': changeDue,
        'paid_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  Future<void> markSaleAsSynced(int saleId) async {
    final db = await database;
    await db.update(
      'sales',
      {
        'status': 'synced',
        'sync_status': 'synced',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  Future<void> clearDb() async {
    final db = await database;
    await db.delete('sale_items');
    await db.delete('sale_payments');
    await db.delete('sales');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}

import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static final LocalDb _instance = LocalDb._internal();

  factory LocalDb() => _instance;

  LocalDb._internal();

  static Database? _database;

  /// Incrementar siempre que se modifique la estructura SQLite.
  static const int _databaseVersion = 6;

  // ============================================================
  // DATABASE
  // ============================================================

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final directory = await getApplicationDocumentsDirectory();

    final dbPath = '${directory.path}/pos_local.db';

    _database = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return _database!;
  }

  // ============================================================
  // CREATE DATABASE
  // ============================================================

  Future<void> _onCreate(
    Database db,
    int version,
  ) async {
    await _createCompanyTable(db);
    await _createProductsTable(db);
    await _createSalesTables(db);
    await _createCatalogTables(db);
  }

  // ============================================================
  // COMPANY
  // ============================================================

  Future<void> _createCompanyTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS company (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        logo TEXT,
        logo_url TEXT,
        colores_json TEXT,
        configuracion_json TEXT,
        direccion TEXT,
        telefono TEXT,
        email_contacto TEXT,
        rfc TEXT,
        razon_social TEXT,
        leyenda_ticket TEXT,
        whatsapp_numero TEXT,
        activo INTEGER DEFAULT 1,
        updated_at TEXT
      )
    ''');
  }

  // ============================================================
  // PRODUCTS
  // ============================================================

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY,
        code TEXT,
        name TEXT,
        price REAL DEFAULT 0,
        stock REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_name
      ON products(name)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_code
      ON products(code)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_active
      ON products(is_active)
    ''');
  }

  // ============================================================
  // SALES
  // ============================================================

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_local TEXT,
        total REAL DEFAULT 0,
        status TEXT DEFAULT 'pending',
        sync_status TEXT DEFAULT 'pending',
        payment_method TEXT,
        cash_received REAL DEFAULT 0,
        change_due REAL DEFAULT 0,
        mesa_id INTEGER,
        mesa_nombre TEXT,
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
        quantity REAL DEFAULT 0,
        unit_price REAL DEFAULT 0,
        total REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        method TEXT,
        amount REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_status
      ON sales(status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_sync_status
      ON sales(sync_status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_created_at
      ON sales(created_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id
      ON sale_items(sale_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_payments_sale_id
      ON sale_payments(sale_id)
    ''');
  }

  // ============================================================
  // CATALOG TABLES
  // ============================================================

  Future<void> _createCatalogTables(Database db) async {
    // CLIENTES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients (
        id INTEGER PRIMARY KEY,
        name TEXT,
        email TEXT,
        phone TEXT,
        rfc TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // IMPUESTOS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS taxes (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        rate REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // FORMAS DE PAGO
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_methods (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // UNIDADES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS units (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // CATEGORIAS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // PROMOCIONES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS promotions (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // CUPONES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS coupons (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    // CONTROL DE SINCRONIZACION
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_sync (
        catalog TEXT PRIMARY KEY,
        version TEXT,
        synced_at TEXT
      )
    ''');
  }

  // ============================================================
  // UPGRADE
  // ============================================================

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // ==========================================================
    // VERSION 2
    // ==========================================================

    if (oldVersion < 2) {
      await _addColumnIfNotExists(
        db,
        'sales',
        'sync_status',
        "TEXT DEFAULT 'pending'",
      );

      await _addColumnIfNotExists(
        db,
        'sales',
        'payment_method',
        'TEXT',
      );

      await _addColumnIfNotExists(
        db,
        'sales',
        'cash_received',
        'REAL DEFAULT 0',
      );

      await _addColumnIfNotExists(
        db,
        'sales',
        'change_due',
        'REAL DEFAULT 0',
      );

      await _addColumnIfNotExists(
        db,
        'sales',
        'paid_at',
        'TEXT',
      );
    }

    // ==========================================================
    // VERSION 3
    // ==========================================================

    if (oldVersion < 3) {
      await _addColumnIfNotExists(
        db,
        'sales',
        'mesa_id',
        'INTEGER',
      );

      await _addColumnIfNotExists(
        db,
        'sales',
        'mesa_nombre',
        'TEXT',
      );
    }

    // ==========================================================
    // VERSION 4
    // ==========================================================

    if (oldVersion < 4) {
      await _createCatalogTables(db);
    }

    // ==========================================================
    // VERSION 5
    // ==========================================================

    if (oldVersion < 5) {
      await _addColumnIfNotExists(
        db,
        'products',
        'data_json',
        'TEXT',
      );

      await _addColumnIfNotExists(
        db,
        'products',
        'updated_at',
        'TEXT',
      );
    }

    // ==========================================================
    // VERSION 6
    // EMPRESA
    // ==========================================================

    if (oldVersion < 6) {
      await _createCompanyTable(db);
    }
  }

  // ============================================================
  // ADD COLUMN
  // ============================================================

  Future<void> _addColumnIfNotExists(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info($table)',
    );

    final exists = columns.any(
      (columnInfo) =>
          columnInfo['name']?.toString() == column,
    );

    if (!exists) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  // ============================================================
  // CONVERSION HELPERS
  // ============================================================

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  String? _stringValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString();
      }
    }

    return null;
  }

  int _activeValue(
    Map<String, dynamic> data,
  ) {
    final value =
        data['is_active'] ??
        data['activo'] ??
        data['active'] ??
        1;

    if (value is bool) {
      return value ? 1 : 0;
    }

    if (value is num) {
      return value == 0 ? 0 : 1;
    }

    final text =
        value.toString().trim().toLowerCase();

    if (text == 'false' ||
        text == '0' ||
        text == 'no' ||
        text == 'inactive' ||
        text == 'inactivo') {
      return 0;
    }

    return 1;
  }

  List<Map<String, dynamic>> _asList(
    dynamic value,
  ) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) =>
              Map<String, dynamic>.from(item),
        )
        .toList();
  }

  // ============================================================
  // COMPANY
  // ============================================================

  Future<void> upsertCompany(
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    Map<String, dynamic>? colores;

    final rawColores = data['colores'];

    if (rawColores is Map) {
      colores =
          Map<String, dynamic>.from(rawColores);
    } else if (rawColores is String) {
      try {
        final decoded = jsonDecode(rawColores);

        if (decoded is Map) {
          colores =
              Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    Map<String, dynamic>? configuracion;

    final rawConfiguracion =
        data['configuracion'];

    if (rawConfiguracion is Map) {
      configuracion =
          Map<String, dynamic>.from(
        rawConfiguracion,
      );
    } else if (rawConfiguracion is String) {
      try {
        final decoded =
            jsonDecode(rawConfiguracion);

        if (decoded is Map) {
          configuracion =
              Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    await db.insert(
      'company',
      {
        'id': id,
        'nombre': data['nombre']?.toString(),
        'logo': data['logo']?.toString(),
        'logo_url': data['logo_url']?.toString(),
        'colores_json':
            colores == null ? null : jsonEncode(colores),
        'configuracion_json':
            configuracion == null
                ? null
                : jsonEncode(configuracion),
        'direccion':
            data['direccion']?.toString(),
        'telefono':
            data['telefono']?.toString(),
        'email_contacto':
            data['email_contacto']?.toString(),
        'rfc': data['rfc']?.toString(),
        'razon_social':
            data['razon_social']?.toString(),
        'leyenda_ticket':
            data['leyenda_ticket']?.toString(),
        'whatsapp_numero':
            data['whatsapp_numero']?.toString(),
        'activo': _activeValue(data),
        'updated_at':
            _stringValue(
              data,
              ['updated_at', 'updatedAt'],
            ) ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCompany() async {
    final db = await database;

    final result = await db.query(
      'company',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    final row =
        Map<String, dynamic>.from(result.first);

    if (row['colores_json'] != null) {
      try {
        row['colores'] =
            jsonDecode(
              row['colores_json'].toString(),
            );
      } catch (_) {
        row['colores'] = {};
      }
    } else {
      row['colores'] = {};
    }

    if (row['configuracion_json'] != null) {
      try {
        row['configuracion'] =
            jsonDecode(
              row['configuracion_json'].toString(),
            );
      } catch (_) {
        row['configuracion'] = {};
      }
    } else {
      row['configuracion'] = {};
    }

    return row;
  }

  // ============================================================
  // PRODUCTS
  // ============================================================

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;

    return db.query(
      'products',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await database;

    return db.query(
      'products',
      orderBy: 'name ASC',
    );
  }

  Future<Map<String, dynamic>?> getProductById(
    int id,
  ) async {
    final db = await database;

    final result = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return result.isEmpty
        ? null
        : result.first;
  }

  Future<int> createProduct({
    int? id,
    required String code,
    required String name,
    required double price,
    double stock = 0,
    bool isActive = true,
    Map<String, dynamic>? data,
    String? updatedAt,
  }) async {
    final db = await database;

    return db.insert(
      'products',
      {
        if (id != null) 'id': id,
        'code': code,
        'name': name,
        'price': price,
        'stock': stock,
        'is_active': isActive ? 1 : 0,
        'data_json':
            data == null ? null : jsonEncode(data),
        'updated_at':
            updatedAt ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<int> updateProduct({
    required int id,
    required String code,
    required String name,
    required double price,
    required double stock,
    bool isActive = true,
    Map<String, dynamic>? data,
    String? updatedAt,
  }) async {
    final db = await database;

    final values = <String, dynamic>{
      'code': code,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': isActive ? 1 : 0,
      'updated_at':
          updatedAt ??
          DateTime.now().toIso8601String(),
    };

    if (data != null) {
      values['data_json'] =
          jsonEncode(data);
    }

    return db.update(
      'products',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;

    return db.update(
      'products',
      {
        'is_active': 0,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // CLIENTS
  // ============================================================

  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;

    return db.query(
      'clients',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllClients() async {
    final db = await database;

    return db.query(
      'clients',
      orderBy: 'name ASC',
    );
  }

  Future<Map<String, dynamic>?> getClientById(
    int id,
  ) async {
    final db = await database;

    final result = await db.query(
      'clients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return result.isEmpty
        ? null
        : result.first;
  }

  Future<void> upsertClient(
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    await _upsertClientWithExecutor(
      db,
      data,
    );
  }

  // ============================================================
  // GENERIC CATALOG
  // ============================================================

  Future<void> _upsertCatalogItem({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    final db = await database;

    await _upsertCatalogWithExecutor(
      db,
      table: table,
      data: data,
      includeRate: table == 'taxes',
    );
  }

  Future<void> _upsertClientWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    await executor.insert(
      'clients',
      {
        'id': id,
        'name': _stringValue(
          data,
          ['name', 'nombre'],
        ),
        'email': _stringValue(
          data,
          ['email', 'correo'],
        ),
        'phone': _stringValue(
          data,
          ['phone', 'telefono', 'teléfono'],
        ),
        'rfc': _stringValue(
          data,
          ['rfc'],
        ),
        'is_active': _activeValue(data),
        'data_json': jsonEncode(data),
        'updated_at':
            _stringValue(
              data,
              ['updated_at', 'updatedAt'],
            ) ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertCatalogWithExecutor(
    dynamic executor, {
    required String table,
    required Map<String, dynamic> data,
    bool includeRate = false,
  }) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    final values = <String, dynamic>{
      'id': id,
      'name': _stringValue(
        data,
        [
          'name',
          'nombre',
          'descripcion',
          'description',
        ],
      ),
      'code': _stringValue(
        data,
        [
          'code',
          'codigo',
          'clave',
          'clave_sat',
          'abreviatura',
        ],
      ),
      'is_active': _activeValue(data),
      'data_json': jsonEncode(data),
      'updated_at':
          _stringValue(
            data,
            ['updated_at', 'updatedAt'],
          ) ??
          DateTime.now().toIso8601String(),
    };

    if (includeRate) {
      values['rate'] = _toDouble(
        data['rate'] ??
            data['tasa'] ??
            data['porcentaje'] ??
            data['valor'],
      );
    }

    await executor.insert(
      table,
      values,
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // TAXES
  // ============================================================

  Future<List<Map<String, dynamic>>> getTaxes() async {
    final db = await database;

    return db.query(
      'taxes',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllTaxes() async {
    final db = await database;

    return db.query(
      'taxes',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertTax(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'taxes',
      data: data,
    );
  }

  // ============================================================
  // PAYMENT METHODS
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getPaymentMethods() async {
    final db = await database;

    return db.query(
      'payment_methods',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>>
      getAllPaymentMethods() async {
    final db = await database;

    return db.query(
      'payment_methods',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertPaymentMethod(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'payment_methods',
      data: data,
    );
  }

  // ============================================================
  // UNITS
  // ============================================================

  Future<List<Map<String, dynamic>>> getUnits() async {
    final db = await database;

    return db.query(
      'units',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllUnits() async {
    final db = await database;

    return db.query(
      'units',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertUnit(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'units',
      data: data,
    );
  }

  // ============================================================
  // CATEGORIES
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getCategories() async {
    final db = await database;

    return db.query(
      'categories',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>>
      getAllCategories() async {
    final db = await database;

    return db.query(
      'categories',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertCategory(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'categories',
      data: data,
    );
  }

  // ============================================================
  // PROMOTIONS
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getPromotions() async {
    final db = await database;

    return db.query(
      'promotions',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>>
      getAllPromotions() async {
    final db = await database;

    return db.query(
      'promotions',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertPromotion(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'promotions',
      data: data,
    );
  }

  // ============================================================
  // COUPONS
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getCoupons() async {
    final db = await database;

    return db.query(
      'coupons',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, dynamic>>>
      getAllCoupons() async {
    final db = await database;

    return db.query(
      'coupons',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertCoupon(
    Map<String, dynamic> data,
  ) async {
    await _upsertCatalogItem(
      table: 'coupons',
      data: data,
    );
  }

  // ============================================================
  // PRODUCT API
  // ============================================================

  Future<void> upsertProductFromApi(
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    await _upsertProductWithExecutor(
      db,
      data,
    );
  }

  Future<void> _upsertProductWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    final name =
        _stringValue(
          data,
          ['name', 'nombre'],
        ) ??
        '';

    final code =
        _stringValue(
          data,
          ['code', 'codigo', 'sku'],
        ) ??
        '';

    final price = _toDouble(
      data['price'] ??
          data['precio'] ??
          data['precio_venta'],
    );

    final stock = _toDouble(
      data['stock'] ??
          data['existencia'] ??
          data['cantidad'],
    );

    await executor.insert(
      'products',
      {
        'id': id,
        'code': code,
        'name': name,
        'price': price,
        'stock': stock,
        'is_active': _activeValue(data),
        'data_json': jsonEncode(data),
        'updated_at':
            _stringValue(
              data,
              ['updated_at', 'updatedAt'],
            ) ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // COMPLETE CATALOG SYNC
  // ============================================================

  Future<void> syncCatalogs(
    Map<String, dynamic> response,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      // --------------------------------------------------------
      // EMPRESA
      // --------------------------------------------------------

      final empresa = response['empresa'];

      if (empresa is Map) {
        await _upsertCompanyWithTransaction(
          txn,
          Map<String, dynamic>.from(empresa),
        );
      }

      // --------------------------------------------------------
      // PRODUCTOS
      // --------------------------------------------------------

      for (final item
          in _asList(response['productos'])) {
        await _upsertProductWithExecutor(
          txn,
          item,
        );
      }

      // --------------------------------------------------------
      // CLIENTES
      // --------------------------------------------------------

      for (final item
          in _asList(response['clientes'])) {
        await _upsertClientWithExecutor(
          txn,
          item,
        );
      }

      // --------------------------------------------------------
      // IMPUESTOS
      // --------------------------------------------------------

      for (final item
          in _asList(response['impuestos'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'taxes',
          data: item,
          includeRate: true,
        );
      }

      // --------------------------------------------------------
      // FORMAS DE PAGO
      // --------------------------------------------------------

      for (final item
          in _asList(response['formas_pago'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'payment_methods',
          data: item,
        );
      }

      // --------------------------------------------------------
      // UNIDADES
      // --------------------------------------------------------

      for (final item
          in _asList(response['unidades_medida'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'units',
          data: item,
        );
      }

      // --------------------------------------------------------
      // CATEGORIAS
      // --------------------------------------------------------

      for (final item
          in _asList(response['categorias'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'categories',
          data: item,
        );
      }

      // --------------------------------------------------------
      // PROMOCIONES
      // --------------------------------------------------------

      for (final item
          in _asList(response['promociones'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'promotions',
          data: item,
        );
      }

      // --------------------------------------------------------
      // CUPONES
      // --------------------------------------------------------

      for (final item
          in _asList(response['cupones'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'coupons',
          data: item,
        );
      }

      // --------------------------------------------------------
      // VERSIONES
      // --------------------------------------------------------

      final versiones = response['versiones'];

      if (versiones is Map) {
        for (final entry in versiones.entries) {
          await txn.insert(
            'catalog_sync',
            {
              'catalog':
                  entry.key.toString(),
              'version':
                  entry.value?.toString(),
              'synced_at':
                  DateTime.now().toIso8601String(),
            },
            conflictAlgorithm:
                ConflictAlgorithm.replace,
          );
        }
      }
    });

    // ----------------------------------------------------------
    // TOMBSTONES
    // ----------------------------------------------------------

    await _processTombstones(
      response['tombstones'],
    );

    // Compatibilidad con backend anterior.
    await _processTombstones({
      'productos':
          response['productos_eliminados'],
      'clientes':
          response['clientes_eliminados'],
      'impuestos':
          response['impuestos_eliminados'],
      'formas_pago':
          response['formas_pago_eliminadas'],
      'unidades_medida':
          response['unidades_medida_eliminadas'],
      'categorias':
          response['categorias_eliminadas'],
      'promociones':
          response['promociones_eliminadas'],
      'cupones':
          response['cupones_eliminados'],
    });
  }

  Future<void> _upsertCompanyWithTransaction(
    Transaction txn,
    Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    String? coloresJson;
    String? configuracionJson;

    final colores = data['colores'];

    if (colores is Map ||
        colores is List) {
      coloresJson = jsonEncode(colores);
    } else if (colores is String) {
      coloresJson = colores;
    }

    final configuracion =
        data['configuracion'];

    if (configuracion is Map ||
        configuracion is List) {
      configuracionJson =
          jsonEncode(configuracion);
    } else if (configuracion is String) {
      configuracionJson =
          configuracion;
    }

    await txn.insert(
      'company',
      {
        'id': id,
        'nombre': data['nombre']?.toString(),
        'logo': data['logo']?.toString(),
        'logo_url': data['logo_url']?.toString(),
        'colores_json': coloresJson,
        'configuracion_json':
            configuracionJson,
        'direccion':
            data['direccion']?.toString(),
        'telefono':
            data['telefono']?.toString(),
        'email_contacto':
            data['email_contacto']?.toString(),
        'rfc': data['rfc']?.toString(),
        'razon_social':
            data['razon_social']?.toString(),
        'leyenda_ticket':
            data['leyenda_ticket']?.toString(),
        'whatsapp_numero':
            data['whatsapp_numero']?.toString(),
        'activo': _activeValue(data),
        'updated_at':
            _stringValue(
              data,
              ['updated_at', 'updatedAt'],
            ) ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // TOMBSTONES
  // ============================================================

  Future<void> _processTombstones(
    dynamic tombstonesData,
  ) async {
    if (tombstonesData is! Map) {
      return;
    }

    final db = await database;

    await db.transaction((txn) async {
      await _deleteTombstoneList(
        txn,
        table: 'products',
        values: tombstonesData['productos'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'clients',
        values: tombstonesData['clientes'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'taxes',
        values: tombstonesData['impuestos'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'payment_methods',
        values:
            tombstonesData['formas_pago'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'units',
        values:
            tombstonesData['unidades_medida'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'categories',
        values:
            tombstonesData['categorias'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'promotions',
        values:
            tombstonesData['promociones'],
      );

      await _deleteTombstoneList(
        txn,
        table: 'coupons',
        values:
            tombstonesData['cupones'],
      );
    });
  }

  Future<void> _deleteTombstoneList(
    Transaction txn, {
    required String table,
    dynamic values,
  }) async {
    if (values is! List) {
      return;
    }

    for (final item in values) {
      int id = 0;

      if (item is Map) {
        id = _toInt(item['id']);
      } else {
        id = _toInt(item);
      }

      if (id <= 0) {
        continue;
      }

      await txn.delete(
        table,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ============================================================
  // CATALOG VERSIONS
  // ============================================================

  Future<String?> getCatalogVersion(
    String catalog,
  ) async {
    final db = await database;

    final result = await db.query(
      'catalog_sync',
      where: 'catalog = ?',
      whereArgs: [catalog],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first['version']
        ?.toString();
  }

  Future<void> setCatalogVersion(
    String catalog,
    String? version,
  ) async {
    final db = await database;

    await db.insert(
      'catalog_sync',
      {
        'catalog': catalog,
        'version': version,
        'synced_at':
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String?>>
      getCatalogVersions() async {
    final db = await database;

    final rows =
        await db.query('catalog_sync');

    return {
      for (final row in rows)
        row['catalog'].toString():
            row['version']?.toString(),
    };
  }

  // ============================================================
  // SALES
  // ============================================================

  Future<bool> cancelSale(
    int saleId,
  ) async {
    final db = await database;

    return db.transaction((txn) async {
      final sales = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );

      if (sales.isEmpty) {
        return false;
      }

      final sale = sales.first;

      final currentStatus =
          sale['status']?.toString();

      if (currentStatus == 'cancelled') {
        return false;
      }

      if (currentStatus == 'paid' ||
          currentStatus == 'synced') {
        final items = await txn.query(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );

        for (final item in items) {
          await txn.rawUpdate(
            '''
            UPDATE products
            SET stock = stock + ?
            WHERE id = ?
            ''',
            [
              _toDouble(item['quantity']),
              _toInt(item['product_id']),
            ],
          );
        }
      }

      await txn.update(
        'sales',
        {
          'status': 'cancelled',
          'sync_status': 'pending',
          'updated_at':
              DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      return true;
    });
  }

  // ============================================================
  // SAVE SALE
  // ============================================================

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
    int? tableId,
    String? tableName,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      final now =
          DateTime.now().toIso8601String();

      final saleId = await txn.insert(
        'sales',
        {
          'uuid_local': uuid,
          'total': total,
          'status': status,
          'sync_status': syncStatus,
          'payment_method': paymentMethod,
          'cash_received': cashReceived,
          'change_due': changeDue,
          'mesa_id': tableId,
          'mesa_nombre': tableName,
          'created_at': now,
          'updated_at': now,
          'paid_at':
              status == 'paid' ? now : null,
        },
      );

      for (final item in items) {
        final productId =
            _toInt(item['product_id']);

        final quantity =
            _toDouble(item['quantity']);

        await txn.insert(
          'sale_items',
          {
            'sale_id': saleId,
            'product_id': productId,
            'name': item['name'],
            'quantity': quantity,
            'unit_price':
                item['unit_price'],
            'total': item['total'],
          },
        );

        if (status == 'paid') {
          final updated =
              await txn.rawUpdate(
            '''
            UPDATE products
            SET stock = stock - ?
            WHERE id = ?
              AND stock >= ?
            ''',
            [
              quantity,
              productId,
              quantity,
            ],
          );

          if (updated != 1) {
            throw StateError(
              'Stock insuficiente para registrar la venta.',
            );
          }
        }
      }

      for (final payment in payments) {
        await txn.insert(
          'sale_payments',
          {
            'sale_id': saleId,
            'method': payment['method'],
            'amount': payment['amount'],
          },
        );
      }

      return saleId;
    });
  }

  // ============================================================
  // TODAY SALES
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getTodaySales() async {
    final db = await database;

    final now = DateTime.now();

    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final startOfTomorrow =
        startOfDay.add(
      const Duration(days: 1),
    );

    return db.query(
      'sales',
      where:
          'created_at >= ? AND created_at < ?',
      whereArgs: [
        startOfDay.toIso8601String(),
        startOfTomorrow.toIso8601String(),
      ],
      orderBy: 'created_at DESC',
    );
  }

  // ============================================================
  // PENDING / UNSYNCED SALES
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getPendingSales() async {
    final db = await database;

    return db.query(
      'sales',
      where:
          "sync_status IN (?, ?)",
      whereArgs: [
        'pending',
        'failed',
      ],
      orderBy: 'created_at ASC',
    );
  }

  // ============================================================
  // SALE DETAIL
  // ============================================================

  Future<Map<String, dynamic>?> getSaleById(
    int saleId,
  ) async {
    final db = await database;

    final sales = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    return sales.isEmpty
        ? null
        : sales.first;
  }

  Future<List<Map<String, dynamic>>>
      getSaleItemsBySaleId(
    int saleId,
  ) async {
    final db = await database;

    return db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
  }

  Future<List<Map<String, dynamic>>>
      getSalePaymentsBySaleId(
    int saleId,
  ) async {
    final db = await database;

    return db.query(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
  }

  // ============================================================
  // SALE STATUS
  // ============================================================

  Future<void> updateSaleStatus(
    int saleId,
    String status, {
    String syncStatus = 'pending',
  }) async {
    final db = await database;

    final now =
        DateTime.now().toIso8601String();

    await db.update(
      'sales',
      {
        'status': status,
        'sync_status': syncStatus,
        'updated_at': now,
        'paid_at':
            status == 'paid' ? now : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  // ============================================================
  // MARK PAID
  // ============================================================

  Future<void> markSaleAsPaid(
    int saleId, {
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final db = await database;

    final now =
        DateTime.now().toIso8601String();

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

  // ============================================================
  // PAY PENDING SALE
  // ============================================================

  Future<bool> payPendingSale(
    int saleId, {
    required List<Map<String, dynamic>> payments,
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      final sales = await txn.query(
        'sales',
        where:
            'id = ? AND status = ?',
        whereArgs: [
          saleId,
          'pending',
        ],
        limit: 1,
      );

      if (sales.isEmpty) {
        return false;
      }

      final items = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      for (final item in items) {
        final quantity =
            _toDouble(item['quantity']);

        final productId =
            _toInt(item['product_id']);

        final updated =
            await txn.rawUpdate(
          '''
          UPDATE products
          SET stock = stock - ?
          WHERE id = ?
            AND stock >= ?
          ''',
          [
            quantity,
            productId,
            quantity,
          ],
        );

        if (updated != 1) {
          throw StateError(
            'Stock insuficiente para cobrar la venta pendiente.',
          );
        }
      }

      await txn.delete(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      for (final payment in payments) {
        await txn.insert(
          'sale_payments',
          {
            'sale_id': saleId,
            'method': payment['method'],
            'amount': payment['amount'],
          },
        );
      }

      final now =
          DateTime.now().toIso8601String();

      await txn.update(
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

      return true;
    });
  }

  // ============================================================
  // DELETE PENDING SALE
  // ============================================================

  Future<bool> deletePendingSale(
    int saleId,
  ) async {
    final db = await database;

    return db.transaction((txn) async {
      final sale = await txn.query(
        'sales',
        where:
            'id = ? AND status = ?',
        whereArgs: [
          saleId,
          'pending',
        ],
        limit: 1,
      );

      if (sale.isEmpty) {
        return false;
      }

      await txn.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      await txn.delete(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      final deleted =
          await txn.delete(
        'sales',
        where:
            'id = ? AND status = ?',
        whereArgs: [
          saleId,
          'pending',
        ],
      );

      return deleted == 1;
    });
  }

  // ============================================================
  // UPDATE PENDING SALE
  // ============================================================

  Future<bool> updatePendingSale({
    required int saleId,
    required List<Map<String, dynamic>> items,
    required double total,
    int? tableId,
    String? tableName,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      final updated =
          await txn.update(
        'sales',
        {
          'total': total,
          'mesa_id': tableId,
          'mesa_nombre': tableName,
          'updated_at':
              DateTime.now().toIso8601String(),
        },
        where:
            'id = ? AND status = ?',
        whereArgs: [
          saleId,
          'pending',
        ],
      );

      if (updated != 1) {
        return false;
      }

      await txn.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      for (final item in items) {
        await txn.insert(
          'sale_items',
          {
            'sale_id': saleId,
            'product_id':
                item['product_id'],
            'name': item['name'],
            'quantity':
                item['quantity'],
            'unit_price':
                item['unit_price'],
            'total': item['total'],
          },
        );
      }

      return true;
    });
  }

  // ============================================================
  // MARK SALE AS SYNCED
  // ============================================================

  Future<void> markSaleAsSynced(
    int saleId,
  ) async {
    final db = await database;

    await db.update(
      'sales',
      {
        'sync_status': 'synced',
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  // ============================================================
  // CATALOG COUNTS
  // ============================================================

  Future<Map<String, int>>
      getCatalogCounts() async {
    final db = await database;

    Future<int> count(
      String table,
    ) async {
      final result =
          await db.rawQuery(
        'SELECT COUNT(*) AS total FROM $table',
      );

      return Sqflite.firstIntValue(
            result,
          ) ??
          0;
    }

    return {
      'productos':
          await count('products'),
      'clientes':
          await count('clients'),
      'impuestos':
          await count('taxes'),
      'formas_pago':
          await count('payment_methods'),
      'unidades_medida':
          await count('units'),
      'categorias':
          await count('categories'),
      'promociones':
          await count('promotions'),
      'cupones':
          await count('coupons'),
    };
  }

  Future<int> restoreCatalogItem({
    required String table,
    required int id,
  }) async {
    final db = await database;

    return db.update(
      table,
      {
        'is_active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  // ============================================================
  // CLEAR DATABASE
  // ============================================================

  Future<void> clearDb() async {
    final db = await database;

    await db.delete('sale_items');
    await db.delete('sale_payments');
    await db.delete('sales');

    await db.delete('products');
    await db.delete('clients');
    await db.delete('taxes');
    await db.delete('payment_methods');
    await db.delete('units');
    await db.delete('categories');
    await db.delete('promotions');
    await db.delete('coupons');
    await db.delete('catalog_sync');
    await db.delete('company');
  }

  // ============================================================
  // CLOSE
  // ============================================================

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ============================================================
  // GENERIC CATALOG CRUD
  // ============================================================

  static const Set<String> _catalogTables = {
    'taxes',
    'payment_methods',
    'units',
    'categories',
    'promotions',
    'coupons',
  };

  void _validateCatalogTable(String table) {
    if (!_catalogTables.contains(table)) {
      throw ArgumentError('Catálogo no permitido: $table');
    }
  }

  Future<List<Map<String, dynamic>>> getCatalogItems(
    String table, {
    bool activeOnly = true,
  }) async {
    _validateCatalogTable(table);

    final db = await database;

    return db.query(
      table,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
  }

  Future<int> createCatalogItem({
    required String table,
    required String name,
    String? code,
    double? rate,
    bool isActive = true,
    Map<String, dynamic>? data,
  }) async {
    _validateCatalogTable(table);

    final db = await database;

    return db.insert(
      table,
      {
        'name': name.trim(),
        'code': code?.trim(),
        if (table == 'taxes') 'rate': rate ?? 0,
        'is_active': isActive ? 1 : 0,
        'data_json':
            data == null ? null : jsonEncode(data),
        'updated_at':
            DateTime.now().toIso8601String(),
      },
    );
  }

  Future<int> updateCatalogItem({
    required String table,
    required int id,
    required String name,
    String? code,
    double? rate,
    bool isActive = true,
    Map<String, dynamic>? data,
  }) async {
    _validateCatalogTable(table);

    final db = await database;

    final values = <String, dynamic>{
      'name': name.trim(),
      'code': code?.trim(),
      'is_active': isActive ? 1 : 0,
      'updated_at':
          DateTime.now().toIso8601String(),
    };

    if (table == 'taxes') {
      values['rate'] = rate ?? 0;
    }

    if (data != null) {
      values['data_json'] = jsonEncode(data);
    }

    return db.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCatalogItem(
    String table,
    int id,
  ) async {
    _validateCatalogTable(table);

    final db = await database;

    return db.update(
      table,
      {
        'is_active': 0,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // CLIENT CRUD
  // ============================================================

  Future<int> createClient({
    required String name,
    String? email,
    String? phone,
    String? rfc,
    bool isActive = true,
  }) async {
    final db = await database;

    return db.insert(
      'clients',
      {
        'name': name.trim(),
        'email': email?.trim(),
        'phone': phone?.trim(),
        'rfc': rfc?.trim(),
        'is_active': isActive ? 1 : 0,
        'data_json': null,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
    );
  }

  Future<int> updateClient({
    required int id,
    required String name,
    String? email,
    String? phone,
    String? rfc,
    bool isActive = true,
  }) async {
    final db = await database;

    return db.update(
      'clients',
      {
        'name': name.trim(),
        'email': email?.trim(),
        'phone': phone?.trim(),
        'rfc': rfc?.trim(),
        'is_active': isActive ? 1 : 0,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteClient(int id) async {
    final db = await database;

    return db.update(
      'clients',
      {
        'is_active': 0,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

}
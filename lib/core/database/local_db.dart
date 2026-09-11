import 'dart:async';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base HISTÓRICA y de RESPALDO.
///
/// Esta base NO sustituye a PosDatabaseService.
/// Su responsabilidad es conservar operaciones de días anteriores,
/// especialmente ventas que todavía no llegaron al servidor.
class LocalDb {
  static final LocalDb _instance = LocalDb._internal();

  factory LocalDb() => _instance;

  LocalDb._internal();

  static Database? _database;

  /// 8 = print_ticket
  /// 9 = products.server_id
  /// 10 = local/server IDs for categories + local product category ID
  static const int _databaseVersion = 11;

  // Notificador global para que las pantallas puedan reaccionar
  // inmediatamente a cambios de ventas sin polling periódico.
  static final StreamController<void> _salesChanges =
      StreamController<void>.broadcast();

  static Stream<void> get salesChanges => _salesChanges.stream;

  static void notifySalesChanged() {
    if (!_salesChanges.isClosed) {
      _salesChanges.add(null);
    }
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/pos_local.db';

    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return _database!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createCompanyTable(db);
    await _createProductsTable(db);
    await _createSalesTables(db);
    await _createCatalogTables(db);
    await _createSyncQueueTable(db);
  }

  // ===========================================================================
  // COMPANY
  // ===========================================================================

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

  // ===========================================================================
  // PRODUCTS
  // ===========================================================================

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY,
        server_id INTEGER,
        category_id INTEGER,
        code TEXT,
        name TEXT,
        price REAL DEFAULT 0,
        stock REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        data_json TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_server_id '
      'ON products(server_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category_id '
      'ON products(category_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name '
      'ON products(name)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_code '
      'ON products(code)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_active '
      'ON products(is_active)',
    );
  }

  // ===========================================================================
  // SALES
  // ===========================================================================

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_local TEXT NOT NULL,
        server_id INTEGER,
        server_folio TEXT,
        business_date TEXT,
        total REAL DEFAULT 0,
        status TEXT DEFAULT 'pending',
        sync_status TEXT DEFAULT 'pending',
        payment_method TEXT,
        cash_received REAL DEFAULT 0,
        change_due REAL DEFAULT 0,
        mesa_id INTEGER,
        mesa_nombre TEXT,
        cliente_id INTEGER,
        descuento_global REAL DEFAULT 0,
        impuesto_global REAL DEFAULT 0,
        notas TEXT,
        sync_attempts INTEGER DEFAULT 0,
        next_retry_at TEXT,
        last_sync_error TEXT,
        server_synced_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        paid_at TEXT,
        print_ticket INTEGER NOT NULL DEFAULT 0,
        UNIQUE(uuid_local)
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
        total REAL DEFAULT 0,
        descuento REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        method TEXT,
        amount REAL DEFAULT 0,
        referencia TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_status '
      'ON sales(status)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_sync_status '
      'ON sales(sync_status)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_business_date '
      'ON sales(business_date)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_created_at '
      'ON sales(created_at)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id '
      'ON sale_items(sale_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale_id '
      'ON sale_payments(sale_id)',
    );
  }

  // ===========================================================================
  // CATALOG TABLES
  // ===========================================================================

  Future<void> _createCatalogTables(Database db) async {
    final definitions = <String, String>{
      'clients':
          'id INTEGER PRIMARY KEY, name TEXT, email TEXT, phone TEXT, '
          'rfc TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'taxes':
          'id INTEGER PRIMARY KEY, name TEXT, code TEXT, rate REAL DEFAULT 0, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'payment_methods':
          'id INTEGER PRIMARY KEY, name TEXT, code TEXT, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'units':
          'id INTEGER PRIMARY KEY, name TEXT, code TEXT, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'categories':
          'id INTEGER PRIMARY KEY, server_id INTEGER, name TEXT, code TEXT, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'promotions':
          'id INTEGER PRIMARY KEY, name TEXT, code TEXT, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',

      'coupons':
          'id INTEGER PRIMARY KEY, name TEXT, code TEXT, '
          'is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
    };

    for (final entry in definitions.entries) {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS ${entry.key} (${entry.value})',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_sync (
        catalog TEXT PRIMARY KEY,
        version TEXT,
        cursor TEXT,
        synced_at TEXT
      )
    ''');
  }

  // ===========================================================================
  // SYNC QUEUE
  // ===========================================================================
  Future<List<Map<String, dynamic>>> debugSyncQueue() async {
    final db = await database;

    return db.query('sync_queue', orderBy: 'created_at ASC');
  }

  Future<void> _createSyncQueueTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid_local TEXT NOT NULL,
      empresa_id INTEGER,
      usuario_id INTEGER,
      business_date TEXT,
      entity_type TEXT NOT NULL,
      entity_id_local INTEGER,
      payload_json TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      server_status TEXT DEFAULT 'not_sent',
      server_id INTEGER,
      server_folio TEXT,
      server_uuid TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_attempt_at TEXT,
      next_retry_at TEXT,
      synced_at TEXT,
      server_received_at TEXT,
      error_code TEXT,
      error_message TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(uuid_local, entity_type)
    )
  ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status '
      'ON sync_queue(status)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry '
      'ON sync_queue(next_retry_at)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_business_date '
      'ON sync_queue(business_date)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity '
      'ON sync_queue(entity_type, entity_id_local)',
    );
  }

  // ===========================================================================
  // DATABASE UPGRADE
  // ===========================================================================

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfNotExists(
        db,
        'sales',
        'sync_status',
        "TEXT DEFAULT 'pending'",
      );

      await _addColumnIfNotExists(db, 'sales', 'payment_method', 'TEXT');

      await _addColumnIfNotExists(
        db,
        'sales',
        'cash_received',
        'REAL DEFAULT 0',
      );

      await _addColumnIfNotExists(db, 'sales', 'change_due', 'REAL DEFAULT 0');

      await _addColumnIfNotExists(db, 'sales', 'paid_at', 'TEXT');
    }

    if (oldVersion < 3) {
      await _addColumnIfNotExists(db, 'sales', 'mesa_id', 'INTEGER');

      await _addColumnIfNotExists(db, 'sales', 'mesa_nombre', 'TEXT');
    }

    if (oldVersion < 4) {
      await _createCatalogTables(db);
    }

    if (oldVersion < 5) {
      await _addColumnIfNotExists(db, 'products', 'data_json', 'TEXT');

      await _addColumnIfNotExists(db, 'products', 'updated_at', 'TEXT');
    }

    if (oldVersion < 6) {
      await _createCompanyTable(db);
    }

    if (oldVersion < 7) {
      final columns = <String, String>{
        'server_id': 'INTEGER',
        'server_folio': 'TEXT',
        'business_date': 'TEXT',
        'cliente_id': 'INTEGER',
        'descuento_global': 'REAL DEFAULT 0',
        'impuesto_global': 'REAL DEFAULT 0',
        'notas': 'TEXT',
        'sync_attempts': 'INTEGER DEFAULT 0',
        'next_retry_at': 'TEXT',
        'last_sync_error': 'TEXT',
        'server_synced_at': 'TEXT',
      };

      for (final entry in columns.entries) {
        await _addColumnIfNotExists(db, 'sales', entry.key, entry.value);
      }

      await _addColumnIfNotExists(
        db,
        'sale_items',
        'descuento',
        'REAL DEFAULT 0',
      );

      await _addColumnIfNotExists(db, 'sale_payments', 'referencia', 'TEXT');

      await _addColumnIfNotExists(db, 'catalog_sync', 'cursor', 'TEXT');

      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_uuid_local '
        'ON sales(uuid_local)',
      );

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_business_date '
        'ON sales(business_date)',
      );
    }

    if (oldVersion < 8) {
      await _addColumnIfNotExists(
        db,
        'sales',
        'print_ticket',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    // =========================================================================
    // VERSION 9
    // products.id = ID LOCAL
    // products.server_id = ID DEL SERVIDOR
    // =========================================================================
    if (oldVersion < 9) {
      await _addColumnIfNotExists(db, 'products', 'server_id', 'INTEGER');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_server_id '
        'ON products(server_id)',
      );

      /*
       * Compatibilidad con instalaciones anteriores.
       *
       * Antes de introducir server_id, los productos descargados
       * del servidor utilizaban el mismo valor para id local y
       * id remoto.
       *
       * Por eso inicializamos:
       *
       * local id 5 -> server id 5
       *
       * Los productos que posteriormente se resuelvan con otro
       * servidor actualizarán server_id.
       */
      await db.execute('''
        UPDATE products
        SET server_id = id
        WHERE server_id IS NULL
          AND id > 0
      ''');
    }

    // =========================================================================
    // VERSION 10
    // categories.id = ID LOCAL
    // categories.server_id = ID DEL SERVIDOR
    // products.category_id = ID LOCAL DE CATEGORIA
    // =========================================================================
    if (oldVersion < 10) {
      await _addColumnIfNotExists(db, 'categories', 'server_id', 'INTEGER');

      await _addColumnIfNotExists(db, 'products', 'category_id', 'INTEGER');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_categories_server_id '
        'ON categories(server_id)',
      );

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_category_id '
        'ON products(category_id)',
      );

      // Recuperar server_id de categorias antiguas únicamente cuando
      // data_json demuestra que el registro provenía del servidor.
      final categories = await db.query(
        'categories',
        columns: ['id', 'server_id', 'data_json'],
      );

      for (final category in categories) {
        if (_toInt(category['server_id']) > 0) {
          continue;
        }

        final raw = category['data_json'];
        if (raw == null) {
          continue;
        }

        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is Map) {
            final remoteId = _toInt(decoded['server_id'] ?? decoded['id']);

            if (remoteId > 0) {
              await db.update(
                'categories',
                {'server_id': remoteId},
                where: 'id = ?',
                whereArgs: [_toInt(category['id'])],
              );
            }
          }
        } catch (_) {}
      }

      // Recuperar category_id local de productos existentes.
      final products = await db.query(
        'products',
        columns: ['id', 'category_id', 'data_json'],
      );

      for (final product in products) {
        if (_toInt(product['category_id']) > 0) {
          continue;
        }

        final raw = product['data_json'];
        if (raw == null) {
          continue;
        }

        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is! Map) {
            continue;
          }

          final categoryRef = _toInt(
            decoded['categoria_id'] ??
                decoded['category_id'] ??
                decoded['categoryId'],
          );

          if (categoryRef <= 0) {
            continue;
          }

          final localCategory = await db.query(
            'categories',
            where: 'id = ?',
            whereArgs: [categoryRef],
            limit: 1,
          );

          int? localId;

          if (localCategory.isNotEmpty) {
            localId = _toInt(localCategory.first['id']);
          } else {
            final serverCategory = await db.query(
              'categories',
              where: 'server_id = ?',
              whereArgs: [categoryRef],
              limit: 1,
            );

            if (serverCategory.isNotEmpty) {
              localId = _toInt(serverCategory.first['id']);
            }
          }

          if (localId != null && localId > 0) {
            await db.update(
              'products',
              {'category_id': localId},
              where: 'id = ?',
              whereArgs: [_toInt(product['id'])],
            );
          }
        } catch (_) {}
      }
    }
    // =========================================================================
    // VERSION 11
    // Cola local de operaciones pendientes de sincronización.
    // =========================================================================
    if (oldVersion < 11) {
      await _createSyncQueueTable(db);
    }
  }

  Future<void> _addColumnIfNotExists(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');

    if (!columns.any(
      (columnInfo) => columnInfo['name']?.toString() == column,
    )) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  int? _nullableInt(dynamic value) {
    final valueInt = _toInt(value);

    return valueInt > 0 ? valueInt : null;
  }

  String? _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return null;
  }

  int _activeValue(Map<String, dynamic> data) {
    final value = data['is_active'] ?? data['activo'] ?? data['active'] ?? 1;

    if (value is bool) {
      return value ? 1 : 0;
    }

    if (value is num) {
      return value == 0 ? 0 : 1;
    }

    final normalized = value.toString().trim().toLowerCase();

    return const {
          'false',
          '0',
          'no',
          'inactive',
          'inactivo',
        }.contains(normalized)
        ? 0
        : 1;
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  dynamic _decodeJson(dynamic value) {
    if (value == null) {
      return {};
    }

    try {
      return jsonDecode(value.toString());
    } catch (_) {
      return {};
    }
  }

  // ===========================================================================
  // COMPANY
  // ===========================================================================

  Future<void> upsertCompany(Map<String, dynamic> data) async {
    final db = await database;

    await db.transaction((txn) => _upsertCompanyWithExecutor(txn, data));
  }

  Future<void> _upsertCompanyWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    dynamic colors = data['colores'];
    dynamic config = data['configuracion'];

    final colorsJson = colors is String
        ? colors
        : colors == null
        ? null
        : jsonEncode(colors);

    final configJson = config is String
        ? config
        : config == null
        ? null
        : jsonEncode(config);

    await executor.insert('company', {
      'id': id,
      'nombre': data['nombre']?.toString(),
      'logo': data['logo']?.toString(),
      'logo_url': data['logo_url']?.toString(),
      'colores_json': colorsJson,
      'configuracion_json': configJson,
      'direccion': data['direccion']?.toString(),
      'telefono': data['telefono']?.toString(),
      'email_contacto': data['email_contacto']?.toString(),
      'rfc': data['rfc']?.toString(),
      'razon_social': data['razon_social']?.toString(),
      'leyenda_ticket': data['leyenda_ticket']?.toString(),
      'whatsapp_numero': data['whatsapp_numero']?.toString(),
      'activo': _activeValue(data),
      'updated_at':
          _stringValue(data, ['updated_at', 'updatedAt']) ??
          DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCompany() async {
    final db = await database;

    final rows = await db.query('company', limit: 1);

    if (rows.isEmpty) {
      return null;
    }

    final row = Map<String, dynamic>.from(rows.first);

    row['colores'] = _decodeJson(row['colores_json']);

    row['configuracion'] = _decodeJson(row['configuracion_json']);

    return row;
  }

  // ===========================================================================
  // PRODUCTS - LOCAL / SERVER
  // ===========================================================================

  Future<List<Map<String, dynamic>>> getProducts() async => (await database)
      .query('products', where: 'is_active = 1', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getAllProducts() async =>
      (await database).query('products', orderBy: 'name ASC');

  /// Busca por ID LOCAL.
  Future<Map<String, dynamic>?> getProductById(int id) async {
    if (id <= 0) {
      return null;
    }

    final rows = await (await database).query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Busca por ID DEL SERVIDOR.
  Future<Map<String, dynamic>?> getProductByServerId(int serverId) async {
    if (serverId <= 0) {
      return null;
    }

    final rows = await (await database).query(
      'products',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Busca por código.
  Future<Map<String, dynamic>?> getProductByCode(String code) async {
    final normalized = code.trim();

    if (normalized.isEmpty) {
      return null;
    }

    final rows = await (await database).query(
      'products',
      where: 'code = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Guarda la relación:
  ///
  /// ID LOCAL -> ID SERVIDOR
  Future<void> setProductServerId({
    required int localId,
    required int serverId,
  }) async {
    if (localId <= 0 || serverId <= 0) {
      return;
    }

    final updated = await (await database).update(
      'products',
      {'server_id': serverId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [localId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<int> createProduct({
    int? id,
    int? serverId,
    int? categoryId,
    required String code,
    required String name,
    required double price,
    double stock = 0,
    bool isActive = true,
    Map<String, dynamic>? data,
    String? updatedAt,
  }) async {
    return (await database).insert('products', {
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (categoryId != null) 'category_id': categoryId,
      'code': code,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': isActive ? 1 : 0,
      'data_json': data == null ? null : jsonEncode(data),
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateProduct({
    required int id,
    required String code,
    required String name,
    required double price,
    required double stock,
    bool isActive = true,
    int? serverId,
    int? categoryId,
    Map<String, dynamic>? data,
    String? updatedAt,
  }) async {
    final values = <String, dynamic>{
      'code': code,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': isActive ? 1 : 0,
      if (serverId != null) 'server_id': serverId,
      if (categoryId != null) 'category_id': categoryId,
      if (data != null) 'data_json': jsonEncode(data),
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    };

    return (await database).update(
      'products',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    return (await database).update(
      'products',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===========================================================================
  // CLIENTS / GENERIC CATALOGS
  // ===========================================================================

  Future<void> _upsertClientWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);

    if (id <= 0) {
      return;
    }

    await executor.insert('clients', {
      'id': id,
      'name': _stringValue(data, ['name', 'nombre']),
      'email': _stringValue(data, ['email', 'correo']),
      'phone': _stringValue(data, ['phone', 'telefono', 'teléfono']),
      'rfc': _stringValue(data, ['rfc']),
      'is_active': _activeValue(data),
      'data_json': jsonEncode(data),
      'updated_at':
          _stringValue(data, ['updated_at', 'updatedAt']) ??
          DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      'name': _stringValue(data, [
        'name',
        'nombre',
        'descripcion',
        'description',
      ]),
      'code': _stringValue(data, [
        'code',
        'codigo',
        'clave',
        'clave_sat',
        'abreviatura',
      ]),
      'is_active': _activeValue(data),
      'data_json': jsonEncode(data),
      'updated_at':
          _stringValue(data, ['updated_at', 'updatedAt']) ??
          DateTime.now().toIso8601String(),
    };

    if (includeRate) {
      values['rate'] = _toDouble(
        data['rate'] ?? data['tasa'] ?? data['porcentaje'] ?? data['valor'],
      );
    }

    await executor.insert(
      table,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertClient(Map<String, dynamic> data) async =>
      _upsertClientWithExecutor(await database, data);

  Future<void> upsertTax(Map<String, dynamic> data) async =>
      _upsertCatalogItem('taxes', data, includeRate: true);

  Future<void> upsertPaymentMethod(Map<String, dynamic> data) async =>
      _upsertCatalogItem('payment_methods', data);

  Future<void> upsertUnit(Map<String, dynamic> data) async =>
      _upsertCatalogItem('units', data);

  Future<void> upsertCategory(Map<String, dynamic> data) async =>
      _upsertCategoryWithExecutor(await database, data);

  Future<void> _upsertCategoryWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final serverId = _toInt(data['server_id'] ?? data['id']);

    if (serverId <= 0) {
      return;
    }

    final name =
        _stringValue(data, ['name', 'nombre', 'descripcion', 'description']) ??
        '';

    final code =
        _stringValue(data, [
          'code',
          'codigo',
          'clave',
          'abreviatura',
        ])?.trim() ??
        '';

    final active = _activeValue(data);
    final updatedAt =
        _stringValue(data, ['updated_at', 'updatedAt']) ??
        DateTime.now().toIso8601String();
    final json = jsonEncode(data);

    final byServerId = await executor.query(
      'categories',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );

    if (byServerId.isNotEmpty) {
      final localId = _toInt(byServerId.first['id']);

      await executor.update(
        'categories',
        {
          'server_id': serverId,
          'name': name,
          'code': code,
          'is_active': active,
          'data_json': json,
          'updated_at': updatedAt,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      return;
    }

    // Compatibilidad con una categoria local creada previamente con
    // el mismo codigo. Se conserva su ID local y se enlaza al servidor.
    if (code.isNotEmpty) {
      final byCode = await executor.query(
        'categories',
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      if (byCode.isNotEmpty) {
        final localId = _toInt(byCode.first['id']);

        await executor.update(
          'categories',
          {
            'server_id': serverId,
            'name': name,
            'code': code,
            'is_active': active,
            'data_json': json,
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );

        return;
      }
    }

    await executor.insert('categories', {
      // No usamos el ID remoto como ID local.
      'server_id': serverId,
      'name': name,
      'code': code,
      'is_active': active,
      'data_json': json,
      'updated_at': updatedAt,
    });
  }

  Future<void> upsertPromotion(Map<String, dynamic> data) async =>
      _upsertCatalogItem('promotions', data);

  Future<void> upsertCoupon(Map<String, dynamic> data) async =>
      _upsertCatalogItem('coupons', data);

  Future<void> _upsertCatalogItem(
    String table,
    Map<String, dynamic> data, {
    bool includeRate = false,
  }) async {
    await _upsertCatalogWithExecutor(
      await database,
      table: table,
      data: data,
      includeRate: includeRate,
    );
  }

  Future<List<Map<String, dynamic>>> getClients() async => (await database)
      .query('clients', where: 'is_active = 1', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getAllClients() async =>
      (await database).query('clients', orderBy: 'name ASC');

  Future<Map<String, dynamic>?> getClientById(int id) async {
    final rows = await (await database).query(
      'clients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getTaxes() async => (await database).query(
    'taxes',
    where: 'is_active = 1',
    orderBy: 'name ASC',
  );

  Future<List<Map<String, dynamic>>> getAllTaxes() async =>
      (await database).query('taxes', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getPaymentMethods() async =>
      (await database).query(
        'payment_methods',
        where: 'is_active = 1',
        orderBy: 'name ASC',
      );

  Future<List<Map<String, dynamic>>> getAllPaymentMethods() async =>
      (await database).query('payment_methods', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getUnits() async => (await database).query(
    'units',
    where: 'is_active = 1',
    orderBy: 'name ASC',
  );

  Future<List<Map<String, dynamic>>> getAllUnits() async =>
      (await database).query('units', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getCategories() async => (await database)
      .query('categories', where: 'is_active = 1', orderBy: 'name ASC');

  // ===========================================================================
  // SYNC QUEUE - OPERATIONS
  // ===========================================================================

  Future<int> enqueueSyncOperation({
    required String uuidLocal,
    required String entityType,
    required Map<String, dynamic> payload,
    int? empresaId,
    int? usuarioId,
    String? businessDate,
    int? entityIdLocal,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return db.insert('sync_queue', {
      'uuid_local': uuidLocal,
      'empresa_id': empresaId,
      'usuario_id': usuarioId,
      'business_date': businessDate,
      'entity_type': entityType,
      'entity_id_local': entityIdLocal,
      'payload_json': jsonEncode(payload),
      'status': 'pending',
      'server_status': 'not_sent',
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingSyncQueue({int? limit}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return db.query(
      'sync_queue',
      where:
          "status IN ('pending', 'failed') "
          "AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [now],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> markSyncQueueSyncing(int id) async {
    final now = DateTime.now().toIso8601String();

    await (await database).update(
      'sync_queue',
      {'status': 'syncing', 'last_attempt_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncQueueSynced(
    int id, {
    int? serverId,
    String? serverFolio,
    String? serverUuid,
    String? serverStatus,
    String? serverReceivedAt,
  }) async {
    final now = DateTime.now().toIso8601String();

    await (await database).update(
      'sync_queue',
      {
        'status': 'synced',
        'server_status': serverStatus ?? 'accepted',
        'server_id': serverId,
        'server_folio': serverFolio,
        'server_uuid': serverUuid,
        'server_received_at': serverReceivedAt,
        'synced_at': now,
        'error_code': null,
        'error_message': null,
        'next_retry_at': null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncQueueFailed(
    int id, {
    String? errorCode,
    required String errorMessage,
  }) async {
    final db = await database;

    final rows = await db.query(
      'sync_queue',
      columns: ['attempts'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    final currentAttempts = rows.isEmpty ? 0 : _toInt(rows.first['attempts']);

    final attempts = currentAttempts + 1;

    final retryMinutes = attempts.clamp(1, 30) * 2;

    final nextRetry = DateTime.now().add(Duration(minutes: retryMinutes));

    final now = DateTime.now().toIso8601String();

    await db.update(
      'sync_queue',
      {
        'status': 'failed',
        'server_status': 'unknown',
        'attempts': attempts,
        'last_attempt_at': now,
        'next_retry_at': nextRetry.toIso8601String(),
        'error_code': errorCode,
        'error_message': errorMessage,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Genera la siguiente clave disponible para una categoría.
  ///
  /// Ejemplos:
  ///   Bebidas   -> BEB-001
  ///   Alimentos -> ALI-001
  ///   Bebidas   -> BEB-002
  ///
  /// La secuencia se calcula únicamente entre categorías.
  /// Los productos NO participan en esta numeración.
  Future<String> getNextCategoryCode(String categoryName) async {
    final name = categoryName.trim();

    if (name.isEmpty) {
      return 'CAT-001';
    }

    String removeAccents(String value) {
      const accents = 'áéíóúÁÉÍÓÚüÜñÑ';
      const replacements = 'aeiouAEIOUuUnN';

      var result = value;

      for (var i = 0; i < accents.length; i++) {
        result = result.replaceAll(accents[i], replacements[i]);
      }

      return result;
    }

    String buildPrefix(String value) {
      final normalized = removeAccents(value)
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ')
          .trim();

      if (normalized.isEmpty) {
        return 'CAT';
      }

      final words = normalized
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();

      if (words.isEmpty) {
        return 'CAT';
      }

      if (words.length == 1) {
        final word = words.first;

        if (word.length >= 3) {
          return word.substring(0, 3);
        }

        return word.padRight(3, 'X');
      }

      final first = words[0];
      final second = words[1];

      if (first.length >= 2) {
        return (first.substring(0, 2) + second.substring(0, 1)).padRight(
          3,
          'X',
        );
      }

      return (first.substring(0, 1) + second.substring(0, 2)).padRight(3, 'X');
    }

    final prefix = buildPrefix(name);

    final rows = await (await database).query('categories', columns: ['code']);

    var maxSequence = 0;

    final pattern = RegExp(
      '^${RegExp.escape(prefix)}-(\\d{3,})\$',
      caseSensitive: false,
    );

    for (final row in rows) {
      final code = row['code']?.toString().trim() ?? '';

      if (code.isEmpty) {
        continue;
      }

      final match = pattern.firstMatch(code);

      if (match == null) {
        continue;
      }

      final sequence = int.tryParse(match.group(1) ?? '');

      if (sequence != null && sequence > maxSequence) {
        maxSequence = sequence;
      }
    }

    final nextSequence = maxSequence + 1;

    return '$prefix-${nextSequence.toString().padLeft(3, '0')}';
  }

  Future<List<Map<String, dynamic>>> getAllCategories() async =>
      (await database).query('categories', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getPromotions() async => (await database)
      .query('promotions', where: 'is_active = 1', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getAllPromotions() async =>
      (await database).query('promotions', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getCoupons() async => (await database)
      .query('coupons', where: 'is_active = 1', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getAllCoupons() async =>
      (await database).query('coupons', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getCatalogItems(
    String table, {
    bool activeOnly = true,
  }) async {
    _validateCatalogTable(table);

    final rows = await (await database).query(
      table,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );

    return rows
        .map(
          (row) => {
            ...row,
            'id': _toInt(row['id']),
            'is_active': _toInt(row['is_active']),
            if (table == 'taxes') 'rate': _toDouble(row['rate']),
          },
        )
        .toList();
  }

  static const _catalogTables = {
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

  Future<int> createCatalogItem({
    required String table,
    required String name,
    String? code,
    double? rate,
    bool isActive = true,
    Map<String, dynamic>? data,
  }) async {
    _validateCatalogTable(table);

    return (await database).insert(table, {
      'name': name.trim(),
      'code': code?.trim(),
      if (table == 'taxes') 'rate': rate ?? 0,
      'is_active': isActive ? 1 : 0,
      'data_json': data == null ? null : jsonEncode(data),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateCatalogItem({
    required String table,
    required int id,
    required String name,
    String? code,
    double? rate,
    bool active = true,
    Map<String, dynamic>? data,
  }) async {
    _validateCatalogTable(table);

    return (await database).update(
      table,
      {
        'name': name.trim(),
        'code': code?.trim(),
        if (table == 'taxes') 'rate': rate ?? 0,
        'is_active': active ? 1 : 0,
        if (data != null) 'data_json': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCatalogItem(String table, int id) async {
    _validateCatalogTable(table);

    return (await database).update(
      table,
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> restoreCatalogItem({
    required String table,
    required int id,
  }) async {
    _validateCatalogTable(table);

    return (await database).update(
      table,
      {'is_active': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> createClient({
    required String name,
    String? email,
    String? phone,
    String? rfc,
    bool isActive = true,
  }) async => (await database).insert('clients', {
    'name': name.trim(),
    'email': email?.trim(),
    'phone': phone?.trim(),
    'rfc': rfc?.trim(),
    'is_active': isActive ? 1 : 0,
    'updated_at': DateTime.now().toIso8601String(),
  });

  Future<int> updateClient({
    required int id,
    required String name,
    String? email,
    String? phone,
    String? rfc,
    bool isActive = true,
  }) async => (await database).update(
    'clients',
    {
      'name': name.trim(),
      'email': email?.trim(),
      'phone': phone?.trim(),
      'rfc': rfc?.trim(),
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<int> deleteClient(int id) async => (await database).update(
    'clients',
    {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );

  // ===========================================================================
  // SYNC CATALOGS
  // ===========================================================================

  Future<void> syncCatalogs(Map<String, dynamic> response) async {
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'])
        : response;

    final db = await database;

    await db.transaction((txn) async {
      if (data['empresa'] is Map) {
        await _upsertCompanyWithExecutor(
          txn,
          Map<String, dynamic>.from(data['empresa']),
        );
      }

      // Las categorias deben existir primero para resolver
      // categoria server_id -> categoria id local en productos.
      for (final category in _asList(data['categorias'])) {
        await _upsertCategoryWithExecutor(txn, category);
      }

      for (final product in _asList(data['productos'])) {
        await _upsertProductWithExecutor(txn, product);
      }

      for (final client in _asList(data['clientes'])) {
        await _upsertClientWithExecutor(txn, client);
      }

      for (final item in _asList(data['impuestos'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'taxes',
          data: item,
          includeRate: true,
        );
      }

      for (final item in _asList(data['formas_pago'])) {
        await _upsertCatalogWithExecutor(
          txn,
          table: 'payment_methods',
          data: item,
        );
      }

      for (final item in _asList(data['unidades_medida'])) {
        await _upsertCatalogWithExecutor(txn, table: 'units', data: item);
      }

      for (final item in _asList(data['promociones'])) {
        await _upsertCatalogWithExecutor(txn, table: 'promotions', data: item);
      }

      for (final item in _asList(data['cupones'])) {
        await _upsertCatalogWithExecutor(txn, table: 'coupons', data: item);
      }

      if (data['versiones'] is Map) {
        for (final entry in (data['versiones'] as Map).entries) {
          await txn.insert('catalog_sync', {
            'catalog': entry.key.toString(),
            'version': entry.value?.toString(),
            'synced_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });

    await _processTombstones(data['tombstones']);

    notifySalesChanged();
  }

  Future<int?> _resolveLocalCategoryId(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    dynamic rawCategory =
        data['categoria_id'] ?? data['category_id'] ?? data['categoryId'];

    if (rawCategory == null && data['categoria'] is Map) {
      rawCategory = (data['categoria'] as Map)['id'];
    }

    if (rawCategory == null && data['category'] is Map) {
      rawCategory = (data['category'] as Map)['id'];
    }

    final categoryRef = _toInt(rawCategory);

    if (categoryRef <= 0) {
      return null;
    }

    final byServerId = await executor.query(
      'categories',
      where: 'server_id = ?',
      whereArgs: [categoryRef],
      limit: 1,
    );

    if (byServerId.isNotEmpty) {
      final localId = _toInt(byServerId.first['id']);
      return localId > 0 ? localId : null;
    }

    final byLocalId = await executor.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryRef],
      limit: 1,
    );

    if (byLocalId.isNotEmpty) {
      final localId = _toInt(byLocalId.first['id']);
      return localId > 0 ? localId : null;
    }

    return null;
  }

  /// Sincroniza un producto recibido desde el servidor.
  ///
  /// Reglas:
  ///
  /// 1. Buscar por server_id.
  /// 2. Si no existe, buscar por código.
  /// 3. Si tampoco existe, crear un nuevo ID local.
  ///
  /// Nunca se fuerza:
  ///
  /// local.id = server.id
  Future<void> _upsertProductWithExecutor(
    dynamic executor,
    Map<String, dynamic> data,
  ) async {
    final serverId = _toInt(data['id']);

    if (serverId <= 0) {
      return;
    }

    final code = _stringValue(data, ['code', 'codigo', 'sku'])?.trim() ?? '';

    final name = _stringValue(data, ['name', 'nombre']) ?? '';

    final price = _toDouble(
      data['price'] ?? data['precio'] ?? data['precio_venta'],
    );

    final stock = _toDouble(
      data['stock'] ?? data['existencia'] ?? data['cantidad'],
    );

    final active = _activeValue(data);

    final updatedAt =
        _stringValue(data, ['updated_at', 'updatedAt']) ??
        DateTime.now().toIso8601String();

    final json = jsonEncode(data);
    final categoryId = await _resolveLocalCategoryId(executor, data);

    // -------------------------------------------------------------------------
    // 1. Buscar por ID de servidor
    // -------------------------------------------------------------------------

    final byServerId = await executor.query(
      'products',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );

    if (byServerId.isNotEmpty) {
      final localId = _toInt(byServerId.first['id']);

      await executor.update(
        'products',
        {
          'server_id': serverId,
          if (categoryId != null) 'category_id': categoryId,
          'code': code,
          'name': name,
          'price': price,
          'stock': stock,
          'is_active': active,
          'data_json': json,
          'updated_at': updatedAt,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      return;
    }

    // -------------------------------------------------------------------------
    // 2. Buscar por código
    // -------------------------------------------------------------------------

    if (code.isNotEmpty) {
      final byCode = await executor.query(
        'products',
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      if (byCode.isNotEmpty) {
        final localId = _toInt(byCode.first['id']);

        await executor.update(
          'products',
          {
            'server_id': serverId,
            if (categoryId != null) 'category_id': categoryId,
            'code': code,
            'name': name,
            'price': price,
            'stock': stock,
            'is_active': active,
            'data_json': json,
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );

        return;
      }
    }

    // -------------------------------------------------------------------------
    // 3. Producto completamente nuevo
    // -------------------------------------------------------------------------

    await executor.insert('products', {
      /*
         * IMPORTANTE:
         *
         * No ponemos 'id': serverId.
         *
         * SQLite generará el ID local.
         */
      'server_id': serverId,
      if (categoryId != null) 'category_id': categoryId,
      'code': code,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': active,
      'data_json': json,
      'updated_at': updatedAt,
    });
  }

  Future<void> upsertProductFromApi(Map<String, dynamic> data) async {
    await _upsertProductWithExecutor(await database, data);

    notifySalesChanged();
  }

  // ===========================================================================
  // APPLY LOCAL -> SERVER PRODUCT MAPPINGS
  // ===========================================================================

  Future<void> applySyncProductMappings(dynamic mappings) async {
    if (mappings is! List) {
      return;
    }

    final db = await database;

    var updated = 0;

    await db.transaction((txn) async {
      for (final raw in mappings) {
        if (raw is! Map) {
          continue;
        }

        final item = Map<String, dynamic>.from(raw);

        final localId = _toInt(item['producto_local_id']);

        final serverId = _toInt(item['producto_server_id']);

        if (localId <= 0 || serverId <= 0) {
          continue;
        }

        final count = await txn.update(
          'products',
          {
            'server_id': serverId,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );

        updated += count;
      }
    });

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  // ===========================================================================
  // TOMBSTONES
  // ===========================================================================

  Future<void> _processTombstones(dynamic data) async {
    if (data is! Map) {
      return;
    }

    final db = await database;

    const map = {
      'productos': 'products',
      'clientes': 'clients',
      'impuestos': 'taxes',
      'formas_pago': 'payment_methods',
      'unidades_medida': 'units',
      'categorias': 'categories',
      'promociones': 'promotions',
      'cupones': 'coupons',
    };

    await db.transaction((txn) async {
      for (final entry in map.entries) {
        final values = data[entry.key];

        if (values is! List) {
          continue;
        }

        for (final value in values) {
          final id = _toInt(value is Map ? value['id'] : value);

          if (id <= 0) {
            continue;
          }

          /*
             * Productos:
             *
             * El ID recibido por tombstone es el
             * ID DEL SERVIDOR.
             */
          if (entry.key == 'productos' || entry.key == 'categorias') {
            await txn.delete(
              entry.value,
              where: 'server_id = ?',
              whereArgs: [id],
            );
          } else {
            await txn.delete(entry.value, where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    });
  }

  // ===========================================================================
  // CATALOG CURSORS
  // ===========================================================================

  Future<String?> getCatalogVersion(String catalog) async {
    final rows = await (await database).query(
      'catalog_sync',
      where: 'catalog = ?',
      whereArgs: [catalog],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first['version']?.toString();
  }

  Future<String?> getCatalogCursor(String catalog) async {
    final rows = await (await database).query(
      'catalog_sync',
      where: 'catalog = ?',
      whereArgs: [catalog],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first['cursor']?.toString();
  }

  Future<void> setCatalogVersion(
    String catalog,
    String? version, {
    String? cursor,
  }) async {
    await (await database).insert('catalog_sync', {
      'catalog': catalog,
      'version': version,
      'cursor': cursor,
      'synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String?>> getCatalogVersions() async {
    final rows = await (await database).query('catalog_sync');

    return {
      for (final row in rows)
        row['catalog'].toString(): row['version']?.toString(),
    };
  }

  // ===========================================================================
  // SALES / HISTORICAL QUEUE
  // ===========================================================================

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
    int? clienteId,
    double descuentoGlobal = 0,
    double impuestoGlobal = 0,
    String? notas,
    String? businessDate,
    bool printTicket = false,
  }) async {
    final db = await database;

    var created = false;

    final saleId = await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();

      final existing = await txn.query(
        'sales',
        where: 'uuid_local = ?',
        whereArgs: [uuid],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        return _toInt(existing.first['id']);
      }

      final id = await txn.insert('sales', {
        'uuid_local': uuid,
        'business_date': businessDate ?? now.substring(0, 10),
        'total': total,
        'status': status,
        'sync_status': syncStatus,
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_due': changeDue,
        'mesa_id': tableId,
        'mesa_nombre': tableName,
        'cliente_id': clienteId,
        'descuento_global': descuentoGlobal,
        'impuesto_global': impuestoGlobal,
        'notas': notas,
        'created_at': now,
        'updated_at': now,
        'paid_at': status == 'paid' ? now : null,
        'print_ticket': printTicket ? 1 : 0,
      });

      for (final item in items) {
        await txn.insert('sale_items', {
          'sale_id': id,
          'product_id': _toInt(item['product_id']),
          'name': item['name'],
          'quantity': _toDouble(item['quantity']),
          'unit_price': _toDouble(item['unit_price']),
          'total': _toDouble(item['total']),
          'descuento': _toDouble(item['descuento']),
        });
      }

      for (final payment in payments) {
        await txn.insert('sale_payments', {
          'sale_id': id,
          'method': payment['method'],
          'amount': _toDouble(payment['amount']),
          'referencia': payment['referencia'],
        });
      }

      created = true;

      return id;
    });

    if (created) {
      notifySalesChanged();
    }

    return saleId;
  }

  Future<void> setSalePrintTicket(int saleId, bool printed) async {
    final updated = await (await database).update(
      'sales',
      {
        'print_ticket': printed ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<List<Map<String, dynamic>>> getTodaySales() async {
    final db = await database;

    final now = DateTime.now();

    final todayYear = now.year;
    final todayMonth = now.month;
    final todayDay = now.day;

    final rows = await db.query('sales', orderBy: 'created_at DESC');

    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final createdAt = row['created_at']?.toString();

      if (createdAt != null && createdAt.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(createdAt);

        if (parsed != null) {
          final local = parsed.toLocal();

          if (local.year == todayYear &&
              local.month == todayMonth &&
              local.day == todayDay) {
            result.add(Map<String, dynamic>.from(row));
          }

          continue;
        }
      }

      if (row['business_date']?.toString() ==
          '${todayYear.toString().padLeft(4, '0')}-'
              '${todayMonth.toString().padLeft(2, '0')}-'
              '${todayDay.toString().padLeft(2, '0')}') {
        result.add(Map<String, dynamic>.from(row));
      }
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getSales({
    String? businessDate,
    String? syncStatus,
    int? limit,
  }) async {
    final db = await database;

    final where = <String>[];
    final args = <dynamic>[];

    if (businessDate != null) {
      where.add('business_date = ?');

      args.add(businessDate);
    }

    if (syncStatus != null) {
      where.add('sync_status = ?');

      args.add(syncStatus);
    }

    return db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSales({
    bool includeFailed = true,
  }) async => getSales(syncStatus: includeFailed ? null : 'pending').then(
    (rows) => rows
        .where(
          (row) =>
              row['sync_status'] == 'pending' || row['sync_status'] == 'failed',
        )
        .toList(),
  );

  Future<Map<String, dynamic>?> getSaleById(int id) async {
    final rows = await (await database).query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getSaleItemsBySaleId(int id) async =>
      (await database).query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [id],
      );

  Future<List<Map<String, dynamic>>> getSalePaymentsBySaleId(int id) async =>
      (await database).query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [id],
      );

  Future<void> markSaleSyncing(int saleId) async {
    final updated = await (await database).update(
      'sales',
      {
        'sync_status': 'syncing',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  /// Marca una venta como sincronizada y captura:
  ///
  /// - venta_id
  /// - folio
  /// - server_id
  ///
  /// Soporta respuestas:
  ///
  /// {
  ///   venta_id: 123
  /// }
  ///
  /// o:
  ///
  /// {
  ///   procesadas: [
  ///     {
  ///       venta_id: 123,
  ///       folio: "V-26-000123"
  ///     }
  ///   ]
  /// }
  Future<void> markSaleAsSynced(
    int saleId, {
    Map<String, dynamic>? serverResponse,
  }) async {
    final response = serverResponse ?? const <String, dynamic>{};

    Map<String, dynamic> nested = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'])
        : Map<String, dynamic>.from(response);

    /*
     * Si la API devuelve:
     *
     * procesadas: [
     *   {
     *      venta_id: 123,
     *      folio: ...
     *   }
     * ]
     *
     * usamos el primer registro correspondiente.
     */
    final processed = nested['procesadas'];

    if (processed is List && processed.isNotEmpty && processed.first is Map) {
      final first = Map<String, dynamic>.from(processed.first);

      nested = {...nested, ...first};
    }

    final serverId = _nullableInt(
      nested['server_id'] ?? nested['venta_id'] ?? nested['id'],
    );

    final serverFolio =
        nested['folio']?.toString() ?? nested['server_folio']?.toString();

    final updated = await (await database).update(
      'sales',
      {
        'sync_status': 'synced',
        'server_id': serverId,
        'server_folio': serverFolio,
        'server_synced_at': DateTime.now().toIso8601String(),
        'last_sync_error': null,
        'next_retry_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<void> markSaleSyncFailed(
    int saleId,
    String error, {
    int? attempts,
  }) async {
    final db = await database;

    final sale = await getSaleById(saleId);

    final count = attempts ?? (_toInt(sale?['sync_attempts']) + 1);

    final retry = DateTime.now().add(
      Duration(minutes: count.clamp(1, 30).toInt() * 2),
    );

    final updated = await db.update(
      'sales',
      {
        'sync_status': 'failed',
        'sync_attempts': count,
        'last_sync_error': error,
        'next_retry_at': retry.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<void> resetSaleForRetry(int saleId) async {
    final updated = await (await database).update(
      'sales',
      {
        'sync_status': 'pending',
        'next_retry_at': null,
        'last_sync_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<void> updateSaleServerResult(
    int saleId,
    Map<String, dynamic> response,
  ) async {
    await markSaleAsSynced(saleId, serverResponse: response);
  }

  Future<List<Map<String, dynamic>>> getPendingSalesReadyToSync({
    int? limit,
  }) async {
    final db = await database;

    final now = DateTime.now().toIso8601String();

    return db.query(
      'sales',
      where:
          "sync_status IN ('pending','failed') "
          "AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [now],
      orderBy: 'business_date ASC, created_at ASC',
      limit: limit,
    );
  }

  Future<void> updateSaleStatus(
    int saleId,
    String status, {
    String syncStatus = 'pending',
  }) async {
    final now = DateTime.now().toIso8601String();

    final updated = await (await database).update(
      'sales',
      {
        'status': status,
        'sync_status': syncStatus,
        'updated_at': now,
        'paid_at': status == 'paid' ? now : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<void> markSaleAsPaid(
    int saleId, {
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final now = DateTime.now().toIso8601String();

    final updated = await (await database).update(
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

    if (updated > 0) {
      notifySalesChanged();
    }
  }

  Future<bool> cancelSale(int saleId) async {
    final db = await database;

    final cancelled = await db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );

      if (rows.isEmpty || rows.first['status'] == 'cancelled') {
        return false;
      }

      final updated = await txn.update(
        'sales',
        {
          'status': 'cancelled',
          'sync_status': 'pending',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      return updated == 1;
    });

    if (cancelled) {
      notifySalesChanged();
    }

    return cancelled;
  }

  Future<bool> deletePendingSale(int saleId) async {
    final db = await database;

    final deleted = await db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ? AND status = ?',
        whereArgs: [saleId, 'pending'],
        limit: 1,
      );

      if (rows.isEmpty) {
        return false;
      }

      await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);

      await txn.delete(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      return (await txn.delete(
            'sales',
            where: 'id = ?',
            whereArgs: [saleId],
          )) ==
          1;
    });

    if (deleted) {
      notifySalesChanged();
    }

    return deleted;
  }

  Future<bool> updatePendingSale({
    required int saleId,
    required List<Map<String, dynamic>> items,
    required double total,
    int? tableId,
    String? tableName,
  }) async {
    final db = await database;

    final updated = await db.transaction((txn) async {
      final count = await txn.update(
        'sales',
        {
          'total': total,
          'mesa_id': tableId,
          'mesa_nombre': tableName,
          'updated_at': DateTime.now().toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ? AND status = ?',
        whereArgs: [saleId, 'pending'],
      );

      if (count != 1) {
        return false;
      }

      await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);

      for (final item in items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': _toInt(item['product_id']),
          'name': item['name'],
          'quantity': _toDouble(item['quantity']),
          'unit_price': _toDouble(item['unit_price']),
          'total': _toDouble(item['total']),
          'descuento': _toDouble(item['descuento']),
        });
      }

      return true;
    });

    if (updated) {
      notifySalesChanged();
    }

    return updated;
  }

  Future<bool> payPendingSale(
    int saleId, {
    required List<Map<String, dynamic>> payments,
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final db = await database;

    final paid = await db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ? AND status = ?',
        whereArgs: [saleId, 'pending'],
        limit: 1,
      );

      if (rows.isEmpty) {
        return false;
      }

      await txn.delete(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      for (final payment in payments) {
        await txn.insert('sale_payments', {
          'sale_id': saleId,
          'method': payment['method'],
          'amount': _toDouble(payment['amount']),
          'referencia': payment['referencia'],
        });
      }

      final updated = await txn.update(
        'sales',
        {
          'status': 'paid',
          'sync_status': 'pending',
          'payment_method': paymentMethod,
          'cash_received': cashReceived,
          'change_due': changeDue,
          'paid_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'print_ticket': 0,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      return updated == 1;
    });

    if (paid) {
      notifySalesChanged();
    }

    return paid;
  }

  /// Copia una venta pendiente de la base diaria a esta base histórica.
  ///
  /// Si ya existe por uuid, no duplica.
  Future<int> archiveDailySale({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
  }) async {
    return saveSale(
      uuid: sale['uuid_local']?.toString() ?? '',
      items: items,
      payments: payments,
      total: _toDouble(sale['total']),
      status: sale['status']?.toString() ?? 'paid',
      syncStatus: sale['sync_status']?.toString() ?? 'pending',
      paymentMethod: sale['payment_method']?.toString(),
      cashReceived: _toDouble(sale['cash_received']),
      changeDue: _toDouble(sale['change_due']),
      tableId: _nullableInt(sale['mesa_id']),
      tableName: sale['mesa_nombre']?.toString(),
      clienteId: _nullableInt(sale['cliente_id']),
      descuentoGlobal: _toDouble(sale['descuento_global']),
      impuestoGlobal: _toDouble(sale['impuesto_global']),
      notas: sale['notas']?.toString(),
      businessDate:
          sale['business_date']?.toString() ??
          sale['created_at']?.toString().substring(0, 10),
      printTicket: _toInt(sale['print_ticket']) != 0,
    );
  }

  Future<bool> hasPendingSales() async => (await getPendingSales()).isNotEmpty;

  Future<Map<String, int>> getSyncSummary() async {
    final rows = await (await database).rawQuery(
      'SELECT sync_status, COUNT(*) total '
      'FROM sales '
      'GROUP BY sync_status',
    );

    return {
      for (final row in rows)
        row['sync_status'].toString(): _toInt(row['total']),
    };
  }

  Future<Map<String, dynamic>?> getSyncStatus(int saleId) async {
    final sale = await getSaleById(saleId);

    if (sale == null) {
      return null;
    }

    return {
      'sync_status': sale['sync_status'],
      'server_id': sale['server_id'],
      'server_folio': sale['server_folio'],
      'server_synced_at': sale['server_synced_at'],
      'last_sync_error': sale['last_sync_error'],
      'business_date': sale['business_date'],
      'sync_attempts': _toInt(sale['sync_attempts']),
    };
  }

  Future<Map<String, int>> getCatalogCounts() async {
    final db = await database;

    Future<int> count(String table) async {
      return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;
    }

    return {
      'productos': await count('products'),
      'clientes': await count('clients'),
      'impuestos': await count('taxes'),
      'formas_pago': await count('payment_methods'),
      'unidades_medida': await count('units'),
      'categorias': await count('categories'),
      'promociones': await count('promotions'),
      'cupones': await count('coupons'),
    };
  }

  // ===========================================================================
  // CLEAR / CLOSE
  // ===========================================================================

  Future<void> clearDb() async {
    final db = await database;

    await db.transaction((txn) async {
      for (final table in [
        'sale_items',
        'sale_payments',
        'sales',
        'products',
        'clients',
        'taxes',
        'payment_methods',
        'units',
        'categories',
        'promotions',
        'coupons',
        'catalog_sync',
        'company',
      ]) {
        await txn.delete(table);
      }
    });

    notifySalesChanged();
  }

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }

    // No cerrar _salesChanges:
    // es un notificador estático de proceso y LocalDb
    // puede volver a abrirse después de cambiar de día.
  }
}

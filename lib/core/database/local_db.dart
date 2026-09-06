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
  static const int _databaseVersion = 7;

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
    if (_database != null) return _database!;
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
  }

  Future<void> _createCompanyTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS company (
      id INTEGER PRIMARY KEY,
      nombre TEXT, logo TEXT, logo_url TEXT, colores_json TEXT,
      configuracion_json TEXT, direccion TEXT, telefono TEXT,
      email_contacto TEXT, rfc TEXT, razon_social TEXT,
      leyenda_ticket TEXT, whatsapp_numero TEXT,
      activo INTEGER DEFAULT 1, updated_at TEXT
    )''');
  }

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS products (
      id INTEGER PRIMARY KEY, code TEXT, name TEXT,
      price REAL DEFAULT 0, stock REAL DEFAULT 0,
      is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_code ON products(code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active)');
  }

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sales (
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
      UNIQUE(uuid_local)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER,
      product_id INTEGER, name TEXT, quantity REAL DEFAULT 0,
      unit_price REAL DEFAULT 0, total REAL DEFAULT 0,
      descuento REAL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER,
      method TEXT, amount REAL DEFAULT 0, referencia TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_sync_status ON sales(sync_status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_business_date ON sales(business_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_payments_sale_id ON sale_payments(sale_id)');
  }

  Future<void> _createCatalogTables(Database db) async {
    final definitions = <String, String>{
      'clients': 'id INTEGER PRIMARY KEY, name TEXT, email TEXT, phone TEXT, rfc TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'taxes': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, rate REAL DEFAULT 0, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'payment_methods': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'units': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'categories': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'promotions': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
      'coupons': 'id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1, data_json TEXT, updated_at TEXT',
    };
    for (final entry in definitions.entries) {
      await db.execute('CREATE TABLE IF NOT EXISTS ${entry.key} (${entry.value})');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS catalog_sync (
      catalog TEXT PRIMARY KEY, version TEXT, cursor TEXT, synced_at TEXT
    )''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfNotExists(db, 'sales', 'sync_status', "TEXT DEFAULT 'pending'");
      await _addColumnIfNotExists(db, 'sales', 'payment_method', 'TEXT');
      await _addColumnIfNotExists(db, 'sales', 'cash_received', 'REAL DEFAULT 0');
      await _addColumnIfNotExists(db, 'sales', 'change_due', 'REAL DEFAULT 0');
      await _addColumnIfNotExists(db, 'sales', 'paid_at', 'TEXT');
    }
    if (oldVersion < 3) {
      await _addColumnIfNotExists(db, 'sales', 'mesa_id', 'INTEGER');
      await _addColumnIfNotExists(db, 'sales', 'mesa_nombre', 'TEXT');
    }
    if (oldVersion < 4) await _createCatalogTables(db);
    if (oldVersion < 5) {
      await _addColumnIfNotExists(db, 'products', 'data_json', 'TEXT');
      await _addColumnIfNotExists(db, 'products', 'updated_at', 'TEXT');
    }
    if (oldVersion < 6) await _createCompanyTable(db);
    if (oldVersion < 7) {
      final columns = <String, String>{
        'server_id': 'INTEGER', 'server_folio': 'TEXT', 'business_date': 'TEXT',
        'cliente_id': 'INTEGER', 'descuento_global': 'REAL DEFAULT 0',
        'impuesto_global': 'REAL DEFAULT 0', 'notas': 'TEXT',
        'sync_attempts': 'INTEGER DEFAULT 0', 'next_retry_at': 'TEXT',
        'last_sync_error': 'TEXT', 'server_synced_at': 'TEXT',
      };
      for (final e in columns.entries) {
        await _addColumnIfNotExists(db, 'sales', e.key, e.value);
      }
      await _addColumnIfNotExists(db, 'sale_items', 'descuento', 'REAL DEFAULT 0');
      await _addColumnIfNotExists(db, 'sale_payments', 'referencia', 'TEXT');
      await _addColumnIfNotExists(db, 'catalog_sync', 'cursor', 'TEXT');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_uuid_local ON sales(uuid_local)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_business_date ON sales(business_date)');
    }
  }

  Future<void> _addColumnIfNotExists(Database db, String table, String column, String definition) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((c) => c['name']?.toString() == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  double _toDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;

  int _toInt(dynamic value) => value is int
      ? value
      : value is num
          ? value.toInt()
          : int.tryParse((value ?? '').toString()) ?? 0;

  int? _nullableInt(dynamic value) {
    final n = _toInt(value);
    return n > 0 ? n : null;
  }

  String? _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString();
    }
    return null;
  }

  int _activeValue(Map<String, dynamic> data) {
    final value = data['is_active'] ?? data['activo'] ?? data['active'] ?? 1;
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value == 0 ? 0 : 1;
    final s = value.toString().trim().toLowerCase();
    return const {'false', '0', 'no', 'inactive', 'inactivo'}.contains(s) ? 0 : 1;
  }

  List<Map<String, dynamic>> _asList(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  // ---------------------------------------------------------------------------
  // COMPANY / CATALOGS
  // ---------------------------------------------------------------------------

  Future<void> upsertCompany(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) => _upsertCompanyWithExecutor(txn, data));
  }

  Future<void> _upsertCompanyWithExecutor(dynamic executor, Map<String, dynamic> data) async {
    final id = _toInt(data['id']);
    if (id <= 0) return;
    dynamic colors = data['colores'];
    dynamic config = data['configuracion'];
    final colorsJson = colors is String ? colors : colors == null ? null : jsonEncode(colors);
    final configJson = config is String ? config : config == null ? null : jsonEncode(config);
    await executor.insert('company', {
      'id': id, 'nombre': data['nombre']?.toString(), 'logo': data['logo']?.toString(),
      'logo_url': data['logo_url']?.toString(), 'colores_json': colorsJson,
      'configuracion_json': configJson, 'direccion': data['direccion']?.toString(),
      'telefono': data['telefono']?.toString(), 'email_contacto': data['email_contacto']?.toString(),
      'rfc': data['rfc']?.toString(), 'razon_social': data['razon_social']?.toString(),
      'leyenda_ticket': data['leyenda_ticket']?.toString(), 'whatsapp_numero': data['whatsapp_numero']?.toString(),
      'activo': _activeValue(data), 'updated_at': _stringValue(data, ['updated_at', 'updatedAt']) ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCompany() async {
    final db = await database;
    final rows = await db.query('company', limit: 1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row['colores'] = _decodeJson(row['colores_json']);
    row['configuracion'] = _decodeJson(row['configuracion_json']);
    return row;
  }

  dynamic _decodeJson(dynamic value) {
    if (value == null) return {};
    try { return jsonDecode(value.toString()); } catch (_) { return {}; }
  }

  Future<List<Map<String, dynamic>>> getProducts() async => (await database).query('products', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllProducts() async => (await database).query('products', orderBy: 'name ASC');
  Future<Map<String, dynamic>?> getProductById(int id) async {
    final rows = await (await database).query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
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
}) async =>
    (await database).insert(
      'products',
      {
        if (id != null) 'id': id,
        'code': code,
        'name': name,
        'price': price,
        'stock': stock,
        'is_active': isActive ? 1 : 0,
        'data_json': data == null ? null : jsonEncode(data),
        'updated_at':
            updatedAt ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

Future<int> updateProduct({
  required int id,
  required String code,
  required String name,
  required double price,
  required double stock,
  bool isActive = true,
  Map<String, dynamic>? data,
  String? updatedAt,
}) async =>
    (await database).update(
      'products',
      {
        'code': code,
        'name': name,
        'price': price,
        'stock': stock,
        'is_active': isActive ? 1 : 0,
        if (data != null) 'data_json': jsonEncode(data),
        'updated_at':
            updatedAt ?? DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  Future<int> deleteProduct(int id) async => (await database).update('products', {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  Future<void> _upsertClientWithExecutor(dynamic executor, Map<String, dynamic> data) async {
    final id = _toInt(data['id']); if (id <= 0) return;
    await executor.insert('clients', {'id': id, 'name': _stringValue(data, ['name', 'nombre']), 'email': _stringValue(data, ['email', 'correo']), 'phone': _stringValue(data, ['phone', 'telefono', 'teléfono']), 'rfc': _stringValue(data, ['rfc']), 'is_active': _activeValue(data), 'data_json': jsonEncode(data), 'updated_at': _stringValue(data, ['updated_at', 'updatedAt']) ?? DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertCatalogWithExecutor(dynamic executor, {required String table, required Map<String, dynamic> data, bool includeRate = false}) async {
    final id = _toInt(data['id']); if (id <= 0) return;
    final values = <String, dynamic>{'id': id, 'name': _stringValue(data, ['name', 'nombre', 'descripcion', 'description']), 'code': _stringValue(data, ['code', 'codigo', 'clave', 'clave_sat', 'abreviatura']), 'is_active': _activeValue(data), 'data_json': jsonEncode(data), 'updated_at': _stringValue(data, ['updated_at', 'updatedAt']) ?? DateTime.now().toIso8601String()};
    if (includeRate) values['rate'] = _toDouble(data['rate'] ?? data['tasa'] ?? data['porcentaje'] ?? data['valor']);
    await executor.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertClient(Map<String, dynamic> data) async => _upsertClientWithExecutor(await database, data);
  Future<void> upsertTax(Map<String, dynamic> data) async => _upsertCatalogItem('taxes', data, includeRate: true);
  Future<void> upsertPaymentMethod(Map<String, dynamic> data) async => _upsertCatalogItem('payment_methods', data);
  Future<void> upsertUnit(Map<String, dynamic> data) async => _upsertCatalogItem('units', data);
  Future<void> upsertCategory(Map<String, dynamic> data) async => _upsertCatalogItem('categories', data);
  Future<void> upsertPromotion(Map<String, dynamic> data) async => _upsertCatalogItem('promotions', data);
  Future<void> upsertCoupon(Map<String, dynamic> data) async => _upsertCatalogItem('coupons', data);
  Future<void> _upsertCatalogItem(String table, Map<String, dynamic> data, {bool includeRate = false}) async => _upsertCatalogWithExecutor(await database, table: table, data: data, includeRate: includeRate);

  Future<List<Map<String, dynamic>>> getClients() async => (await database).query('clients', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllClients() async => (await database).query('clients', orderBy: 'name ASC');
  Future<Map<String, dynamic>?> getClientById(int id) async { final r = await (await database).query('clients', where: 'id = ?', whereArgs: [id], limit: 1); return r.isEmpty ? null : r.first; }
  Future<List<Map<String, dynamic>>> getTaxes() async => (await database).query('taxes', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllTaxes() async => (await database).query('taxes', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getPaymentMethods() async => (await database).query('payment_methods', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllPaymentMethods() async => (await database).query('payment_methods', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getUnits() async => (await database).query('units', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllUnits() async => (await database).query('units', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getCategories() async => (await database).query('categories', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllCategories() async => (await database).query('categories', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getPromotions() async => (await database).query('promotions', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllPromotions() async => (await database).query('promotions', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getCoupons() async => (await database).query('coupons', where: 'is_active = 1', orderBy: 'name ASC');
  Future<List<Map<String, dynamic>>> getAllCoupons() async => (await database).query('coupons', orderBy: 'name ASC');

  Future<List<Map<String, dynamic>>> getCatalogItems(String table, {bool activeOnly = true}) async {
    _validateCatalogTable(table);
    final rows = await (await database).query(table, where: activeOnly ? 'is_active = 1' : null, orderBy: 'name ASC');
    return rows.map((row) => {...row, 'id': _toInt(row['id']), 'is_active': _toInt(row['is_active']), if (table == 'taxes') 'rate': _toDouble(row['rate'])}).toList();
  }

  static const _catalogTables = {'taxes', 'payment_methods', 'units', 'categories', 'promotions', 'coupons'};
  void _validateCatalogTable(String table) { if (!_catalogTables.contains(table)) throw ArgumentError('Catálogo no permitido: $table'); }
  Future<int> createCatalogItem({required String table, required String name, String? code, double? rate, bool isActive = true, Map<String, dynamic>? data}) async { _validateCatalogTable(table); return (await database).insert(table, {'name': name.trim(), 'code': code?.trim(), if (table == 'taxes') 'rate': rate ?? 0, 'is_active': isActive ? 1 : 0, 'data_json': data == null ? null : jsonEncode(data), 'updated_at': DateTime.now().toIso8601String()}); }

  // ═══════════════════════════════════════════════════════════════════════════
  // ✅ MÉTODO CORREGIDO: ahora acepta 'active' en lugar de 'isActive'
  // ═══════════════════════════════════════════════════════════════════════════
  Future<int> updateCatalogItem({
    required String table,
    required int id,
    required String name,
    String? code,
    double? rate,
    bool active = true,     // <-- Cambiado de isActive a active
    Map<String, dynamic>? data,
  }) async {
    _validateCatalogTable(table);
    return (await database).update(
      table,
      {
        'name': name.trim(),
        'code': code?.trim(),
        if (table == 'taxes') 'rate': rate ?? 0,
        'is_active': active ? 1 : 0,  // <-- Mapeo a is_active
        if (data != null) 'data_json': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCatalogItem(String table, int id) async { _validateCatalogTable(table); return (await database).update(table, {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]); }
  Future<int> restoreCatalogItem({required String table, required int id}) async { _validateCatalogTable(table); return (await database).update(table, {'is_active': 1, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]); }
  Future<int> createClient({required String name, String? email, String? phone, String? rfc, bool isActive = true}) async => (await database).insert('clients', {'name': name.trim(), 'email': email?.trim(), 'phone': phone?.trim(), 'rfc': rfc?.trim(), 'is_active': isActive ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()});
  Future<int> updateClient({required int id, required String name, String? email, String? phone, String? rfc, bool isActive = true}) async => (await database).update('clients', {'name': name.trim(), 'email': email?.trim(), 'phone': phone?.trim(), 'rfc': rfc?.trim(), 'is_active': isActive ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  Future<int> deleteClient(int id) async => (await database).update('clients', {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  Future<void> syncCatalogs(Map<String, dynamic> response) async {
    final data = response['data'] is Map ? Map<String, dynamic>.from(response['data']) : response;
    final db = await database;
    await db.transaction((txn) async {
      if (data['empresa'] is Map) await _upsertCompanyWithExecutor(txn, Map<String, dynamic>.from(data['empresa']));
      for (final p in _asList(data['productos'])) await _upsertProductWithExecutor(txn, p);
      for (final c in _asList(data['clientes'])) await _upsertClientWithExecutor(txn, c);
      for (final x in _asList(data['impuestos'])) await _upsertCatalogWithExecutor(txn, table: 'taxes', data: x, includeRate: true);
      for (final x in _asList(data['formas_pago'])) await _upsertCatalogWithExecutor(txn, table: 'payment_methods', data: x);
      for (final x in _asList(data['unidades_medida'])) await _upsertCatalogWithExecutor(txn, table: 'units', data: x);
      for (final x in _asList(data['categorias'])) await _upsertCatalogWithExecutor(txn, table: 'categories', data: x);
      for (final x in _asList(data['promociones'])) await _upsertCatalogWithExecutor(txn, table: 'promotions', data: x);
      for (final x in _asList(data['cupones'])) await _upsertCatalogWithExecutor(txn, table: 'coupons', data: x);
      if (data['versiones'] is Map) for (final e in (data['versiones'] as Map).entries) await txn.insert('catalog_sync', {'catalog': e.key.toString(), 'version': e.value?.toString(), 'synced_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await _processTombstones(data['tombstones']);
  }

  Future<void> _upsertProductWithExecutor(
  dynamic executor,
  Map<String, dynamic> data,
  ) async {
    final id = _toInt(data['id']);
    if (id <= 0) return;
    await executor.insert(
      'products',
      {
        'id': id,
        'code': _stringValue(data, ['code', 'codigo', 'sku']) ?? '',
        'name': _stringValue(data, ['name', 'nombre']) ?? '',
        'price': _toDouble(data['price'] ?? data['precio'] ?? data['precio_venta']),
        'stock': _toDouble(data['stock'] ?? data['existencia'] ?? data['cantidad']),
        'is_active': _activeValue(data),
        'data_json': jsonEncode(data),
        'updated_at': _stringValue(data, ['updated_at', 'updatedAt']) ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  Future<void> upsertProductFromApi(Map<String, dynamic> data) async => _upsertProductWithExecutor(await database, data);

  Future<void> _processTombstones(dynamic data) async {
    if (data is! Map) return;
    final db = await database;
    const map = {'productos': 'products', 'clientes': 'clients', 'impuestos': 'taxes', 'formas_pago': 'payment_methods', 'unidades_medida': 'units', 'categorias': 'categories', 'promociones': 'promotions', 'cupones': 'coupons'};
    await db.transaction((txn) async {
      for (final entry in map.entries) {
        final values = data[entry.key];
        if (values is! List) continue;
        for (final value in values) {
          final id = _toInt(value is Map ? value['id'] : value);
          if (id > 0) await txn.delete(entry.value, where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  Future<String?> getCatalogVersion(String catalog) async { final r = await (await database).query('catalog_sync', where: 'catalog = ?', whereArgs: [catalog], limit: 1); return r.isEmpty ? null : r.first['version']?.toString(); }
  Future<String?> getCatalogCursor(String catalog) async { final r = await (await database).query('catalog_sync', where: 'catalog = ?', whereArgs: [catalog], limit: 1); return r.isEmpty ? null : r.first['cursor']?.toString(); }
  Future<void> setCatalogVersion(String catalog, String? version, {String? cursor}) async => (await database).insert('catalog_sync', {'catalog': catalog, 'version': version, 'cursor': cursor, 'synced_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<Map<String, String?>> getCatalogVersions() async { final rows = await (await database).query('catalog_sync'); return {for (final r in rows) r['catalog'].toString(): r['version']?.toString()}; }

  // ---------------------------------------------------------------------------
  // SALES / HISTORICAL QUEUE
  // ---------------------------------------------------------------------------

  Future<int> saveSale({required String uuid, required List<Map<String, dynamic>> items, required List<Map<String, dynamic>> payments, required double total, required String status, String syncStatus = 'pending', String? paymentMethod, double cashReceived = 0, double changeDue = 0, int? tableId, String? tableName, int? clienteId, double descuentoGlobal = 0, double impuestoGlobal = 0, String? notas, String? businessDate}) async {
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

  Future<List<Map<String, dynamic>>> getTodaySales() async {
    final db = await database;
    final now = DateTime.now();
    final todayYear = now.year;
    final todayMonth = now.month;
    final todayDay = now.day;

    final rows = await db.query(
      'sales',
      orderBy: 'created_at DESC',
    );

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
  Future<List<Map<String, dynamic>>> getSales({String? businessDate, String? syncStatus, int? limit}) async { final db = await database; final where = <String>[]; final args = <dynamic>[]; if (businessDate != null) { where.add('business_date = ?'); args.add(businessDate); } if (syncStatus != null) { where.add('sync_status = ?'); args.add(syncStatus); } return db.query('sales', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'created_at ASC', limit: limit); }
  Future<List<Map<String, dynamic>>> getPendingSales({bool includeFailed = true}) async => getSales(syncStatus: includeFailed ? null : 'pending').then((rows) => rows.where((r) => r['sync_status'] == 'pending' || r['sync_status'] == 'failed').toList());
  Future<Map<String, dynamic>?> getSaleById(int id) async { final r = await (await database).query('sales', where: 'id = ?', whereArgs: [id], limit: 1); return r.isEmpty ? null : r.first; }
  Future<List<Map<String, dynamic>>> getSaleItemsBySaleId(int id) async => (await database).query('sale_items', where: 'sale_id = ?', whereArgs: [id]);
  Future<List<Map<String, dynamic>>> getSalePaymentsBySaleId(int id) async => (await database).query('sale_payments', where: 'sale_id = ?', whereArgs: [id]);

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
    if (updated > 0) notifySalesChanged();
  }

  Future<void> markSaleAsSynced(
    int saleId, {
    Map<String, dynamic>? serverResponse,
  }) async {
    final r = serverResponse ?? const <String, dynamic>{};
    final nested = r['data'] is Map
        ? Map<String, dynamic>.from(r['data'])
        : r;

    final updated = await (await database).update(
      'sales',
      {
        'sync_status': 'synced',
        'server_id': _nullableInt(
          nested['server_id'] ?? nested['venta_id'] ?? nested['id'],
        ),
        'server_folio': nested['folio']?.toString() ??
            nested['server_folio']?.toString(),
        'server_synced_at': DateTime.now().toIso8601String(),
        'last_sync_error': null,
        'next_retry_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (updated > 0) notifySalesChanged();
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

    if (updated > 0) notifySalesChanged();
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
    if (updated > 0) notifySalesChanged();
  }
  Future<void> updateSaleServerResult(int saleId, Map<String, dynamic> response) async => markSaleAsSynced(saleId, serverResponse: response);
  Future<List<Map<String, dynamic>>> getPendingSalesReadyToSync({int? limit}) async { final db = await database; final now = DateTime.now().toIso8601String(); return db.query('sales', where: "sync_status IN ('pending','failed') AND (next_retry_at IS NULL OR next_retry_at <= ?)", whereArgs: [now], orderBy: 'business_date ASC, created_at ASC', limit: limit); }

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
    if (updated > 0) notifySalesChanged();
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
    if (updated > 0) notifySalesChanged();
  }

  Future<bool> cancelSale(int saleId) async {
    final db = await database;

    final cancelled = await db.transaction((txn) async {
      final r = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );

      if (r.isEmpty || r.first['status'] == 'cancelled') {
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
      final r = await txn.query(
        'sales',
        where: 'id = ? AND status = ?',
        whereArgs: [saleId, 'pending'],
        limit: 1,
      );

      if (r.isEmpty) return false;

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
      final n = await txn.update(
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

      if (n != 1) return false;

      await txn.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

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
      final r = await txn.query(
        'sales',
        where: 'id = ? AND status = ?',
        whereArgs: [saleId, 'pending'],
        limit: 1,
      );

      if (r.isEmpty) return false;

      await txn.delete(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      for (final p in payments) {
        await txn.insert('sale_payments', {
          'sale_id': saleId,
          'method': p['method'],
          'amount': _toDouble(p['amount']),
          'referencia': p['referencia'],
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
  /// Si ya existe por uuid, no duplica.
  Future<int> archiveDailySale({required Map<String, dynamic> sale, required List<Map<String, dynamic>> items, required List<Map<String, dynamic>> payments}) async {
    return saveSale(uuid: sale['uuid_local']?.toString() ?? '', items: items, payments: payments, total: _toDouble(sale['total']), status: sale['status']?.toString() ?? 'paid', syncStatus: sale['sync_status']?.toString() ?? 'pending', paymentMethod: sale['payment_method']?.toString(), cashReceived: _toDouble(sale['cash_received']), changeDue: _toDouble(sale['change_due']), tableId: _nullableInt(sale['mesa_id']), tableName: sale['mesa_nombre']?.toString(), clienteId: _nullableInt(sale['cliente_id']), descuentoGlobal: _toDouble(sale['descuento_global']), impuestoGlobal: _toDouble(sale['impuesto_global']), notas: sale['notas']?.toString(), businessDate: sale['business_date']?.toString() ?? sale['created_at']?.toString().substring(0, 10));
  }

  Future<bool> hasPendingSales() async => (await getPendingSales()).isNotEmpty;
  Future<Map<String, int>> getSyncSummary() async { final rows = await (await database).rawQuery("SELECT sync_status, COUNT(*) total FROM sales GROUP BY sync_status"); return {for (final r in rows) r['sync_status'].toString(): _toInt(r['total'])}; }

  Future<Map<String, dynamic>?> getSyncStatus(int saleId) async { final sale = await getSaleById(saleId); if (sale == null) return null; return {'sync_status': sale['sync_status'], 'server_id': sale['server_id'], 'server_folio': sale['server_folio'], 'server_synced_at': sale['server_synced_at'], 'last_sync_error': sale['last_sync_error'], 'business_date': sale['business_date'], 'sync_attempts': _toInt(sale['sync_attempts'])}; }



  Future<Map<String, int>> getCatalogCounts() async { final db = await database; Future<int> c(String t) async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0; return {'productos': await c('products'), 'clientes': await c('clients'), 'impuestos': await c('taxes'), 'formas_pago': await c('payment_methods'), 'unidades_medida': await c('units'), 'categorias': await c('categories'), 'promociones': await c('promotions'), 'cupones': await c('coupons')}; }

  Future<void> clearDb() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in [
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
        await txn.delete(t);
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
  }
}
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/local_db.dart';

// ============================================================
// RESULTADO DE IMPORTACIÓN
// ============================================================

class ExcelImportRowError {
  const ExcelImportRowError({
    required this.rowNumber,
    required this.field,
    required this.message,
    this.rawRow,
  });

  final int rowNumber;
  final String field;
  final String message;
  final Map<String, dynamic>? rawRow;

  Map<String, dynamic> toMap() => {
    'row_number': rowNumber,
    'field': field,
    'message': message,
    'raw_row': rawRow,
  };
}

class ExcelImportResult {
  const ExcelImportResult({
    required this.totalRows,
    required this.inserted,
    required this.updated,
    required this.errors,
  });

  final int totalRows;
  final int inserted;
  final int updated;
  final List<ExcelImportRowError> errors;

  bool get hasErrors => errors.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'total_rows': totalRows,
    'inserted': inserted,
    'updated': updated,
    'errors': errors.map((e) => e.toMap()).toList(),
  };
}

// ============================================================
// SERVICIO
// ============================================================

class CatalogExcelService {
  final LocalDb _db = LocalDb();

  /// Umbral mínimo de similitud para considerar "mismo producto".
  /// 0.85 = 85% de similitud Levenshtein.
  static const double _similarityThreshold = 0.85;

  /// Mínimo de caracteres para permitir match por prefijo.
  static const int _minPrefixLength = 3;

  // ============================================================
  // DEFINICIÓN DE PLANTILLAS
  // ============================================================

  List<String> _headersFor(String table) {
    switch (table) {
      case 'products':
        return const [
          'nombre',
          'precio',
          'stock',
          'maneja_inventario',
          'categoria_nombre',
          'descripcion',
        ];
      case 'categories':
        return const ['nombre', 'activo'];
      case 'payment_methods':
        return const ['nombre', 'activo'];
      default:
        return const ['nombre'];
    }
  }

  String _catalogLabel(String table) {
    switch (table) {
      case 'products':
        return 'productos';
      case 'categories':
        return 'categorias';
      case 'payment_methods':
        return 'formas_pago';
      default:
        return table;
    }
  }

  List<String> _sampleRowFor(String table) {
    switch (table) {
      case 'products':
        return const [
          'Café Americano',
          '45.00',
          '100',
          'SI',
          'Bebidas',
          'Café negro 12oz',
        ];
      case 'categories':
        return const ['Bebidas', 'SI'];
      case 'payment_methods':
        return const ['Efectivo', 'SI'];
      default:
        return const ['Ejemplo'];
    }
  }

  // ============================================================
  // DESCARGA DE PLANTILLA
  // ============================================================

  Future<String> downloadTemplate(String table) async {
    final excel = Excel.createExcel();

    final sheetName = _catalogLabel(table);
    final sheet = excel[sheetName];

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = _headersFor(table);

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#E8F5E9'),
      );
    }

    final sample = _sampleRowFor(table);

    for (var i = 0; i < sample.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
          .value = TextCellValue(
        sample[i],
      );
    }

    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 22);
    }

    final bytes = excel.encode();

    if (bytes == null) {
      throw Exception('No se pudo generar el archivo Excel.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'plantilla_${_catalogLabel(table)}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File('${dir.path}/$fileName');

    await file.writeAsBytes(bytes, flush: true);

    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Plantilla ${_catalogLabel(table)}',
        text: 'Plantilla para carga masiva de ${_catalogLabel(table)}.',
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo abrir el share sheet: $e');
    }

    return file.path;
  }

  // ============================================================
  // IMPORTACIÓN
  // ============================================================

  Future<ExcelImportResult?> pickAndImport(String table) async {
    // file_picker 13.x: withData ya no existe.
    // pickFiles() devuelve List<PlatformFile>.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (files.isEmpty) {
      return null;
    }

    final picked = files.first;

    // Leer bytes explícitamente desde el PlatformFile.
    final bytes = await picked.readAsBytes();

    if (bytes == null || bytes.isEmpty) {
      throw Exception('No se pudo leer el archivo seleccionado.');
    }

    return importFromBytes(table: table, bytes: bytes);
  }

  Future<ExcelImportResult> importFromBytes({
    required String table,
    required Uint8List bytes,
  }) async {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('El archivo Excel está vacío.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    if (sheet.rows.isEmpty) {
      throw Exception('La hoja "$sheetName" está vacía.');
    }

    // ==========================================================
    // VALIDAR ENCABEZADOS
    // ==========================================================

    final headerRow = sheet.rows.first;

    final actualHeaders = headerRow
        .map((cell) => _cellToString(cell)?.trim().toLowerCase() ?? '')
        .where((h) => h.isNotEmpty)
        .toList();

    final expectedHeaders = _headersFor(table);

    final missingHeaders = expectedHeaders
        .where((h) => !actualHeaders.contains(h.toLowerCase()))
        .toList();

    if (missingHeaders.isNotEmpty) {
      throw Exception(
        'El Excel no contiene las columnas requeridas: '
        '${missingHeaders.join(', ')}',
      );
    }

    // ==========================================================
    // MAPEAR HEADERS A ÍNDICES
    // ==========================================================

    final headerIndex = <String, int>{};

    for (var i = 0; i < headerRow.length; i++) {
      final header = _cellToString(headerRow[i])?.trim().toLowerCase();

      if (header != null && header.isNotEmpty) {
        headerIndex[header] = i;
      }
    }

    // ==========================================================
    // PROCESAR FILAS
    // ==========================================================

    final errors = <ExcelImportRowError>[];

    // Cache de categorías por nombre normalizado.
    final Map<String, int> categoryIdByName = {};

    if (table == 'products') {
      final categories = await _db.getCategories();

      for (final c in categories) {
        final name = (c['name'] ?? c['nombre'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        final id = _toInt(c['id']);

        if (name.isNotEmpty && id > 0) {
          categoryIdByName[name] = id;
        }
      }
    }

    final Set<String> seenNamesInSheet = {};

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];

      if (row.every((cell) => _cellToString(cell)?.trim().isEmpty ?? true)) {
        continue;
      }

      final rowNumber = rowIndex;

      final rowData = <String, dynamic>{};

      for (final entry in headerIndex.entries) {
        final col = entry.value;
        final value = col < row.length ? _cellToString(row[col]) : null;
        rowData[entry.key] = value?.trim() ?? '';
      }

      if (table == 'products') {
        _validateProductRow(
          rowData: rowData,
          rowNumber: rowNumber,
          errors: errors,
          categoryIdByName: categoryIdByName,
          seenNames: seenNamesInSheet,
        );
      } else {
        _validateSimpleRow(
          rowData: rowData,
          rowNumber: rowNumber,
          errors: errors,
          seenNames: seenNamesInSheet,
        );
      }
    }

    // Si hay errores, NO insertamos nada.
    if (errors.isNotEmpty) {
      return ExcelImportResult(
        totalRows: sheet.rows.length - 1,
        inserted: 0,
        updated: 0,
        errors: errors,
      );
    }

    // ==========================================================
    // INSERTAR / ACTUALIZAR
    // ==========================================================
    //
    // Construimos el "contexto" de nombres existentes en la BD
    // para hacer match por similitud.
    //
    // Clave: nombre normalizado → id local.
    //

    final Map<String, int> existingByName = {};

    if (table == 'products') {
      final products = await _db.getAllProducts();

      for (final p in products) {
        final name = (p['name'] ?? p['nombre'] ?? '').toString().trim();

        final id = _toInt(p['id']);

        if (name.isNotEmpty && id > 0) {
          existingByName[normalizeName(name)] = id;
        }
      }
    } else if (table == 'categories') {
      final categories = await _db.getAllCategories();

      for (final c in categories) {
        final name = (c['name'] ?? c['nombre'] ?? '').toString().trim();
        final id = _toInt(c['id']);
        if (name.isNotEmpty && id > 0) {
          existingByName[normalizeName(name)] = id;
        }
      }
    } else if (table == 'payment_methods') {
      final items = await _db.getCatalogItems(
        'payment_methods',
        activeOnly: false,
      );

      for (final c in items) {
        final name = (c['name'] ?? c['nombre'] ?? '').toString().trim();
        final id = _toInt(c['id']);
        if (name.isNotEmpty && id > 0) {
          existingByName[normalizeName(name)] = id;
        }
      }
    }

    var inserted = 0;
    var updated = 0;

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];

      if (row.every((cell) => _cellToString(cell)?.trim().isEmpty ?? true)) {
        continue;
      }

      final rowData = <String, dynamic>{};

      for (final entry in headerIndex.entries) {
        final col = entry.value;
        final value = col < row.length ? _cellToString(row[col]) : null;
        rowData[entry.key] = value?.trim() ?? '';
      }

      try {
        if (table == 'products') {
          final r = await _upsertProduct(rowData, existingByName);
          if (r == 'inserted') inserted++;
          if (r == 'updated') updated++;
        } else if (table == 'categories') {
          final r = await _upsertCategory(rowData, existingByName);
          if (r == 'inserted') inserted++;
          if (r == 'updated') updated++;
        } else if (table == 'payment_methods') {
          final r = await _upsertPaymentMethod(rowData, existingByName);
          if (r == 'inserted') inserted++;
          if (r == 'updated') updated++;
        }
      } catch (e) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowIndex,
            field: '',
            message: 'No se pudo guardar la fila: $e',
            rawRow: rowData,
          ),
        );
      }
    }

    return ExcelImportResult(
      totalRows: sheet.rows.length - 1,
      inserted: inserted,
      updated: updated,
      errors: errors,
    );
  }

  // ============================================================
  // VALIDACIÓN PRODUCTOS
  // ============================================================

  void _validateProductRow({
    required Map<String, dynamic> rowData,
    required int rowNumber,
    required List<ExcelImportRowError> errors,
    required Map<String, int> categoryIdByName,
    required Set<String> seenNames,
  }) {
    final name = (rowData['nombre'] ?? '').toString().trim();

    if (name.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'nombre',
          message: 'El nombre es obligatorio.',
          rawRow: rowData,
        ),
      );
    } else {
      final key = normalizeName(name);

      if (seenNames.contains(key)) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowNumber,
            field: 'nombre',
            message: 'El nombre "$name" está duplicado en el Excel.',
            rawRow: rowData,
          ),
        );
      } else {
        seenNames.add(key);
      }
    }

    final precioRaw = (rowData['precio'] ?? '').toString().trim();

    if (precioRaw.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'precio',
          message: 'El precio es obligatorio.',
          rawRow: rowData,
        ),
      );
    } else {
      final precio = double.tryParse(precioRaw.replaceAll(',', '.'));

      if (precio == null) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowNumber,
            field: 'precio',
            message: 'El precio debe ser numérico.',
            rawRow: rowData,
          ),
        );
      } else if (precio < 0) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowNumber,
            field: 'precio',
            message: 'El precio no puede ser negativo.',
            rawRow: rowData,
          ),
        );
      }
    }

    final inventarioRaw = (rowData['maneja_inventario'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    if (inventarioRaw.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'maneja_inventario',
          message: 'Debe indicar SI o NO.',
          rawRow: rowData,
        ),
      );
    } else if (inventarioRaw != 'SI' && inventarioRaw != 'NO') {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'maneja_inventario',
          message: 'Debe ser SI o NO.',
          rawRow: rowData,
        ),
      );
    }

    if (inventarioRaw == 'SI') {
      final stockRaw = (rowData['stock'] ?? '').toString().trim();

      if (stockRaw.isEmpty) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowNumber,
            field: 'stock',
            message: 'Si maneja inventario, el stock es obligatorio.',
            rawRow: rowData,
          ),
        );
      } else {
        final stock = double.tryParse(stockRaw.replaceAll(',', '.'));

        if (stock == null) {
          errors.add(
            ExcelImportRowError(
              rowNumber: rowNumber,
              field: 'stock',
              message: 'El stock debe ser numérico.',
              rawRow: rowData,
            ),
          );
        } else if (stock < 0) {
          errors.add(
            ExcelImportRowError(
              rowNumber: rowNumber,
              field: 'stock',
              message: 'El stock no puede ser negativo.',
              rawRow: rowData,
            ),
          );
        }
      }
    }

    final categoryName = (rowData['categoria_nombre'] ?? '').toString().trim();

    if (categoryName.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'categoria_nombre',
          message: 'La categoría es obligatoria.',
          rawRow: rowData,
        ),
      );
    } else if (!categoryIdByName.containsKey(categoryName.toLowerCase())) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'categoria_nombre',
          message: 'La categoría "$categoryName" no existe.',
          rawRow: rowData,
        ),
      );
    }
  }

  // ============================================================
  // VALIDACIÓN CATEGORÍAS / FORMAS DE PAGO
  // ============================================================

  void _validateSimpleRow({
    required Map<String, dynamic> rowData,
    required int rowNumber,
    required List<ExcelImportRowError> errors,
    required Set<String> seenNames,
  }) {
    final name = (rowData['nombre'] ?? '').toString().trim();

    if (name.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'nombre',
          message: 'El nombre es obligatorio.',
          rawRow: rowData,
        ),
      );
    } else {
      final key = normalizeName(name);

      if (seenNames.contains(key)) {
        errors.add(
          ExcelImportRowError(
            rowNumber: rowNumber,
            field: 'nombre',
            message: 'El nombre "$name" está duplicado en el Excel.',
            rawRow: rowData,
          ),
        );
      } else {
        seenNames.add(key);
      }
    }

    final activoRaw = (rowData['activo'] ?? '').toString().trim().toUpperCase();

    if (activoRaw.isEmpty) {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'activo',
          message: 'Debe indicar SI o NO.',
          rawRow: rowData,
        ),
      );
    } else if (activoRaw != 'SI' && activoRaw != 'NO') {
      errors.add(
        ExcelImportRowError(
          rowNumber: rowNumber,
          field: 'activo',
          message: 'Debe ser SI o NO.',
          rawRow: rowData,
        ),
      );
    }
  }

  // ============================================================
  // UPSERT PRODUCTO
  // ============================================================

  Future<String> _upsertProduct(
    Map<String, dynamic> rowData,
    Map<String, int> existingByName,
  ) async {
    // Los textos se guardan en MAYÚSCULAS.
    final name = (rowData['nombre'] ?? '').toString().trim().toUpperCase();

    final price = _toDouble(rowData['precio']);

    final manejaInventario =
        (rowData['maneja_inventario'] ?? '').toString().trim().toUpperCase() ==
        'SI';

    final stock = manejaInventario ? _toDouble(rowData['stock']) : 0.0;

    final categoryName = (rowData['categoria_nombre'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    final description = (rowData['descripcion'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    final categories = await _db.getCategories();

    int? categoryId;

    for (final c in categories) {
      final n = (c['name'] ?? c['nombre'] ?? '').toString().trim();

      if (n.toLowerCase() == categoryName.toLowerCase()) {
        categoryId = _toInt(c['id']);
        break;
      }
    }

    if (categoryId == null || categoryId <= 0) {
      throw Exception('La categoría "$categoryName" no existe.');
    }

    // ==========================================================
    // BUSCAR MATCH POR SIMILITUD
    // ==========================================================

    final existingId = findBestMatch(name, existingByName.keys.toList());

    if (existingId != null && existingByName.containsKey(existingId)) {
      final localId = existingByName[existingId]!;

      final existing = await _db.getProductById(localId);

      final data = <String, dynamic>{
        if (existing?['data_json'] is String)
          ...((jsonDecodeSafe(existing!['data_json']) ?? {})
              as Map<String, dynamic>),
        'categoria_id': categoryId,
        if (description.isNotEmpty) 'descripcion': description,
      };

      await _db.updateProduct(
        id: localId,
        code: (existing?['code'] ?? '').toString(),
        name: name,
        price: price,
        stock: stock,
        isActive: true,
        isInventoriable: manejaInventario,
        categoryId: categoryId,
        data: data,
      );

      LocalDb.notifySalesChanged();

      return 'updated';
    }

    // ==========================================================
    // INSERTAR NUEVO
    // ==========================================================

    final code = await _generateProductCode(categoryId);

    final data = <String, dynamic>{
      'categoria_id': categoryId,
      if (description.isNotEmpty) 'descripcion': description,
    };

    await _db.createProduct(
      categoryId: categoryId,
      code: code,
      name: name,
      price: price,
      stock: stock,
      isActive: true,
      isInventoriable: manejaInventario,
      data: data,
    );

    LocalDb.notifySalesChanged();

    return 'inserted';
  }

  // ============================================================
  // UPSERT CATEGORÍA
  // ============================================================

  Future<String> _upsertCategory(
    Map<String, dynamic> rowData,
    Map<String, int> existingByName,
  ) async {
    // Los textos se guardan en MAYÚSCULAS.
    final name = (rowData['nombre'] ?? '').toString().trim().toUpperCase();

    final active =
        (rowData['activo'] ?? '').toString().trim().toUpperCase() == 'SI';

    final existingId = findBestMatch(name, existingByName.keys.toList());

    if (existingId != null && existingByName.containsKey(existingId)) {
      final localId = existingByName[existingId]!;

      final existing = await _db.getAllCategories().then(
        (list) => list.firstWhere(
          (c) => _toInt(c['id']) == localId,
          orElse: () => <String, dynamic>{},
        ),
      );

      await _db.updateCatalogItem(
        table: 'categories',
        id: localId,
        name: name,
        code: (existing['code'] ?? '').toString(),
        active: active,
      );

      LocalDb.notifySalesChanged();

      return 'updated';
    }

    final code = await _db.getNextCategoryCode(name);

    await _db.createCatalogItem(
      table: 'categories',
      name: name,
      code: code,
      isActive: active,
    );

    LocalDb.notifySalesChanged();

    return 'inserted';
  }

  // ============================================================
  // UPSERT FORMA DE PAGO
  // ============================================================

  Future<String> _upsertPaymentMethod(
    Map<String, dynamic> rowData,
    Map<String, int> existingByName,
  ) async {
    // Los textos se guardan en MAYÚSCULAS.
    final name = (rowData['nombre'] ?? '').toString().trim().toUpperCase();

    final active =
        (rowData['activo'] ?? '').toString().trim().toUpperCase() == 'SI';

    final existingId = findBestMatch(name, existingByName.keys.toList());

    if (existingId != null && existingByName.containsKey(existingId)) {
      final localId = existingByName[existingId]!;

      await _db.updateCatalogItem(
        table: 'payment_methods',
        id: localId,
        name: name,
        active: active,
      );

      LocalDb.notifySalesChanged();

      return 'updated';
    }

    await _db.createCatalogItem(
      table: 'payment_methods',
      name: name,
      isActive: active,
    );

    LocalDb.notifySalesChanged();

    return 'inserted';
  }

  // ============================================================
  // MATCH POR SIMILITUD
  // ============================================================

  /// Normaliza un nombre para comparación:
  ///   - lowercase
  ///   - sin acentos
  ///   - sin signos raros
  ///   - sin espacios dobles ni extremos
  static String normalizeName(String value) {
    var v = value.trim().toLowerCase();

    v = v
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');

    v = v.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    v = v.replaceAll(RegExp(r'\s+'), ' ').trim();

    return v;
  }

  /// Devuelve la clave existente que mejor matchea con `input`,
  /// o `null` si ninguna supera el umbral.
  ///
  /// Orden de prioridad:
  ///   1. Igualdad exacta (post-normalización).
  ///   2. Prefijo (uno es prefijo del otro, ≥ 3 chars).
  ///   3. Levenshtein normalizado ≥ 0.85.
  static String? findBestMatch(String input, List<String> candidates) {
    if (input.trim().isEmpty || candidates.isEmpty) return null;

    final needle = normalizeName(input);
    if (needle.isEmpty) return null;

    // 1. Exacto.
    for (final c in candidates) {
      final h = normalizeName(c);
      if (h == needle) return c;
    }

    // 2. Prefijo.
    for (final c in candidates) {
      final h = normalizeName(c);

      if (h.length >= _minPrefixLength && needle.length >= _minPrefixLength) {
        if (h.startsWith(needle) || needle.startsWith(h)) {
          return c;
        }
      }
    }

    // 3. Levenshtein.
    String? best;
    double bestScore = 0;

    for (final c in candidates) {
      final h = normalizeName(c);
      final score = similarity(needle, h);

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    if (best != null && bestScore >= _similarityThreshold) {
      return best;
    }

    return null;
  }

  /// Similitud Levenshtein normalizada (0..1).
  static double similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;

    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;

    if (m == 0) return n;
    if (n == 0) return m;

    final prev = List<int>.generate(n + 1, (i) => i);
    final curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;

      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;

        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce(min);
      }

      for (var k = 0; k <= n; k++) {
        prev[k] = curr[k];
      }
    }

    return prev[n];
  }

  // ============================================================
  // GENERACIÓN DE CÓDIGO DE PRODUCTO
  // ============================================================

  Future<String> _generateProductCode(int categoryId) async {
    final categories = await _db.getCategories();

    Map<String, dynamic>? category;

    for (final c in categories) {
      if (_toInt(c['id']) == categoryId) {
        category = c;
        break;
      }
    }

    final prefix = _buildCategoryPrefix(category);

    final products = await _db.getAllProducts();

    var max = 0;

    for (final p in products) {
      final code = (p['code'] ?? '').toString().trim();

      final match = RegExp('^${RegExp.escape(prefix)}-(\\d{3})\$')
          .firstMatch(code);

      if (match != null) {
        final n = int.tryParse(match.group(1) ?? '') ?? 0;
        if (n > max) max = n;
        continue;
      }

      final legacy = RegExp('^${RegExp.escape(prefix)}(\\d{3})\$')
          .firstMatch(code);

      if (legacy != null) {
        final n = int.tryParse(legacy.group(1) ?? '') ?? 0;
        if (n > max) max = n;
      }
    }

    return '$prefix-${(max + 1).toString().padLeft(3, '0')}';
  }

  String _buildCategoryPrefix(Map<String, dynamic>? category) {
    final raw = (category?['name'] ?? category?['nombre'] ?? '')
        .toString()
        .trim();

    if (raw.isEmpty) return 'PRD';

    final normalized = _removeAccents(raw.toUpperCase())
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');

    final words = normalized
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return 'PRD';

    var prefix = words.first.substring(
      0,
      words.first.length >= 3 ? 3 : words.first.length,
    );

    if (prefix.length < 3 && words.length > 1) {
      for (final w in words.skip(1)) {
        if (prefix.length >= 3) break;
        final remaining = 3 - prefix.length;
        prefix += w.substring(0, remaining.clamp(0, w.length));
      }
    }

    while (prefix.length < 3) {
      prefix += 'X';
    }

    return prefix.substring(0, 3);
  }

  String _removeAccents(String value) {
    return value
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ñ', 'N');
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String? _cellToString(Data? cell) {
    if (cell == null) return null;

    final value = cell.value;

    if (value == null) return null;

    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value ? 'SI' : 'NO';
    if (value is DateCellValue) return value.year.toString();

    return value.toString();
  }

  Map<String, dynamic>? jsonDecodeSafe(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }
}

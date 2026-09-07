import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/database/local_db.dart';

class CatalogEditScreen extends StatefulWidget {
  final String table;
  final bool isProduct;
  final bool isClient;
  final String catalogTitle;
  final Map<String, dynamic>? item;

  const CatalogEditScreen({
    super.key,
    required this.table,
    required this.isProduct,
    required this.isClient,
    required this.catalogTitle,
    this.item,
  });

  @override
  State<CatalogEditScreen> createState() => _CatalogEditScreenState();
}

class _CatalogEditScreenState extends State<CatalogEditScreen> {
  final LocalDb _db = LocalDb();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _focusNode = FocusNode();

  late final TextEditingController _nameController;

  // CÓDIGO: solo lectura para productos (se genera automáticamente)
  // Para otros catálogos sigue siendo editable.
  final TextEditingController _codeController = TextEditingController();

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _rfcController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();

  bool _isSaving = false;
  bool _isDisposed = false;

  // ============================================================
  // INVENTARIABLE
  // ============================================================
  // true = el producto maneja stock; false = no inventariable
  bool _esInventariable = true;

  // ============================================================
  // CATEGORÍAS
  // ============================================================

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  bool _loadingCategories = false;

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.item?['name']?.toString() ??
          widget.item?['nombre']?.toString() ??
          '',
    );

    // Para productos el código se lee como referencia pero no se edita manualmente
    _codeController.text = widget.item?['code']?.toString() ??
        widget.item?['codigo']?.toString() ??
        '';

    _priceController.text = widget.item?['price']?.toString() ??
        widget.item?['precio']?.toString() ??
        '';

    final stockRaw = _toDouble(widget.item?['stock']);
    _stockController.text = widget.item != null ? stockRaw.toStringAsFixed(0) : '0';

    // Determinar si es inventariable.
    // Si el item ya existe y tiene stock == null o is_inventariable == false → no inventariable.
    if (widget.item != null && widget.isProduct) {
      final inv = widget.item!['is_inventariable'] ??
          widget.item!['inventariable'];
      if (inv != null) {
        _esInventariable = _toBool(inv);
      } else {
        // Por defecto: si ya tiene stock registrado asumimos inventariable
        _esInventariable = stockRaw > 0;
      }
    }

    _emailController.text = widget.item?['email']?.toString() ?? '';
    _phoneController.text = widget.item?['phone']?.toString() ?? '';
    _rfcController.text = widget.item?['rfc']?.toString() ?? '';
    _rateController.text = widget.item?['rate']?.toString() ?? '';

    if (widget.isProduct) {
      _selectedCategoryId = _getExistingCategoryId();
      _loadCategories();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rfcController.dispose();
    _rateController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  // ============================================================
  // CATEGORÍAS — CARGA
  // ============================================================

  int? _getExistingCategoryId() {
    final directValues = [
      widget.item?['categoria_id'],
      widget.item?['category_id'],
      widget.item?['categoryId'],
    ];
    for (final value in directValues) {
      final id = _toIntOrNull(value);
      if (id != null) return id;
    }
    final raw = widget.item?['data_json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final key in ['categoria_id', 'category_id', 'categoryId']) {
            final id = _toIntOrNull(decoded[key]);
            if (id != null) return id;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _loadCategories() async {
    if (_isDisposed || !mounted) return;
    _safeSetState(() => _loadingCategories = true);

    try {
      final categories = await _db.getCategories();
      if (_isDisposed || !mounted) return;

      _safeSetState(() {
        _categories =
            categories.map((e) => Map<String, dynamic>.from(e)).toList();
        _loadingCategories = false;

        if (_selectedCategoryId != null) {
          final exists = _categories.any(
            (c) => _toIntOrNull(c['id']) == _selectedCategoryId,
          );
          if (!exists) _selectedCategoryId = null;
        }
      });
    } catch (_) {
      if (_isDisposed || !mounted) return;
      _safeSetState(() => _loadingCategories = false);
    }
  }

  // ============================================================
  // GENERACIÓN AUTOMÁTICA DE CÓDIGO
  // ============================================================

  /// Al cambiar la categoría seleccionada, genera el código del producto.
  /// Formato: [clave_categoría][consecutivo 3 dígitos]
  /// Ejemplo: BEB → BEB001, BEB002 …
  Future<void> _onCategoryChanged(int? newId) async {
    if (newId == _selectedCategoryId) return;

    _safeSetState(() {
      _selectedCategoryId = newId;
      _codeController.text = ''; // limpia mientras genera
    });

    if (newId == null) return;

    try {
      // Clave de la categoría (campo code o nombre truncado)
      final cat = _categories.firstWhere(
        (c) => _toIntOrNull(c['id']) == newId,
        orElse: () => <String, dynamic>{},
      );

      final catCode = (cat['code']?.toString().trim().isNotEmpty == true
              ? cat['code'].toString().trim()
              : (cat['name']?.toString().trim() ?? ''))
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]'), '')
          .substring(0, cat['code']?.toString().trim().isNotEmpty == true
              ? (cat['code'] as String).trim().length.clamp(0, 6)
              : (cat['name']?.toString().trim().length ?? 0).clamp(0, 4));

      // Contar productos existentes en esa categoría para el consecutivo
      final allProducts = await _db.getAllProducts();
      int count = 0;
      for (final p in allProducts) {
        final dataJson = p['data_json'];
        if (dataJson is String && dataJson.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(dataJson);
            if (decoded is Map) {
              final catId = _toIntOrNull(decoded['categoria_id'] ?? decoded['category_id']);
              if (catId == newId) count++;
            }
          } catch (_) {}
        }
      }

      // Si estamos editando un producto existente, su slot ya está ocupado → no sumar
      final isNew = widget.item == null;
      final nextNum = isNew ? count + 1 : count;
      final code =
          '${catCode.isEmpty ? 'PRD' : catCode}${nextNum.toString().padLeft(3, '0')}';

      if (!_isDisposed && mounted) {
        _safeSetState(() => _codeController.text = code);
      }
    } catch (_) {
      // Si falla la generación, no bloquear al usuario
    }
  }

  // ============================================================
  // GUARDAR
  // ============================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    if (widget.isProduct && _selectedCategoryId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Debes seleccionar una categoría.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }

    _safeSetState(() => _isSaving = true);

    try {
      final isNew = widget.item == null;
      final id = isNew ? null : _toIntOrNull(widget.item!['id']);

      if (widget.isProduct) {
        final price = double.tryParse(_priceController.text.trim()) ?? 0;
        final stock = _esInventariable
            ? (double.tryParse(_stockController.text.trim()) ?? 0)
            : 0.0;

        final Map<String, dynamic> productData = _getExistingProductData();
        productData['categoria_id'] = _selectedCategoryId;
        productData['is_inventariable'] = _esInventariable;

        if (isNew) {
          await _db.createProduct(
            code: _codeController.text.trim(),
            name: _nameController.text.trim(),
            price: price,
            stock: stock,
            data: productData,
          );
        } else {
          if (id == null) throw Exception('ID inválido');
          await _db.updateProduct(
            id: id,
            code: _codeController.text.trim(),
            name: _nameController.text.trim(),
            price: price,
            stock: stock,
            data: productData,
          );
        }

        // Notificar al POS para que recargue el catálogo en tiempo real (tarea 3)
        LocalDb.notifySalesChanged();
      } else if (widget.isClient) {
        if (isNew) {
          await _db.createClient(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            rfc: _rfcController.text.trim(),
          );
        } else {
          if (id == null) throw Exception('ID inválido');
          await _db.updateClient(
            id: id,
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            rfc: _rfcController.text.trim(),
          );
        }
      } else {
        final rate = _rateController.text.trim().isNotEmpty
            ? double.tryParse(_rateController.text.trim()) ?? 0.0
            : null;

        if (isNew) {
          await _db.createCatalogItem(
            table: widget.table,
            name: _nameController.text.trim(),
            code: _codeController.text.trim(),
            rate: rate,
          );
        } else {
          if (id == null) throw Exception('ID inválido');
          await _db.updateCatalogItem(
            table: widget.table,
            id: id,
            name: _nameController.text.trim(),
            code: _codeController.text.trim(),
            rate: rate,
          );
        }
      }

      if (_isDisposed || !mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      _safeSetState(() => _isSaving = false);
    }
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  Map<String, dynamic> _getExistingProductData() {
    final result = <String, dynamic>{};
    final raw = widget.item?['data_json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) result.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return result;
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final t = v.toString().trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().trim() ?? '') ?? 0;
  }

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'si' || s == 'yes';
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  String? _number(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requerido';
    return double.tryParse(v.trim()) == null ? 'Número inválido' : null;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    final isTax = widget.table == 'taxes';

    final title = isNew
        ? 'Nuevo ${widget.catalogTitle.toLowerCase()}'
        : 'Editar ${widget.item?['name']?.toString() ?? widget.item?['nombre']?.toString() ?? 'registro'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── NOMBRE ────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.label_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),

                  const SizedBox(height: 16),

                  // ── CÓDIGO: editable solo para catálogos NO producto ──
                  if (!widget.isClient && !widget.isProduct) ...[
                    TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Código / Clave',
                        prefixIcon: Icon(Icons.code),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ══════════════════════════════════════════════
                  // SECCIÓN PRODUCTO
                  // ══════════════════════════════════════════════

                  if (widget.isProduct) ...[
                    // ── CATEGORÍA (obligatoria) ────────────────
                    if (_loadingCategories)
                      const InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Categoría *',
                          prefixIcon: Icon(Icons.category_outlined),
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Cargando categorías...'),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Categoría *',
                          prefixIcon: Icon(Icons.category_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: _categories
                            .map((category) {
                              final id = _toIntOrNull(category['id']);
                              final name =
                                  (category['name'] ?? category['nombre'] ?? '')
                                      .toString();
                              if (id == null) return null;
                              return DropdownMenuItem<int>(
                                value: id,
                                child: Text(
                                  name.isEmpty ? 'Sin nombre' : name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .whereType<DropdownMenuItem<int>>()
                            .toList(),
                        onChanged: _isSaving ? null : _onCategoryChanged,
                        validator: (value) =>
                            value == null ? 'Selecciona una categoría' : null,
                      ),

                    const SizedBox(height: 16),

                    // ── AVISO: sin categorías ──────────────────
                    if (!_loadingCategories && _categories.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No hay categorías activas. Crea una categoría antes de guardar el producto.',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── CÓDIGO GENERADO (solo lectura) ─────────
                    if (_codeController.text.isNotEmpty) ...[
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Código (generado automáticamente)',
                          prefixIcon: const Icon(Icons.qr_code_outlined),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          _codeController.text,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── PRECIO ────────────────────────────────
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Precio',
                        prefixIcon: Icon(Icons.attach_money),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: _number,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                    ),

                    const SizedBox(height: 16),

                    // ── INVENTARIABLE / NO INVENTARIABLE ───────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Theme.of(context).colorScheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warehouse_outlined,
                              color: Colors.grey, size: 22),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¿El producto maneja inventario?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Si es inventariable, se controlará el stock al vender.',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _esInventariable,
                            onChanged: _isSaving
                                ? null
                                : (value) => _safeSetState(
                                    () => _esInventariable = value),
                            activeThumbColor: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── EXISTENCIA (solo si inventariable) ────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _esInventariable
                          ? TextFormField(
                              key: const ValueKey('stock_enabled'),
                              controller: _stockController,
                              decoration: const InputDecoration(
                                labelText: 'Existencia inicial',
                                prefixIcon:
                                    Icon(Icons.warehouse_outlined),
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: _number,
                            )
                          : InputDecorator(
                              key: const ValueKey('stock_disabled'),
                              decoration: InputDecoration(
                                labelText: 'Existencia',
                                prefixIcon:
                                    const Icon(Icons.warehouse_outlined),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                suffixText: 'No inventariable',
                                suffixStyle: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500),
                              ),
                              child: Text(
                                'N/A',
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14),
                              ),
                            ),
                    ),

                    const SizedBox(height: 16),
                  ],

                  // ══════════════════════════════════════════════
                  // SECCIÓN CLIENTE
                  // ══════════════════════════════════════════════

                  if (widget.isClient) ...[
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _rfcController,
                      decoration: const InputDecoration(
                        labelText: 'RFC',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ══════════════════════════════════════════════
                  // SECCIÓN IMPUESTO
                  // ══════════════════════════════════════════════

                  if (isTax) ...[
                    TextFormField(
                      controller: _rateController,
                      decoration: const InputDecoration(
                        labelText: 'Tasa (%)',
                        prefixIcon: Icon(Icons.percent),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        return double.tryParse(v.trim()) == null
                            ? 'Número inválido'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── BOTONES ────────────────────────────────
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

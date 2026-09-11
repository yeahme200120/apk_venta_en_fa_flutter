import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';

class CatalogEditScreen extends StatefulWidget {
  const CatalogEditScreen({
    super.key,
    required this.table,
    required this.isProduct,
    required this.isClient,
    required this.catalogTitle,
    this.item,
  });

  final String table;
  final bool isProduct;
  final bool isClient;
  final String catalogTitle;
  final Map<String, dynamic>? item;

  @override
  State<CatalogEditScreen> createState() => _CatalogEditScreenState();
}

class _CatalogEditScreenState extends State<CatalogEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _db = LocalDb();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;

  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _rfcController;

  late final TextEditingController _rateController;

  bool _saving = false;

  bool _esInventariable = false;

  List<Map<String, dynamic>> _categories = const [];
  int? _selectedCategoryId;
  bool _loadingCategories = false;

  bool get _isEditing => widget.item != null;

  bool get _isCategory =>
      widget.table == 'categories' && !widget.isProduct && !widget.isClient;

  @override
  void initState() {
    super.initState();

    final item = widget.item ?? {};

    _nameController = TextEditingController(
      text: _stringValue(item, ['name', 'nombre']),
    );

    _codeController = TextEditingController(
      text: _stringValue(item, ['code', 'codigo', 'sku']),
    );

    _priceController = TextEditingController(
      text: _numberText(item['price'] ?? item['precio']),
    );

    _stockController = TextEditingController(
      text: _numberText(item['stock'] ?? item['existencia']),
    );

    final existingInventory = item['is_inventariable'] ?? item['inventariable'];

    if (existingInventory != null) {
      _esInventariable = _boolValue(existingInventory);
    } else if (widget.isProduct && _isEditing) {
      final stock = _toDouble(item['stock'] ?? item['existencia']);

      _esInventariable = stock > 0;
    }

    _emailController = TextEditingController(
      text: _stringValue(item, ['email', 'correo']),
    );

    _phoneController = TextEditingController(
      text: _stringValue(item, ['phone', 'telefono', 'teléfono']),
    );

    _rfcController = TextEditingController(text: _stringValue(item, ['rfc']));

    _rateController = TextEditingController(
      text: _numberText(item['rate'] ?? item['tasa'] ?? item['porcentaje']),
    );

    if (widget.isProduct) {
      _selectedCategoryId = _getExistingCategoryId();

      _loadCategories();
    }

    if (_isCategory && !_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateCategoryCode();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rfcController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  String _numberText(dynamic value) {
    if (value == null) {
      return '';
    }

    final number = _toDouble(value);

    if (number == 0) {
      return '';
    }

    if (number == number.roundToDouble()) {
      return number.toInt().toString();
    }

    return number.toString();
  }

  bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase() ?? '';

    return text == '1' ||
        text == 'true' ||
        text == 'si' ||
        text == 'sí' ||
        text == 'yes';
  }

  int? _getExistingCategoryId() {
    final item = widget.item ?? {};

    final directKeys = ['categoria_id', 'category_id', 'categoryId'];

    for (final key in directKeys) {
      final value = item[key];

      if (value != null) {
        final parsed = int.tryParse(value.toString());

        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    }

    final dataJson = item['data_json'];

    if (dataJson is String && dataJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(dataJson);

        if (decoded is Map) {
          for (final key in directKeys) {
            final value = decoded[key];

            if (value != null) {
              final parsed = int.tryParse(value.toString());

              if (parsed != null && parsed > 0) {
                return parsed;
              }
            }
          }
        }
      } catch (_) {
        // Ignorar JSON inválido.
      }
    }

    return null;
  }

  // ===========================================================================
  // CATEGORIES
  // ===========================================================================

  Future<void> _loadCategories() async {
    if (!widget.isProduct) {
      return;
    }

    setState(() {
      _loadingCategories = true;
    });

    try {
      final rows = await _db.getCategories();

      if (!mounted) {
        return;
      }

      final categories = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      var selected = _selectedCategoryId;

      if (selected != null &&
          !categories.any((category) => _toInt(category['id']) == selected)) {
        selected = null;
      }

      setState(() {
        _categories = categories;
        _selectedCategoryId = selected;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingCategories = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar las categorías: $e')),
      );
    }
  }

  // ===========================================================================
  // PRODUCT CODE
  // ===========================================================================

  String _buildCategoryPrefix(Map<String, dynamic>? category) {
    final raw = _stringValue(category ?? const {}, [
      'name',
      'nombre',
      'code',
      'codigo',
    ]);

    if (raw.isEmpty) {
      return 'PRD';
    }

    final normalized = _removeAccents(raw.toUpperCase())
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');

    final words = normalized
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return 'PRD';
    }

    var prefix = words.first.substring(
      0,
      words.first.length >= 3 ? 3 : words.first.length,
    );

    if (prefix.length < 3 && words.length > 1) {
      for (final word in words.skip(1)) {
        if (prefix.length >= 3) {
          break;
        }

        prefix += word.substring(0, (3 - prefix.length).clamp(0, word.length));
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

  Future<int> _getNextProductSequence(String prefix) async {
    final products = await _db.getAllProducts();

    var max = 0;

    for (final product in products) {
      final code = product['code']?.toString().trim() ?? '';

      final match = RegExp('^${RegExp.escape(prefix)}-(\\d{3})\$')
          .firstMatch(code);

      if (match != null) {
        final number = int.tryParse(match.group(1) ?? '') ?? 0;

        if (number > max) {
          max = number;
        }

        continue;
      }

      final legacyMatch = RegExp('^${RegExp.escape(prefix)}(\\d{3})\$')
          .firstMatch(code);

      if (legacyMatch != null) {
        final number = int.tryParse(legacyMatch.group(1) ?? '') ?? 0;

        if (number > max) {
          max = number;
        }
      }
    }

    return max + 1;
  }

  Future<String> _generateProductCode(int categoryId) async {
    Map<String, dynamic>? category;

    for (final item in _categories) {
      if (_toInt(item['id']) == categoryId) {
        category = item;
        break;
      }
    }

    final prefix = _buildCategoryPrefix(category);

    final sequence = await _getNextProductSequence(prefix);

    return '$prefix-${sequence.toString().padLeft(3, '0')}';
  }

  Future<void> _onCategoryChanged(int? value) async {
    setState(() {
      _selectedCategoryId = value;
    });

    // Solo generamos código automáticamente
    // al crear un producto nuevo.
    if (!_isEditing && value != null) {
      try {
        final code = await _generateProductCode(value);

        if (!mounted) {
          return;
        }

        setState(() {
          _codeController.text = code;
        });
      } catch (_) {
        // El guardado seguirá validando
        // los datos aunque falle la generación.
      }
    }
  }

  // ===========================================================================
  // CATEGORY CODE
  // ===========================================================================

  Future<void> _generateCategoryCode() async {
    if (!_isCategory || _isEditing) {
      return;
    }

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      if (_codeController.text.isNotEmpty) {
        setState(() {
          _codeController.clear();
        });
      }

      return;
    }

    try {
      final code = await _db.getNextCategoryCode(name);

      if (!mounted) {
        return;
      }

      setState(() {
        _codeController.text = code;
      });
    } catch (_) {
      // El guardado volverá a intentar generar
      // la clave si fuera necesario.
    }
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      return;
    }

    if (widget.isProduct && _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una categoría para el producto.'),
        ),
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (widget.isProduct) {
        final price = _toDouble(_priceController.text);

        final double stock = _esInventariable
            ? _toDouble(_stockController.text)
            : 0.0;

        final data = _existingProductData();

        data['categoria_id'] = _selectedCategoryId;

        data['is_inventariable'] = _esInventariable;

        var code = _codeController.text.trim();

        if (code.isEmpty && _selectedCategoryId != null) {
          code = await _generateProductCode(_selectedCategoryId!);

          _codeController.text = code;
        }

        if (_isEditing) {
          final localId = _toInt(widget.item!['id']);

          await _db.updateProduct(
            id: localId,
            serverId: _nullableInt(
              widget.item!['server_id'] ?? widget.item!['serverId'],
            ),
            categoryId: _selectedCategoryId,
            code: code,
            name: name,
            price: price,
            stock: stock,
            isActive: true,
            data: data,
          );
        } else {
          await _db.createProduct(
            categoryId: _selectedCategoryId,
            code: code,
            name: name,
            price: price,
            stock: stock,
            isActive: true,
            data: data,
          );
        }

        LocalDb.notifySalesChanged();
      } else if (widget.isClient) {
        final data = <String, dynamic>{
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'rfc': _rfcController.text.trim(),
        };

        if (_isEditing) {
          await _db.updateCatalogItem(
            table: widget.table,
            id: _toInt(widget.item!['id']),
            name: name,
            code: _codeController.text.trim(),
            data: data,
          );
        } else {
          await _db.createCatalogItem(
            table: widget.table,
            name: name,
            code: _codeController.text.trim(),
            data: data,
          );
        }
      } else {
        final rate = _toDouble(_rateController.text);

        var code = _codeController.text.trim();

        // Las categorías nuevas reciben una clave
        // automática. Las categorías existentes
        // conservan su clave actual.
        if (_isCategory && !_isEditing) {
          if (code.isEmpty) {
            code = await _db.getNextCategoryCode(name);

            _codeController.text = code;
          }
        }

        if (_isEditing) {
          await _db.updateCatalogItem(
            table: widget.table,
            id: _toInt(widget.item!['id']),
            name: name,
            code: code,
            rate: rate,
          );
        } else {
          await _db.createCatalogItem(
            table: widget.table,
            name: name,
            code: code,
            rate: rate,
          );
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Map<String, dynamic> _existingProductData() {
    final raw = widget.item?['data_json'];

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Ignorar JSON inválido.
      }
    }

    return {};
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableInt(dynamic value) {
    final parsed = _toInt(value);

    return parsed > 0 ? parsed : null;
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final isProduct = widget.isProduct;
    final isClient = widget.isClient;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Editar ${widget.catalogTitle}'
              : 'Nuevo ${widget.catalogTitle}',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  if (_isCategory && !_isEditing) {
                    _generateCategoryCode();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa un nombre.';
                  }

                  return null;
                },
              ),

              // =================================================================
              // CLAVE AUTOMÁTICA DE CATEGORÍA
              // =================================================================
              if (_isCategory)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Clave de categoría',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _codeController.text.trim().isEmpty
                                ? 'Se generará automáticamente'
                                : _codeController.text.trim(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!_isEditing)
                          const Icon(Icons.auto_awesome_rounded, size: 20),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // =================================================================
              // CÓDIGO MANUAL PARA OTROS CATÁLOGOS
              // =================================================================
              if (!isClient && !isProduct && !_isCategory)
                TextFormField(
                  controller: _codeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Código / clave',
                    border: OutlineInputBorder(),
                  ),
                ),

              if (!isClient && !isProduct && !_isCategory)
                const SizedBox(height: 16),

              // =================================================================
              // PRODUCTO
              // =================================================================
              if (isProduct) ...[
                DropdownButtonFormField<int>(
                  value: _selectedCategoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem<int>(
                          value: _toInt(category['id']),
                          child: Text(
                            _stringValue(category, ['name', 'nombre']),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingCategories ? null : _onCategoryChanged,
                  validator: (_) {
                    if (_selectedCategoryId == null) {
                      return 'Selecciona una categoría.';
                    }

                    return null;
                  },
                ),

                if (_loadingCategories)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),

                if (!_loadingCategories && _categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No hay categorías disponibles. '
                      'Crea una categoría antes de registrar productos.',
                    ),
                  ),

                if (_codeController.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Código generado',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _codeController.text.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Maneja inventario'),
                  subtitle: const Text(
                    'Permite controlar existencias de este producto.',
                  ),
                  value: _esInventariable,
                  onChanged: (value) {
                    setState(() {
                      _esInventariable = value;

                      if (!value) {
                        _stockController.clear();
                      }
                    });
                  },
                ),

                if (_esInventariable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      controller: _stockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Existencia inicial',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],

              // =================================================================
              // CLIENTE
              // =================================================================
              if (isClient) ...[
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _rfcController,
                  decoration: const InputDecoration(
                    labelText: 'RFC',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              // =================================================================
              // IMPUESTOS
              // =================================================================
              if (widget.table == 'taxes') ...[
                const SizedBox(height: 16),

                TextFormField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tasa (%)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // =================================================================
              // BOTONES
              // =================================================================
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

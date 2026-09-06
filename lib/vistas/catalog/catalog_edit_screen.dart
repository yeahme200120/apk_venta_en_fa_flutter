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
  State<CatalogEditScreen> createState() =>
      _CatalogEditScreenState();
}

class _CatalogEditScreenState
    extends State<CatalogEditScreen> {
  final LocalDb _db = LocalDb();
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();
  final FocusNode _focusNode = FocusNode();

  late final TextEditingController
      _nameController;

  final TextEditingController
      _codeController =
      TextEditingController();

  final TextEditingController
      _priceController =
      TextEditingController();

  final TextEditingController
      _stockController =
      TextEditingController();

  final TextEditingController
      _emailController =
      TextEditingController();

  final TextEditingController
      _phoneController =
      TextEditingController();

  final TextEditingController
      _rfcController =
      TextEditingController();

  final TextEditingController
      _rateController =
      TextEditingController();

  bool _isSaving = false;
  bool _isDisposed = false;

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

    _nameController =
        TextEditingController(
      text: widget.item?['name']?.toString() ??
          widget.item?['nombre']?.toString() ??
          '',
    );

    _codeController.text =
        widget.item?['code']?.toString() ??
            widget.item?['codigo']?.toString() ??
            '';

    _priceController.text =
        widget.item?['price']?.toString() ??
            widget.item?['precio']?.toString() ??
            '';

    _stockController.text =
        widget.item?['stock']?.toString() ??
            '0';

    _emailController.text =
        widget.item?['email']?.toString() ??
            '';

    _phoneController.text =
        widget.item?['phone']?.toString() ??
            '';

    _rfcController.text =
        widget.item?['rfc']?.toString() ??
            '';

    _rateController.text =
        widget.item?['rate']?.toString() ??
            '';

    if (widget.isProduct) {
      _selectedCategoryId =
          _getExistingCategoryId();

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

  // ============================================================
  // SETSTATE SEGURO
  // ============================================================

  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  // ============================================================
  // CATEGORÍAS
  // ============================================================

  int? _getExistingCategoryId() {
    final directValues = [
      widget.item?['categoria_id'],
      widget.item?['category_id'],
      widget.item?['categoryId'],
    ];

    for (final value in directValues) {
      final id = _toIntOrNull(value);

      if (id != null) {
        return id;
      }
    }

    final raw = widget.item?['data_json'];

    if (raw is String &&
        raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          final values = [
            decoded['categoria_id'],
            decoded['category_id'],
            decoded['categoryId'],
          ];

          for (final value in values) {
            final id = _toIntOrNull(value);

            if (id != null) {
              return id;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _loadCategories() async {
    if (_isDisposed || !mounted) return;

    _safeSetState(
      () => _loadingCategories = true,
    );

    try {
      final categories =
          await _db.getCategories();

      if (_isDisposed || !mounted) return;

      _safeSetState(() {
        _categories = categories
            .map(
              (e) =>
                  Map<String, dynamic>.from(e),
            )
            .toList();

        _loadingCategories = false;

        if (_selectedCategoryId != null) {
          final exists = _categories.any(
            (category) =>
                _toIntOrNull(
                  category['id'],
                ) ==
                _selectedCategoryId,
          );

          if (!exists) {
            _selectedCategoryId = null;
          }
        }
      });
    } catch (_) {
      if (_isDisposed || !mounted) return;

      _safeSetState(
        () => _loadingCategories = false,
      );
    }
  }

  // ============================================================
  // GUARDAR
  // ============================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isSaving) return;

    // ----------------------------------------------------------
    // CATEGORÍA OBLIGATORIA PARA PRODUCTOS
    // ----------------------------------------------------------

    if (widget.isProduct &&
        _selectedCategoryId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Debes seleccionar una categoría.',
            ),
            behavior:
                SnackBarBehavior.floating,
          ),
        );

      return;
    }

    _safeSetState(
      () => _isSaving = true,
    );

    try {
      final isNew = widget.item == null;

      final id = isNew
          ? null
          : _toIntOrNull(
              widget.item!['id'],
            );

      if (widget.isProduct) {
        final price = double.tryParse(
              _priceController.text.trim(),
            ) ??
            0;

        final stock = double.tryParse(
              _stockController.text.trim(),
            ) ??
            0;

        // ------------------------------------------------------
        // PRESERVAR data_json EXISTENTE
        // ------------------------------------------------------

        final Map<String, dynamic>
            productData =
            _getExistingProductData();

        productData['categoria_id'] =
            _selectedCategoryId;

        if (isNew) {
          await _db.createProduct(
            code:
                _codeController.text.trim(),
            name:
                _nameController.text.trim(),
            price: price,
            stock: stock,
            data: productData,
          );
        } else {
          if (id == null) {
            throw Exception('ID inválido');
          }

          await _db.updateProduct(
            id: id,
            code:
                _codeController.text.trim(),
            name:
                _nameController.text.trim(),
            price: price,
            stock: stock,
            data: productData,
          );
        }
      } else if (widget.isClient) {
        if (isNew) {
          await _db.createClient(
            name:
                _nameController.text.trim(),
            email:
                _emailController.text.trim(),
            phone:
                _phoneController.text.trim(),
            rfc:
                _rfcController.text.trim(),
          );
        } else {
          if (id == null) {
            throw Exception('ID inválido');
          }

          await _db.updateClient(
            id: id,
            name:
                _nameController.text.trim(),
            email:
                _emailController.text.trim(),
            phone:
                _phoneController.text.trim(),
            rfc:
                _rfcController.text.trim(),
          );
        }
      } else {
        final rate =
            _rateController.text
                    .trim()
                    .isNotEmpty
                ? double.tryParse(
                      _rateController.text
                          .trim(),
                    ) ??
                    0.0
                : null;

        if (isNew) {
          await _db.createCatalogItem(
            table: widget.table,
            name:
                _nameController.text.trim(),
            code:
                _codeController.text.trim(),
            rate: rate,
          );
        } else {
          if (id == null) {
            throw Exception('ID inválido');
          }

          await _db.updateCatalogItem(
            table: widget.table,
            id: id,
            name:
                _nameController.text.trim(),
            code:
                _codeController.text.trim(),
            rate: rate,
          );
        }
      }

      if (_isDisposed || !mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (_isDisposed || !mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content:
              Text('Error al guardar: $e'),
          behavior:
              SnackBarBehavior.floating,
        ),
      );
    } finally {
      _safeSetState(
        () => _isSaving = false,
      );
    }
  }

  // ============================================================
  // DATA DEL PRODUCTO
  // ============================================================

  Map<String, dynamic>
      _getExistingProductData() {
    final result =
        <String, dynamic>{};

    final raw = widget.item?['data_json'];

    if (raw is String &&
        raw.trim().isNotEmpty) {
      try {
        final decoded =
            jsonDecode(raw);

        if (decoded is Map) {
          result.addAll(
            Map<String, dynamic>.from(
              decoded,
            ),
          );
        }
      } catch (_) {}
    }

    return result;
  }

  // ============================================================
  // VALIDADORES Y UTILIDADES
  // ============================================================

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;

    if (v is int) return v;

    if (v is num) {
      return v.toInt();
    }

    final t = v.toString().trim();

    return t.isEmpty
        ? null
        : int.tryParse(t);
  }

  String? _required(String? v) {
    return (v == null ||
            v.trim().isEmpty)
        ? 'Requerido'
        : null;
  }

  String? _number(String? v) {
    if (v == null ||
        v.trim().isEmpty) {
      return 'Requerido';
    }

    return double.tryParse(
              v.trim(),
            ) ==
            null
        ? 'Número inválido'
        : null;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;

    final isTax =
        widget.table == 'taxes';

    String title;

    if (isNew) {
      title =
          'Nuevo ${widget.catalogTitle.toLowerCase()}';
    } else {
      final name =
          widget.item?['name']
                  ?.toString() ??
              widget.item?['nombre']
                  ?.toString() ??
              'registro';

      title = 'Editar $name';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          overflow:
              TextOverflow.ellipsis,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding:
                  EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                ),
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
              padding:
                  const EdgeInsets.all(20),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior
                      .onDrag,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,
                children: [
                  // ---------- NOMBRE ----------
                  TextFormField(
                    controller:
                        _nameController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(
                        Icons.label_outline,
                      ),
                      border:
                          OutlineInputBorder(),
                    ),
                    validator: _required,
                    textInputAction:
                        TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        FocusScope.of(
                          context,
                        ).nextFocus(),
                  ),

                  const SizedBox(height: 16),

                  // ---------- CÓDIGO ----------
                  if (!widget.isClient) ...[
                    TextFormField(
                      controller:
                          _codeController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Código / Clave',
                        prefixIcon:
                            Icon(Icons.code),
                        border:
                            OutlineInputBorder(),
                      ),
                      textInputAction:
                          TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(
                            context,
                          ).nextFocus(),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  // ==================================================
                  // PRODUCTO
                  // ==================================================

                  if (widget.isProduct) ...[
                    // ---------- CATEGORÍA ----------
                    if (_loadingCategories)
                      const InputDecorator(
                        decoration:
                            InputDecoration(
                          labelText:
                              'Categoría *',
                          prefixIcon: Icon(
                            Icons
                                .category_outlined,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              'Cargando categorías...',
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        value:
                            _selectedCategoryId,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Categoría *',
                          prefixIcon: Icon(
                            Icons
                                .category_outlined,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                        items: _categories
                            .map(
                              (
                                category,
                              ) {
                                final id =
                                    _toIntOrNull(
                                  category[
                                      'id'],
                                );

                                final name =
                                    (category[
                                                'name'] ??
                                            category[
                                                'nombre'] ??
                                            '')
                                        .toString();

                                if (id ==
                                    null) {
                                  return null;
                                }

                                return DropdownMenuItem<
                                    int>(
                                  value: id,
                                  child:
                                      Text(
                                    name.isEmpty
                                        ? 'Sin nombre'
                                        : name,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                  ),
                                );
                              },
                            )
                            .whereType<
                                DropdownMenuItem<
                                    int>>()
                            .toList(),
                        onChanged:
                            _isSaving
                                ? null
                                : (value) {
                                    _safeSetState(
                                      () =>
                                          _selectedCategoryId =
                                              value,
                                    );
                                  },
                        validator:
                            (value) {
                          if (value ==
                              null) {
                            return 'Selecciona una categoría';
                          }

                          return null;
                        },
                      ),

                    const SizedBox(
                      height: 16,
                    ),

                    // ---------- AVISO SIN CATEGORÍAS ----------
                    if (!_loadingCategories &&
                        _categories.isEmpty)
                      Container(
                        padding:
                            const EdgeInsets
                                .all(12),
                        decoration:
                            BoxDecoration(
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .errorContainer,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Icon(
                              Icons
                                  .warning_amber_outlined,
                              color: Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: Text(
                                'No hay categorías activas. Crea una categoría antes de guardar el producto.',
                                style:
                                    TextStyle(
                                  color: Theme.of(
                                    context,
                                  )
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (!_loadingCategories &&
                        _categories.isEmpty)
                      const SizedBox(
                        height: 16,
                      ),

                    // ---------- PRECIO ----------
                    TextFormField(
                      controller:
                          _priceController,
                      decoration:
                          const InputDecoration(
                        labelText: 'Precio',
                        prefixIcon: Icon(
                          Icons
                              .attach_money,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      validator: _number,
                      textInputAction:
                          TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(
                            context,
                          ).nextFocus(),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    // ---------- EXISTENCIA ----------
                    TextFormField(
                      controller:
                          _stockController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Existencia',
                        prefixIcon: Icon(
                          Icons
                              .warehouse_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      validator: _number,
                    ),

                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  // ==================================================
                  // CLIENTE
                  // ==================================================

                  if (widget.isClient) ...[
                    TextFormField(
                      controller:
                          _emailController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Correo electrónico',
                        prefixIcon: Icon(
                          Icons
                              .email_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                      keyboardType:
                          TextInputType
                              .emailAddress,
                      textInputAction:
                          TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(
                            context,
                          ).nextFocus(),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    TextFormField(
                      controller:
                          _phoneController,
                      decoration:
                          const InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: Icon(
                          Icons
                              .phone_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                      keyboardType:
                          TextInputType.phone,
                      textInputAction:
                          TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(
                            context,
                          ).nextFocus(),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    TextFormField(
                      controller:
                          _rfcController,
                      decoration:
                          const InputDecoration(
                        labelText: 'RFC',
                        prefixIcon: Icon(
                          Icons
                              .badge_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                      textCapitalization:
                          TextCapitalization
                              .characters,
                    ),

                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  // ==================================================
                  // IMPUESTO
                  // ==================================================

                  if (isTax) ...[
                    TextFormField(
                      controller:
                          _rateController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Tasa (%)',
                        prefixIcon:
                            Icon(Icons.percent),
                        border:
                            OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null ||
                            v.trim().isEmpty) {
                          return 'Requerido';
                        }

                        return double.tryParse(
                                  v.trim(),
                                ) ==
                                null
                            ? 'Número inválido'
                            : null;
                      },
                    ),

                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  // ==================================================
                  // BOTONES
                  // ==================================================

                  const SizedBox(
                    height: 16,
                  ),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () =>
                                Navigator.of(
                                  context,
                                ).pop(false),
                        child:
                            const Text(
                          'Cancelar',
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      FilledButton.icon(
                        onPressed:
                            _isSaving
                                ? null
                                : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .save_outlined,
                              ),
                        label: Text(
                          _isSaving
                              ? 'Guardando...'
                              : 'Guardar',
                        ),
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
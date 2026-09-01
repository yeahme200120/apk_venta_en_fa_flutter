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
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _rfcController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();

  bool _isSaving = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?['name']?.toString() ?? '');
    _codeController.text = widget.item?['code']?.toString() ?? '';
    _priceController.text = widget.item?['price']?.toString() ?? '';
    _stockController.text = widget.item?['stock']?.toString() ?? '0';
    _emailController.text = widget.item?['email']?.toString() ?? '';
    _phoneController.text = widget.item?['phone']?.toString() ?? '';
    _rfcController.text = widget.item?['rfc']?.toString() ?? '';
    _rateController.text = widget.item?['rate']?.toString() ?? '';
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
  // GUARDAR
  // ============================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    _safeSetState(() => _isSaving = true);

    try {
      final isNew = widget.item == null;
      final id = isNew ? null : _toIntOrNull(widget.item!['id']);

      if (widget.isProduct) {
        final price = double.tryParse(_priceController.text.trim()) ?? 0;
        final stock = double.tryParse(_stockController.text.trim()) ?? 0;

        if (isNew) {
          await _db.createProduct(
            code: _codeController.text.trim(),
            name: _nameController.text.trim(),
            price: price,
            stock: stock,
          );
        } else {
          if (id == null) throw Exception('ID inválido');
          await _db.updateProduct(
            id: id,
            code: _codeController.text.trim(),
            name: _nameController.text.trim(),
            price: price,
            stock: stock,
          );
        }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      _safeSetState(() => _isSaving = false);
    }
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final t = v.toString().trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;
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

    String title;
    if (isNew) {
      title = 'Nuevo ${widget.catalogTitle.toLowerCase()}';
    } else {
      final name = widget.item?['name']?.toString() ?? widget.item?['nombre']?.toString() ?? 'registro';
      title = 'Editar $name';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                  // ---------- NOMBRE (siempre presente) ----------
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.label_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 16),

                  // ---------- CÓDIGO (excepto clientes) ----------
                  if (!widget.isClient) ...[
                    TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Código / Clave',
                        prefixIcon: Icon(Icons.code),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: widget.isProduct ? TextInputAction.next : TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---------- PRODUCTO: precio y stock ----------
                  if (widget.isProduct) ...[
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Precio',
                        prefixIcon: Icon(Icons.attach_money),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _number,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _stockController,
                      decoration: const InputDecoration(
                        labelText: 'Existencia',
                        prefixIcon: Icon(Icons.warehouse_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _number,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---------- CLIENTE: email, teléfono, RFC ----------
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
                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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

                  // ---------- IMPUESTO: tasa ----------
                  if (isTax) ...[
                    TextFormField(
                      controller: _rateController,
                      decoration: const InputDecoration(
                        labelText: 'Tasa (%)',
                        prefixIcon: Icon(Icons.percent),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        return double.tryParse(v.trim()) == null ? 'Número inválido' : null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---------- BOTONES ----------
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
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
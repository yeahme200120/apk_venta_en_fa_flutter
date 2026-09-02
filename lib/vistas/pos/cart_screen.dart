import 'package:flutter/material.dart';

import '../../core/models/product.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cartNotifier,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onClear,
    required this.onCheckout,
  });

  final ValueNotifier<List<CartItem>>
      cartNotifier;

  final void Function(
    int productId,
    int delta,
  ) onQuantityChanged;

  final ValueChanged<int> onRemove;

  final VoidCallback onClear;

  final Future<bool> Function()
      onCheckout;

  @override
  State<CartScreen> createState() =>
      _CartScreenState();
}

class _CartScreenState
    extends State<CartScreen> {
  bool _isProcessing = false;

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Carrito de compra',
        ),
        actions: [
          IconButton(
            icon:
                const Icon(
              Icons.close,
            ),
            tooltip:
                'Cerrar',
            onPressed:
                () =>
                    Navigator.of(
              context,
            ).pop(),
          ),
        ],
      ),
      body:
          ValueListenableBuilder<
              List<CartItem>>(
        valueListenable:
            widget.cartNotifier,
        builder:
            (
          context,
          items,
          child,
        ) {
          final total =
              items.fold(
            0.0,
            (
              sum,
              item,
            ) =>
                sum +
                item.subtotal,
          );

          if (items.isEmpty) {
            return const Center(
              child:
                  Padding(
                padding:
                    EdgeInsets.all(
                  24,
                ),
                child:
                    Column(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .center,
                  children: [
                    Icon(
                      Icons
                          .shopping_cart_outlined,
                      size:
                          80,
                      color:
                          Colors.grey,
                    ),
                    SizedBox(
                      height:
                          16,
                    ),
                    Text(
                      'Agrega productos desde la caja para comenzar.',
                      textAlign:
                          TextAlign
                              .center,
                      style:
                          TextStyle(
                        fontSize:
                            16,
                        color:
                            Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return LayoutBuilder(
            builder:
                (
              context,
              constraints,
            ) {
              final isMobile =
                  constraints
                          .maxWidth <
                      600;

              final isDesktop =
                  constraints
                          .maxWidth >=
                      1200;

              return Column(
                children: [
                  Expanded(
                    child:
                        isDesktop
                            ? GridView.builder(
                                padding:
                                    const EdgeInsets.all(
                                  16,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      2,
                                  crossAxisSpacing:
                                      12,
                                  mainAxisSpacing:
                                      12,
                                  childAspectRatio:
                                      2.2,
                                ),
                                itemCount:
                                    items.length,
                                itemBuilder:
                                    (
                                  context,
                                  index,
                                ) =>
                                        _buildCartItem(
                                  items[index],
                                  isMobile:
                                      false,
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.all(
                                  16,
                                ),
                                itemCount:
                                    items.length,
                                separatorBuilder:
                                    (
                                  _,
                                  __,
                                ) =>
                                        const SizedBox(
                                  height:
                                      8,
                                ),
                                itemBuilder:
                                    (
                                  context,
                                  index,
                                ) =>
                                        _buildCartItem(
                                  items[index],
                                  isMobile:
                                      isMobile,
                                ),
                              ),
                  ),

                  _buildBottomBar(
                    total,
                    items.isNotEmpty,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // ITEM DEL CARRITO
  // ============================================================

  Widget _buildCartItem(
    CartItem item, {
    required bool isMobile,
  }) {
    return Card(
      elevation:
          2,
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          12,
        ),
        child:
            isMobile
                ? Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child:
                                Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  item.product
                                      .name,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .w700,
                                    fontSize:
                                        16,
                                  ),
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                ),
                                const SizedBox(
                                  height:
                                      4,
                                ),
                                Text(
                                  '\$${item.product.price.toStringAsFixed(2)} c/u',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.grey,
                                  ),
                                ),
                                const SizedBox(
                                  height:
                                      4,
                                ),
                                Text(
                                  '\$${item.subtotal.toStringAsFixed(2)}',
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    fontSize:
                                        16,
                                    color:
                                        Color(
                                      0xFF9AC53B,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Row(
                            mainAxisSize:
                                MainAxisSize
                                    .min,
                            children: [
                              IconButton(
                                tooltip:
                                    'Disminuir',
                                onPressed:
                                    () =>
                                        widget
                                            .onQuantityChanged(
                                  item.product.id,
                                  -1,
                                ),
                                icon:
                                    const Icon(
                                  Icons
                                      .remove_circle_outline,
                                ),
                                iconSize:
                                    28,
                              ),
                              Text(
                                '${item.quantity}',
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  fontSize:
                                      16,
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'Aumentar',
                                onPressed:
                                    item.quantity <
                                            item.product
                                                .stock
                                        ? () =>
                                            widget
                                                .onQuantityChanged(
                                          item.product
                                              .id,
                                          1,
                                        )
                                        : null,
                                icon:
                                    const Icon(
                                  Icons
                                      .add_circle_outline,
                                ),
                                iconSize:
                                    28,
                              ),
                              IconButton(
                                tooltip:
                                    'Eliminar',
                                onPressed:
                                    () =>
                                        widget
                                            .onRemove(
                                  item.product
                                      .id,
                                ),
                                icon:
                                    const Icon(
                                  Icons
                                      .delete_outline,
                                ),
                                iconSize:
                                    24,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex:
                            2,
                        child:
                            Text(
                          item.product
                              .name,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                      ),
                      Expanded(
                        flex:
                            1,
                        child:
                            Text(
                          '\$${item.product.price.toStringAsFixed(2)}',
                        ),
                      ),
                      Expanded(
                        flex:
                            1,
                        child:
                            Row(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: [
                            IconButton(
                              tooltip:
                                  'Disminuir',
                              onPressed:
                                  () =>
                                      widget
                                          .onQuantityChanged(
                                item.product
                                    .id,
                                -1,
                              ),
                              icon:
                                  const Icon(
                                Icons
                                    .remove_circle_outline,
                              ),
                            ),
                            Text(
                              '${item.quantity}',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  'Aumentar',
                              onPressed:
                                  item.quantity <
                                          item.product
                                              .stock
                                      ? () =>
                                          widget
                                              .onQuantityChanged(
                                        item.product
                                            .id,
                                        1,
                                      )
                                      : null,
                              icon:
                                  const Icon(
                                Icons
                                    .add_circle_outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex:
                            1,
                        child:
                            Text(
                          '\$${item.subtotal.toStringAsFixed(2)}',
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .bold,
                            color:
                                Color(
                              0xFF9AC53B,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip:
                            'Eliminar',
                        onPressed:
                            () =>
                                widget
                                    .onRemove(
                          item.product.id,
                        ),
                        icon:
                            const Icon(
                          Icons
                              .delete_outline,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  // ============================================================
  // BARRA INFERIOR
  // ============================================================

  Widget _buildBottomBar(
    double total,
    bool hasItems,
  ) {
    return SafeArea(
      minimum:
          const EdgeInsets.all(
        16,
      ),
      child:
          Row(
        children: [
          Expanded(
            child:
                OutlinedButton.icon(
              onPressed:
                  hasItems
                      ? widget
                          .onClear
                      : null,
              icon:
                  const Icon(
                Icons
                    .remove_shopping_cart_outlined,
              ),
              label:
                  const Text(
                'Vaciar',
              ),
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            flex: 2,
            child:
                ElevatedButton.icon(
              onPressed:
                  hasItems &&
                          !_isProcessing
                      ? _processCheckout
                      : null,
              icon:
                  _isProcessing
                      ? const SizedBox(
                          width:
                              20,
                          height:
                              20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                            color:
                                Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons
                              .check_circle_outline,
                        ),
              label:
                  Text(
                _isProcessing
                    ? 'Procesando...'
                    : 'Cobrar \$${total.toStringAsFixed(2)}',
              ),
              style:
                  ElevatedButton
                      .styleFrom(
                backgroundColor:
                    const Color(
                  0xFF9AC53B,
                ),
                foregroundColor:
                    Colors.white,
                minimumSize:
                    const Size(
                  double.infinity,
                  48,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROCESAR CHECKOUT
  // ============================================================

  Future<void> _processCheckout() async {
    if (_isProcessing) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    bool success = false;

    try {
      success =
          await widget.onCheckout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Error procesando el cobro: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }

    // ==========================================================
    // SOLO CERRAR SI EL COBRO FUE REALMENTE EXITOSO
    // ==========================================================

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }
}
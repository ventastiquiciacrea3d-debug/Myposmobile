// lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../models/label_print_item.dart';
import '../repositories/product_repository.dart';
import '../providers/label_notifier.dart';
import '../locator.dart';
import '../config/routes.dart';
import './inventory_adjustment_form_screen.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product? _product;
  List<Product> _variations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final productRepo = getIt<ProductRepository>();

      final product = await productRepo.getProductById(
        widget.productId,
        forceApi: false,
      );

      if (product == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Producto no encontrado';
        });
        return;
      }

      List<Product> variations = [];
      if (product.isVariable) {
        variations = await productRepo.getAllVariations(product.id);
      }

      setState(() {
        _product = product;
        _variations = variations;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ProductDetail] Error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error cargando producto: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cargando...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Producto no encontrado',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Producto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadProduct(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Imagen
            _buildImageGallery(),

            // Info principal
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _product!.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SKU: ${_product!.sku}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_product!.barcode != null && _product!.barcode!.isNotEmpty)
                    Text(
                      'Código: ${_product!.barcode}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),

                  const SizedBox(height: 16),

                  // Precio
                  Row(
                    children: [
                      if (_product!.onSale && _product!.regularPrice != null) ...[
                        Text(
                          currencyFormat.format(_product!.regularPrice),
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey[500],
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        currencyFormat.format(_product!.price),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _product!.onSale
                              ? Colors.red[700]
                              : Colors.black87,
                        ),
                      ),
                      if (_product!.onSale)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(
                            label: const Text('EN OFERTA'),
                            backgroundColor: Colors.red[100],
                            labelStyle: TextStyle(
                              color: Colors.red[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),

                  // Stock
                  ListTile(
                    leading: Icon(
                      Icons.inventory_2_outlined,
                      color: _getStockColor(_product!),
                    ),
                    title: const Text('Stock disponible'),
                    trailing: Text(
                      _product!.manageStock
                          ? '${_product!.stockQuantity ?? 0} unidades'
                          : 'No gestionado',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getStockColor(_product!),
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Estado'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStockStatusColor(_product!).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getStockStatusText(_product!),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getStockStatusColor(_product!),
                        ),
                      ),
                    ),
                  ),

                  // Categorías
                  if (_product!.categoryNames != null &&
                      _product!.categoryNames!.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Categorías',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _product!.categoryNames!.map((cat) =>
                        Chip(
                          label: Text(cat),
                          backgroundColor: Colors.blue[50],
                        ),
                      ).toList(),
                    ),
                  ],

                  // Variaciones
                  if (_product!.isVariable && _variations.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Variaciones (${_variations.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._variations.map((variation) =>
                      Card(
                        child: ListTile(
                          title: Text(variation.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Stock: ${variation.stockQuantity ?? 0}'),
                              if (variation.attributes != null && variation.attributes!.isNotEmpty)
                                Text(
                                  variation.attributes!
                                      .map((attr) => '${attr['name']}: ${attr['option']}')
                                      .join(', '),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                            ],
                          ),
                          trailing: Text(
                            currencyFormat.format(variation.price),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Descripción
                  if (_product!.description != null &&
                      _product!.description!.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Descripción',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_product!.description!),
                  ],

                  const SizedBox(height: 80), // Espacio para bottom bar
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildImageGallery() {
    if (_product!.imageUrls.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey[200],
        child: Icon(
          Icons.inventory_2,
          size: 64,
          color: Colors.grey[400],
        ),
      );
    }

    if (_product!.imageUrls.length == 1) {
      return Container(
        height: 300,
        child: CachedNetworkImage(
          imageUrl: _product!.imageUrls.first,
          fit: BoxFit.contain,
          placeholder: (c, u) => const Center(
            child: CircularProgressIndicator(),
          ),
          errorWidget: (c, u, e) => const Icon(
            Icons.broken_image,
            size: 64,
          ),
        ),
      );
    }

    return SizedBox(
      height: 300,
      child: PageView.builder(
        itemCount: _product!.imageUrls.length,
        itemBuilder: (context, index) {
          return CachedNetworkImage(
            imageUrl: _product!.imageUrls[index],
            fit: BoxFit.contain,
            placeholder: (c, u) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (c, u, e) => const Icon(
              Icons.broken_image,
              size: 64,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.inventory_outlined),
              label: const Text('AJUSTE'),
              onPressed: () => _navigateToInventoryAdjustment(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('PEDIDO'),
              onPressed: () => _addToOrder(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.local_offer),
              label: const Text('ETIQUETA'),
              onPressed: () => _addToLabelQueue(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStockColor(Product product) {
    if (!product.manageStock) return Colors.grey[600]!;
    final stock = product.stockQuantity ?? 0;
    if (stock > 10) return Colors.green[700]!;
    if (stock > 0) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  Color _getStockStatusColor(Product product) {
    final status = product.stockStatus ?? 'instock';
    switch (status) {
      case 'instock':
        return Colors.green[700]!;
      case 'outofstock':
        return Colors.red[700]!;
      case 'onbackorder':
        return Colors.orange[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  String _getStockStatusText(Product product) {
    final status = product.stockStatus ?? 'instock';
    switch (status) {
      case 'instock':
        return 'DISPONIBLE';
      case 'outofstock':
        return 'AGOTADO';
      case 'onbackorder':
        return 'BAJO PEDIDO';
      default:
        return 'N/A';
    }
  }

  void _navigateToInventoryAdjustment() {
    Navigator.pushNamed(
      context,
      Routes.inventoryAdjustmentForm,
      arguments: InventoryAdjustmentFormScreenArguments(
        operationType: 'entry',
        initialProduct: _product,
      ),
    );
  }

  void _addToOrder() {
    // TODO: Integrar con OrderNotifier
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${_product!.name} agregado al pedido'),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _addToLabelQueue() {
    try {
      final labelItem = LabelPrintItem(
        productId: _product!.id,
        quantity: 1,
        selectedVariants: const {},
        barcode: _product!.barcode,
        cachedProductName: _product!.name,
        cachedSku: _product!.sku,
      );

      ref.read(labelProvider.notifier).addOrUpdateItem(labelItem);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${_product!.name} agregado a cola de impresión'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }
}

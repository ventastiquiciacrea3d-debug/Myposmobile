// lib/widgets/catalog/product_catalog_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../models/product.dart';

class ProductCatalogCard extends StatelessWidget {
  final Product product;
  final List<Product> variations;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onTap;
  final VoidCallback onAdjustInventory;
  final VoidCallback onAddToOrder;
  final VoidCallback onPrintLabel;
  final VoidCallback onEditCategories;

  const ProductCatalogCard({
    super.key,
    required this.product,
    required this.variations,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onTap,
    required this.onAdjustInventory,
    required this.onAddToOrder,
    required this.onPrintLabel,
    required this.onEditCategories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡', decimalDigits: 0);

    return Slidable(
      key: ValueKey('slidable_${product.id}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.6,
        children: [
          SlidableAction(
            onPressed: (_) => onAdjustInventory(),
            backgroundColor: Colors.blue[700]!,
            foregroundColor: Colors.white,
            icon: Icons.inventory_outlined,
            label: 'Ajuste',
          ),
          SlidableAction(
            onPressed: (_) => onAddToOrder(),
            backgroundColor: Colors.green[700]!,
            foregroundColor: Colors.white,
            icon: Icons.add_shopping_cart_outlined,
            label: 'Pedido',
          ),
          SlidableAction(
            onPressed: (_) => onPrintLabel(),
            backgroundColor: Colors.orange[700]!,
            foregroundColor: Colors.white,
            icon: Icons.local_offer_outlined,
            label: 'Etiqueta',
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // ROW PRINCIPAL
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Imagen
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[200],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: product.displayImageUrl != null && product.displayImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.displayImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (c, u, e) => Icon(
                              Icons.inventory_2,
                              color: Colors.grey[400],
                              size: 32,
                            ),
                          )
                        : Icon(
                            Icons.inventory_2,
                            color: Colors.grey[400],
                            size: 32,
                          ),
                  ),

                  const SizedBox(width: 12),

                  // Info principal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SKU: ${product.sku.isNotEmpty ? product.sku : 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (product.barcode != null && product.barcode!.isNotEmpty)
                          Text(
                            'Código: ${product.barcode}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Precio
                        Row(
                          children: [
                            if (product.onSale && product.regularPrice != null) ...[
                              Text(
                                currencyFormat.format(product.regularPrice),
                                style: TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              currencyFormat.format(product.price),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: product.onSale
                                    ? Colors.red[700]
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Botones de acción en la esquina superior derecha
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón de categorías
                      IconButton(
                        icon: const Icon(Icons.category_outlined, size: 20),
                        color: Colors.purple[700],
                        onPressed: onEditCategories,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Categorías',
                      ),
                      // Icono expandir si es variable
                      if (product.isVariable && variations.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 20,
                          ),
                          onPressed: onToggleExpanded,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ROW DE STOCK
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Stock
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: _getStockColor(product),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        product.manageStock
                            ? 'Stock: ${product.stockQuantity ?? 0}'
                            : 'Stock no gestionado',
                        style: TextStyle(
                          fontSize: 13,
                          color: _getStockColor(product),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Badge de estado
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStockStatusColor(product).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStockStatusColor(product).withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      _getStockStatusText(product),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getStockStatusColor(product),
                      ),
                    ),
                  ),
                ],
              ),

              // Variaciones expandidas
              if (isExpanded && product.isVariable && variations.isNotEmpty)
                _buildVariationsList(variations, currencyFormat, theme),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildVariationsList(
    List<Product> variations,
    NumberFormat currencyFormat,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Variaciones (${variations.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Divider(height: 1),
          ...variations.map((variation) =>
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: _getStockColor(variation).withOpacity(0.2),
                child: Icon(
                  Icons.label_outline,
                  size: 16,
                  color: _getStockColor(variation),
                ),
              ),
              title: Text(
                variation.name,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock: ${variation.stockQuantity ?? 0}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  if (variation.attributes != null && variation.attributes!.isNotEmpty)
                    Text(
                      variation.attributes!
                          .map((attr) => '${attr['name']}: ${attr['option']}')
                          .join(', '),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: Text(
                currencyFormat.format(variation.price),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
}

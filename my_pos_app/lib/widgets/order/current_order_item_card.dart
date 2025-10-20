// lib/widgets/order/current_order_item_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart' show OrderItem;
import '../../providers/order_provider.dart';
import '../../widgets/quantity_selector.dart';

class CurrentOrderItemCard extends StatelessWidget {
  final OrderItem item;
  final NumberFormat currencyFormat;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final Function(OrderItem item) onShowVariantsModal;
  final Function(OrderItem item) onShowDiscountModal;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const CurrentOrderItemCard({
    Key? key,
    required this.item,
    required this.currencyFormat,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onShowVariantsModal,
    required this.onShowDiscountModal,
    required this.onDuplicate,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderProvider = context.read<OrderProvider>();

    final bool isVariableProduct = item.productType == 'variation' || item.productType == 'variable';
    final String displayedName = item.name;

    final String currentAttributeDisplay = item.attributes
        ?.where((attr) => (attr['name'] != null && attr['name']!.isNotEmpty) && (attr['option'] != null && attr['option']!.isNotEmpty))
        .map((attr) => attr['option'])
        .join(' / ') ??
        (item.isVariation ? "Configurar Variantes" : "");

    final double effectivePrice = item.price;
    final double? regularPrice = item.regularPrice;
    final bool onSale = regularPrice != null && effectivePrice < regularPrice && (regularPrice - effectivePrice).abs() > 0.01;

    final double lineSubtotalBeforeManualDiscount = effectivePrice * item.quantity;
    final double lineTotalAfterIndividualDiscount = lineSubtotalBeforeManualDiscount - (item.individualDiscount ?? 0.0);

    final String itemSku = item.sku;
    final bool manageStock = item.manageStock;
    final int? stockQuantity = item.stockQuantity;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggleExpand,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayedName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isVariableProduct)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: InkWell(
                              onTap: () => onShowVariantsModal(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        currentAttributeDisplay.isNotEmpty ? currentAttributeDisplay : 'Seleccionar Opciones',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade700),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    currencyFormat.format(lineTotalAfterIndividualDiscount),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.primaryColor),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const Divider(height: 24, thickness: 0.8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Precio Und.:", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    Row(
                      children: [
                        if (onSale && regularPrice != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              currencyFormat.format(regularPrice),
                              style: TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Text(
                          currencyFormat.format(effectivePrice),
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: onSale ? theme.colorScheme.error : theme.textTheme.bodyLarge?.color),
                        ),
                      ],
                    )
                  ],
                ),
                if ((item.individualDiscount ?? 0) > 0.01)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Descuento:", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        Text("-${currencyFormat.format(item.individualDiscount)}", style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    QuantitySelector(
                      key: ValueKey('qty_selector_${item.productId}_${item.variationId ?? ''}'),
                      value: item.quantity,
                      minValue: 0,
                      maxValue: (manageStock && stockQuantity != null && stockQuantity >= 0)
                          ? stockQuantity + item.quantity
                          : 9999,
                      onChanged: (newQuantity) {
                        final itemUniqueIdForProvider = item.isVariation ? '${item.productId}_${item.variationId!}' : item.productId;
                        if (newQuantity == 0) {
                          orderProvider.removeItem(itemUniqueIdForProvider);
                        } else {
                          orderProvider.updateItemQuantity(itemUniqueIdForProvider, newQuantity);
                        }
                      },
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => onShowDiscountModal(item),
                          child: const Text("Dcto."),
                        ),
                        TextButton(
                          onPressed: onDuplicate,
                          child: const Text("Duplicar"),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
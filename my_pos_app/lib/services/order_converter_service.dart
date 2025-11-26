// lib/services/order_converter_service.dart
import 'dart:convert';
import '../models/order.dart';
import '../models/order_compact.dart';

/// Servicio para convertir entre Order (legacy Hive) y OrderCompact (ObjectBox)
class OrderConverterService {
  /// Convertir Order (Hive) a OrderCompact (ObjectBox)
  OrderCompact orderToCompact(Order order) {
    // Generar localOrderId único
    final localOrderId = order.id ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

    // Parsear order ID de WooCommerce
    final int? orderId = order.id != null && !order.id!.startsWith('local_')
        ? int.tryParse(order.id!)
        : null;

    // Parsear customer ID
    final int? customerId = order.customerId != null
        ? int.tryParse(order.customerId!)
        : null;

    // Convertir items a JSON comprimido
    final List<Map<String, dynamic>> itemsJsonList = order.items.map((item) {
      // Convertir List<Map<String, String>>? a Map<String, String>?
      Map<String, String>? attributesMap;
      if (item.attributes != null && item.attributes!.isNotEmpty) {
        attributesMap = {};
        for (final attr in item.attributes!) {
          final name = attr['name'] ?? attr['key'];
          final value = attr['value'] ?? attr['option'];
          if (name != null && value != null) {
            attributesMap[name] = value;
          }
        }
      }

      return OrderItemCompact(
        productId: int.tryParse(item.productId) ?? 0,
        variationId: item.variationId,
        name: _truncate(item.name, 100),
        sku: _truncate(item.sku, 20),
        quantity: item.quantity,
        priceInCents: (item.price * 100).round(),
        subtotalInCents: (item.subtotal * 100).round(),
        regularPriceInCents: item.regularPrice != null ? (item.regularPrice! * 100).round() : null,
        individualDiscountInCents: item.individualDiscount != null ? (item.individualDiscount! * 100).round() : null,
        productType: item.productType ?? 'simple',
        attributes: attributesMap,
      ).toJson();
    }).toList();

    final String itemsJson = json.encode(itemsJsonList);

    // Convertir totales a centavos
    final int subtotalInCents = (order.subtotal * 100).round();
    final int taxInCents = (order.tax * 100).round();
    final int discountInCents = (order.discount * 100).round();
    final int totalInCents = (order.total * 100).round();

    // Parse order status
    final int orderStatusCode = OrderCompact.parseOrderStatus(order.orderStatus);

    // Flags
    int flags = 0;
    if (order.isSynced) flags |= 0x01;
    // Bit 1: isPaid - no tenemos en Order original, se puede agregar después

    return OrderCompact(
      localOrderId: localOrderId,
      orderId: orderId,
      customerId: customerId,
      orderNumber: order.number,
      customerName: _truncate(order.customerName, 50),
      itemsJson: itemsJson,
      subtotalInCents: subtotalInCents,
      taxInCents: taxInCents,
      discountInCents: discountInCents,
      totalInCents: totalInCents,
      date: order.date,
      orderStatusCode: orderStatusCode,
      flags: flags,
    );
  }

  /// Convertir OrderCompact (ObjectBox) a Order (Hive)
  Order compactToOrder(OrderCompact compact) {
    // Convertir items de JSON
    final List<OrderItem> items = compact.items.map((compactItem) {
      // Convertir Map<String, String>? a List<Map<String, String>>?
      List<Map<String, String>>? attributesList;
      if (compactItem.attributes != null && compactItem.attributes!.isNotEmpty) {
        attributesList = compactItem.attributes!.entries
            .map((e) => {'name': e.key, 'option': e.value})
            .toList();
      }

      return OrderItem(
        productId: compactItem.productId.toString(),
        variationId: compactItem.variationId,
        name: compactItem.name,
        sku: compactItem.sku,
        quantity: compactItem.quantity,
        price: compactItem.price,
        subtotal: compactItem.subtotal,
        regularPrice: compactItem.regularPrice,
        individualDiscount: compactItem.individualDiscount,
        productType: compactItem.productType,
        attributes: attributesList,
      );
    }).toList();

    return Order(
      id: compact.orderId?.toString() ?? compact.localOrderId,
      number: compact.orderNumber,
      customerId: compact.customerId?.toString(),
      customerName: compact.customerName,
      items: items,
      subtotal: compact.subtotal,
      tax: compact.tax,
      discount: compact.discount,
      total: compact.total,
      date: compact.date,
      orderStatus: compact.orderStatus,
      isSynced: compact.isSynced,
    );
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength);
  }
}

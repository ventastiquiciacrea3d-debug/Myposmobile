// lib/models/order_compact.dart
import 'package:objectbox/objectbox.dart';
import 'dart:convert';

/// Order Compacto para ObjectBox: ~150 bytes
///
/// Reducción de ~800 bytes (Hive) → 150 bytes (ObjectBox)
/// 1,000 órdenes: 800 KB → 150 KB (81% menos espacio)
@Entity()
class OrderCompact {
  // ObjectBox ID (auto-increment)
  @Id()
  int localId = 0;

  // ==================== IDs (14 bytes) ====================

  /// Order ID de WooCommerce (puede ser 0 si es local)
  @Index()
  int? orderId;

  /// Local ID (para órdenes pendientes de sincronizar)
  @Index()
  @Unique()
  String localOrderId;

  /// Customer ID
  int? customerId;

  // ==================== STRINGS (100 bytes) ====================

  /// Número de orden WooCommerce
  @Index()
  String? orderNumber;

  /// Nombre del cliente (max 50 chars)
  String customerName;

  // ==================== LINE ITEMS (JSON comprimido) ====================

  /// Items del pedido en formato JSON comprimido
  /// [{"pid":123,"vid":456,"q":2,"p":2999}]
  String itemsJson;

  // ==================== TOTALES (16 bytes) ====================

  /// Subtotal en centavos
  int subtotalInCents;

  /// Tax en centavos
  int taxInCents;

  /// Discount en centavos
  int discountInCents;

  /// Total en centavos
  int totalInCents;

  // ==================== METADATA (12 bytes) ====================

  /// Fecha de creación
  @Property(type: PropertyType.date)
  DateTime date;

  /// Estado de orden: 0=pending, 1=processing, 2=completed, 3=cancelled, 4=failed
  int orderStatusCode;

  /// Flags (8 bits)
  /// Bit 0: isSynced
  /// Bit 1: isPaid
  /// Bit 2-7: Reservados
  int flags;

  // ==================== CONSTRUCTOR ====================

  OrderCompact({
    required this.localOrderId,
    this.orderId,
    this.customerId,
    this.orderNumber,
    required this.customerName,
    required this.itemsJson,
    required this.subtotalInCents,
    required this.taxInCents,
    required this.discountInCents,
    required this.totalInCents,
    required this.date,
    required this.orderStatusCode,
    required this.flags,
  });

  // ==================== GETTERS HELPERS ====================

  double get subtotal => subtotalInCents / 100.0;
  double get tax => taxInCents / 100.0;
  double get discount => discountInCents / 100.0;
  double get total => totalInCents / 100.0;

  bool get isSynced => (flags & 0x01) != 0;
  bool get isPaid => (flags & 0x02) != 0;

  String get orderStatus {
    switch (orderStatusCode) {
      case 0:
        return 'pending';
      case 1:
        return 'processing';
      case 2:
        return 'completed';
      case 3:
        return 'cancelled';
      case 4:
        return 'failed';
      default:
        return 'pending';
    }
  }

  List<OrderItemCompact> get items {
    try {
      final List<dynamic> jsonList = json.decode(itemsJson);
      return jsonList.map((j) => OrderItemCompact.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  // ==================== SETTERS HELPERS ====================

  set isSynced(bool value) {
    if (value) {
      flags |= 0x01;
    } else {
      flags &= ~0x01;
    }
  }

  set isPaid(bool value) {
    if (value) {
      flags |= 0x02;
    } else {
      flags &= ~0x02;
    }
  }

  static int parseOrderStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 0;
      case 'processing':
        return 1;
      case 'completed':
        return 2;
      case 'cancelled':
        return 3;
      case 'failed':
        return 4;
      default:
        return 0;
    }
  }

  // ==================== TO STRING ====================

  @override
  String toString() {
    return 'OrderCompact(id: ${orderId ?? localOrderId}, customer: $customerName, total: \$$total, status: $orderStatus)';
  }
}

/// OrderItem Compacto (solo en JSON, no es entidad separada)
class OrderItemCompact {
  final int productId;
  final int? variationId;
  final String name;
  final String sku;
  final int quantity;
  final int priceInCents;
  final int subtotalInCents;
  final int? regularPriceInCents;
  final int? individualDiscountInCents;
  final String productType;
  final Map<String, String>? attributes;

  OrderItemCompact({
    required this.productId,
    this.variationId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.priceInCents,
    required this.subtotalInCents,
    this.regularPriceInCents,
    this.individualDiscountInCents,
    required this.productType,
    this.attributes,
  });

  double get price => priceInCents / 100.0;
  double get subtotal => subtotalInCents / 100.0;
  double? get regularPrice =>
      regularPriceInCents != null ? regularPriceInCents! / 100.0 : null;
  double? get individualDiscount => individualDiscountInCents != null
      ? individualDiscountInCents! / 100.0
      : null;

  // Formato JSON comprimido: {"pid":123,"vid":456,"n":"Producto","s":"SKU123","q":2,"p":2999,"st":5998,"rp":3999,"d":0,"t":"variation","a":{"color":"rojo"}}
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'pid': productId,
      'n': name,
      's': sku,
      'q': quantity,
      'p': priceInCents,
      'st': subtotalInCents,
      't': productType,
    };

    if (variationId != null) json['vid'] = variationId;
    if (regularPriceInCents != null) json['rp'] = regularPriceInCents;
    if (individualDiscountInCents != null && individualDiscountInCents! > 0) {
      json['d'] = individualDiscountInCents;
    }
    if (attributes != null && attributes!.isNotEmpty) {
      json['a'] = attributes;
    }

    return json;
  }

  factory OrderItemCompact.fromJson(Map<String, dynamic> json) {
    return OrderItemCompact(
      productId: json['pid'] as int,
      variationId: json['vid'] as int?,
      name: json['n'] as String,
      sku: json['s'] as String,
      quantity: json['q'] as int,
      priceInCents: json['p'] as int,
      subtotalInCents: json['st'] as int,
      regularPriceInCents: json['rp'] as int?,
      individualDiscountInCents: json['d'] as int?,
      productType: json['t'] as String? ?? 'simple',
      attributes: json['a'] != null
          ? Map<String, String>.from(json['a'] as Map)
          : null,
    );
  }

  @override
  String toString() {
    return 'OrderItemCompact(name: $name, sku: $sku, qty: $quantity, price: \$$price)';
  }
}

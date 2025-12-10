// lib/models/order_item.dart
import 'package:hive/hive.dart';
import 'product.dart';

part 'order_item.g.dart';

@HiveType(typeId: 13)
class OrderItem extends HiveObject {
  @HiveField(0)
  final String productId;

  @HiveField(1)
  final String? variationId;

  @HiveField(2)
  final String productName;

  @HiveField(3)
  final String sku;

  @HiveField(4)
  int quantity;

  @HiveField(5)
  double price;

  @HiveField(6)
  double discount;

  @HiveField(7)
  String discountType;

  @HiveField(8)
  double subtotal;

  @HiveField(9)
  Map<String, String> attributes;

  @HiveField(10)
  Map<String, dynamic>? availableAttributes;

  @HiveField(11)
  List<Map<String, dynamic>>? availableVariations;

  OrderItem({
    required this.productId,
    this.variationId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.price,
    this.discount = 0,
    this.discountType = 'fixed',
    required this.subtotal,
    this.attributes = const {},
    this.availableAttributes,
    this.availableVariations,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'variation_id': variationId,
    'name': productName,
    'sku': sku,
    'quantity': quantity,
    'price': price,
    'discount': discount,
    'discount_type': discountType,
    'subtotal': subtotal,
    'attributes': attributes,
    'available_attributes': availableAttributes,
    'available_variations': availableVariations,
  };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['product_id'].toString(),
    variationId: json['variation_id']?.toString(),
    productName: json['name'] ?? '',
    sku: json['sku'] ?? '',
    quantity: json['quantity'] ?? 1,
    price: (json['price'] ?? 0).toDouble(),
    discount: (json['discount'] ?? 0).toDouble(),
    discountType: json['discount_type'] ?? 'fixed',
    subtotal: (json['subtotal'] ?? 0).toDouble(),
    attributes: json['attributes'] != null
        ? Map<String, String>.from(json['attributes'])
        : {},
    availableAttributes: json['available_attributes'] != null
        ? Map<String, dynamic>.from(json['available_attributes'])
        : null,
    availableVariations: json['available_variations'] != null
        ? (json['available_variations'] as List).map((v) => Map<String, dynamic>.from(v)).toList()
        : null,
  );

  factory OrderItem.fromProduct(Product product, {int quantity = 1, Map<String, String>? selectedAttributes}) {
    final double itemPrice = product.price;
    return OrderItem(
      productId: product.id,
      variationId: product.type == 'variation' ? product.id : null,
      productName: product.name,
      sku: product.sku,
      quantity: quantity,
      price: itemPrice,
      subtotal: itemPrice * quantity,
      attributes: selectedAttributes ?? {},
      // ⚠️ NOTA: fullAttributesWithOptions es List<Map>, no Map - incompatible con availableAttributes
      // TODO: Refactorizar modelo para soportar List<Map> o convertir estructura
      availableAttributes: null,
    );
  }

  void calculateSubtotal() {
    double itemSubtotal = price * quantity;
    double itemDiscount = 0;

    if (discountType == 'percent') {
      itemDiscount = itemSubtotal * (discount / 100);
    } else {
      itemDiscount = discount * quantity;
    }

    subtotal = itemSubtotal - itemDiscount;
  }
}

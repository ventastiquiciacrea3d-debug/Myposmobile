// lib/models/order.dart
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import 'package:collection/collection.dart'; // Para firstWhereOrNull

part 'order.g.dart';

// --- Order Class Definition ---
@HiveType(typeId: 1)
class Order extends HiveObject {
  @HiveField(0) final String? id; // Puede ser null para pedidos nuevos locales
  @HiveField(1) final String? number; // Número de pedido de WC
  @HiveField(2) final String? customerId;
  @HiveField(3) final String customerName;
  @HiveField(4) final List<OrderItem> items;
  @HiveField(5) final double subtotal; // Subtotal base (suma de regular_price * qty)
  @HiveField(6) final double tax; // Impuesto total calculado
  @HiveField(7) final double discount; // Descuento total a nivel de pedido (WC discount_total, usualmente cupones)
  // O, si se recalcula en el provider, puede ser la suma de descuentos de oferta de productos.
  @HiveField(8) final double total; // Total final del pedido
  @HiveField(9) final DateTime date;
  @HiveField(10) final String orderStatus;
  @HiveField(11) final bool isSynced; // True si el pedido está sincronizado/existe en el servidor

  Order({
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.discount, // Descuento a nivel de pedido
    required this.total,
    required this.date,
    required this.orderStatus,
    required this.isSynced,
    this.id,
    this.number,
    this.customerId,
    required this.customerName,
  });

  String? get orderNumber => number;
  String get status => orderStatus;

  Order copyWith({
    String? id,
    String? number,
    String? customerId, // Hacer nullable
    String? customerName,
    List<OrderItem>? items,
    double? subtotal,
    double? tax,
    double? discount,
    double? total,
    DateTime? date,
    String? orderStatus,
    bool? isSynced,
  }) {
    return Order(
      id: id ?? this.id,
      number: number ?? this.number,
      customerId: customerId ?? this.customerId, // Mantener el original si no se pasa
      customerName: customerName ?? this.customerName,
      items: items ?? List<OrderItem>.from(this.items.map((item) => item.copyWith())),
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      date: date ?? this.date,
      orderStatus: orderStatus ?? this.orderStatus,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final idLog = json['id']?.toString() ?? json['local_id_ref']?.toString() ?? 'N/A';
    // Nombre del cliente
    String fn = json['billing']?['first_name']?.toString() ?? '';
    String ln = json['billing']?['last_name']?.toString() ?? '';
    String name = '${fn} ${ln}'.trim();
    String customer = json['customerName'] ?? (name.isEmpty ? 'Cliente General' : name);

    // Fecha del pedido
    DateTime dt = DateTime.now(); // Fallback
    final dateString = json['date'] ?? json['date_created_gmt'] ?? json['date_created'];
    if (dateString != null && dateString is String) {
      try {
        // Intentar parsear como UTC si termina en Z, sino como local.
        dt = dateString.endsWith('Z') ? DateTime.parse(dateString).toLocal() : DateTime.parse(dateString);
      } catch (_) {
        if (kDebugMode) {
          print("Error parsing date: $dateString for order $idLog");
        }
      }
    }

    // Items del pedido
    List<OrderItem> parsedItems = [];
    final itemsList = json['line_items'];
    if (itemsList is List) {
      for (var itemJson in itemsList) {
        if (itemJson is Map<String, dynamic>) {
          try {
            parsedItems.add(OrderItem.fromJson(itemJson));
          } catch (e, s) {
            if (kDebugMode) {
              print("ERROR OrderItem.fromJson for order ID ${json['id']}: $e\n$s\nItem JSON: $itemJson");
            }
          }
        }
      }
    }

    // Helper para parsear doubles de forma segura
    double pDouble(dynamic val, double def) {
      if (val == null) return def;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? def;
      return def;
    }

    // Totales del pedido
    // 'subtotal' en la API de WC suele ser la suma de precios de línea ANTES de cupones.
    // 'total' es el final después de impuestos y descuentos (incluyendo cupones).
    // 'discount_total' es el descuento por cupones a nivel de pedido.
    // 'total_tax' es el impuesto total.
    // La app calcula el subtotal base (suma de regular_price * qty) y el descuento por ofertas de productos.
    // El OrderProvider.recalculateTotals es quien realmente calcula y ajusta estos valores para la app.
    // Aquí, tomamos los valores de la API como referencia.
    return Order(
      id: json['id']?.toString() ?? json['local_id_ref']?.toString(),
      number: json['number']?.toString() ?? json['number_ref']?.toString(),
      customerId: json['customer_id']?.toString(),
      customerName: customer,
      items: parsedItems,
      subtotal: pDouble(json['subtotal'], 0.0), // Este es el subtotal de WC
      tax: pDouble(json['total_tax'], 0.0),
      discount: pDouble(json['discount_total'], 0.0), // Descuento de cupón de WC
      total: pDouble(json['total'], 0.0),
      date: dt,
      orderStatus: json['status']?.toString() ?? json['orderStatus']?.toString() ?? 'pending',
      isSynced: json['isSynced'] as bool? ?? (json['id'] != null && json['id'].toString().isNotEmpty && !json['id'].toString().startsWith('local_')),
    );
  }

  // Convertir a JSON para enviar a la API
  Map<String, dynamic> toJson({bool forUpdate = false}) {
    Map<String, dynamic> jsonMap = {};

    if (forUpdate) { // Para actualizar un pedido existente (ej. solo estado)
      jsonMap['status'] = orderStatus;
      // Se podrían añadir más campos si la API permite actualizarlos (ej. line_items, customer_id)
      // Si se actualizan line_items, se debe enviar el 'id' de la línea de ítem si existe.
    } else { // Para crear un nuevo pedido
      // Establecer customer_id si es un cliente registrado
      if (customerId != null && customerId!.isNotEmpty && customerId != '0' && !customerId!.startsWith('local_')) {
        jsonMap['customer_id'] = int.tryParse(customerId!) ?? 0;
      }
      // Información de facturación y envío (a menudo la misma para POS)
      jsonMap['billing'] = {
        'first_name': customerName.split(' ').first,
        'last_name': customerName.split(' ').length > 1 ? customerName.split(' ').sublist(1).join(' ') : '',
        // 'email': 'customer@example.com', // Podría ser necesario un email para billing
        // 'phone': '12345678',
      };
      jsonMap['shipping'] = { // Puede ser igual que billing
        'first_name': customerName.split(' ').first,
        'last_name': customerName.split(' ').length > 1 ? customerName.split(' ').sublist(1).join(' ') : '',
      };
      jsonMap['line_items'] = items.map((i) => i.toJson(forUpdate: false)).toList();
      jsonMap['status'] = orderStatus.isNotEmpty ? orderStatus : 'pending'; // Estado inicial
      // Meta data opcional
      jsonMap['meta_data'] = [
        {'key': '_order_origin', 'value': 'Aplicación Móvil POS'}
      ];
      // Nota: Los precios, impuestos y totales son usualmente recalculados por WooCommerce
      // al crear el pedido, basándose en los productos y la configuración de la tienda.
      // No es común enviar 'total', 'subtotal', 'tax' al crear.
    }
    return jsonMap;
  }
}

@HiveType(typeId: 2)
class OrderItem extends HiveObject {
  @HiveField(0) final String productId; // ID del producto padre (incluso para variaciones)
  @HiveField(1) final String name; // Nombre del producto o variante específica
  @HiveField(2) final String sku;
  @HiveField(3) final int quantity;
  @HiveField(4) final double price; // Precio unitario efectivo (con descuento de oferta si aplica, ANTES de descuento manual de línea)
  @HiveField(5) final double subtotal; // Subtotal de la línea (price * quantity, ANTES de descuento manual de línea)
  @HiveField(6) final int? variationId; // ID de la variación si es una variación
  @HiveField(7) final List<Map<String, String>>? attributes; // Atributos seleccionados para la variante
  @HiveField(8) final double? individualDiscount; // Descuento manual aplicado a ESTA línea
  @HiveField(9) final double? regularPrice; // Precio regular del producto/variante
  @HiveField(10) final int? lineItemId; // ID de la línea de ítem en WooCommerce (si el pedido ya existe en WC)
  @HiveField(11) final String productType; // 'simple' o 'variation'

  // Campos no persistidos en Hive directamente por este adaptador,
  // pero útiles en la lógica de la app. Se inicializan en el constructor/fromJson.
  final bool manageStock;
  final int? stockQuantity;

  // Getters computados
  // Subtotal efectivo después de descuento individual
  double get effectiveSubtotal => subtotal - (individualDiscount ?? 0.0);
  // Precio efectivo por unidad después de descuento individual
  double get effectivePrice => quantity > 0 ? effectiveSubtotal / quantity : price;
  // Precio base para mostrar (regular_price si existe y es diferente, sino price)
  double get basePrice => regularPrice ?? price;
  String get productName => name;
  bool get isVariation => productType == 'variation' && variationId != null && variationId! > 0;


  OrderItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.price, // Este es el precio de WC (puede ser de oferta)
    required this.subtotal, // price * quantity
    this.variationId,
    this.attributes,
    this.individualDiscount,
    this.regularPrice, // Precio original antes de ofertas de WC
    this.lineItemId,
    required this.productType,
    this.manageStock = false, // Valor por defecto
    this.stockQuantity,     // Valor por defecto
  });

  OrderItem copyWith({
    String? productId,
    String? name,
    String? sku,
    int? quantity,
    double? price,
    double? subtotal,
    int? variationId, // Hacer nullable
    List<Map<String, String>>? attributes, // Hacer nullable
    ValueGetter<double?>? individualDiscount, // Usar ValueGetter para permitir null
    ValueGetter<double?>? regularPrice, // Usar ValueGetter
    ValueGetter<int?>? lineItemId, // Usar ValueGetter
    String? productType,
    bool? manageStock,
    ValueGetter<int?>? stockQuantity, // Usar ValueGetter
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      subtotal: subtotal ?? this.subtotal,
      variationId: variationId ?? this.variationId,
      attributes: attributes ?? (this.attributes != null ? List<Map<String, String>>.from(this.attributes!) : null),
      individualDiscount: individualDiscount != null ? individualDiscount() : this.individualDiscount,
      regularPrice: regularPrice != null ? regularPrice() : this.regularPrice,
      lineItemId: lineItemId != null ? lineItemId() : this.lineItemId,
      productType: productType ?? this.productType,
      manageStock: manageStock ?? this.manageStock,
      stockQuantity: stockQuantity != null ? stockQuantity() : this.stockQuantity,
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final int? itemLineId = (json['id'] is num) ? (json['id'] as num).toInt() : null;
    final pId = json['product_id']?.toString() ?? 'unknown_pid';
    // El nombre ('name') en line_items de WC ya suele ser el nombre de la variante si es una.
    final parsedName = json['name'] as String? ?? 'Producto Desconocido';
    final skuApi = json['sku']?.toString() ?? '';
    final qty = (json['quantity'] as num?)?.toInt() ?? 1;

    // 'price' en line_items es el precio unitario al que se vendió (puede ser de oferta).
    // 'subtotal' es (price * quantity) ANTES de impuestos.
    // 'total' es (price * quantity + tax) DESPUÉS de impuestos para esa línea.
    final double priceApi = double.tryParse(json['price']?.toString() ?? '0') ?? 0;
    final double subtotalApi = double.tryParse(json['subtotal']?.toString() ?? '0') ?? (priceApi * qty);
    // No hay un 'regular_price' estándar en line_items. Se podría obtener de meta_data si se guarda al crear el pedido.
    // Para simplificar, si no se envía, se asume que priceApi es el precio base para descuentos manuales.
    final double? regularPriceApi = null; // Placeholder, OrderProvider lo puede rellenar al añadir al carrito

    final vIdNum = json['variation_id'];
    final vId = (vIdNum is num && vIdNum != 0) ? vIdNum.toInt() : null;

    List<Map<String,String>> itemAttrs = [];
    final metaData = json['meta_data'] as List? ?? [];
    for (var meta in metaData) {
      if (meta is Map && meta['display_key'] != null && meta['display_value'] != null && !(meta['display_key']?.toString() ?? '').startsWith('_')) {
        itemAttrs.add({
          'name': meta['display_key'].toString(), // Nombre del atributo (ej. "Color")
          'option': meta['display_value'].toString(), // Opción seleccionada (ej. "Rojo")
          // 'slug' no está directamente aquí, se podría inferir si es necesario, o guardarlo al crear.
        });
      }
    }

    // Para manage_stock y stock_quantity, estos no vienen en line_items estándar de WC.
    // Estos se establecerían al añadir el producto al carrito desde la app, basados en el Product model.
    // Aquí se ponen valores por defecto si vienen de un pedido de la API.
    final bool itemManageStock = false; // Por defecto, ya que no viene de la API de pedidos
    final int? itemStockQuantity = null; // Por defecto

    // Determinar productType
    final String itemProductType = (vId != null && vId > 0) ? 'variation' : 'simple';

    return OrderItem(
      lineItemId: itemLineId,
      productId: pId,
      variationId: vId,
      name: parsedName,
      sku: skuApi,
      quantity: qty,
      price: priceApi, // Precio unitario de WC (puede ser de oferta)
      subtotal: subtotalApi, // subtotal de línea de WC
      attributes: itemAttrs.isNotEmpty ? itemAttrs : null,
      individualDiscount: null, // Descuentos manuales se manejan en la app, no vienen de GET /orders así
      regularPrice: regularPriceApi, // No viene de WC, se establece al añadir
      productType: itemProductType,
      manageStock: itemManageStock, // No viene de WC, se establece al añadir
      stockQuantity: itemStockQuantity, // No viene de WC, se establece al añadir
    );
  }

  Map<String, dynamic> toJson({bool forUpdate = false}) {
    final Map<String, dynamic> data = {};

    if (forUpdate && lineItemId != null && lineItemId! > 0) { // Para actualizar una línea existente en un pedido
      data['id'] = lineItemId;
      data['quantity'] = quantity;
      // No se suele enviar precio al actualizar, WC lo recalcula o mantiene el original.
      // Si se necesita forzar un precio, se podría añadir aquí, pero es menos común.
    } else { // Para crear una nueva línea en un pedido
      data['product_id'] = int.tryParse(productId) ?? 0;
      if (variationId != null && variationId! > 0) {
        data['variation_id'] = variationId;
      }
      data['quantity'] = quantity;
      // Opcional: Enviar el precio al que se añade al carrito. WC puede recalcularlo.
      // data['price'] = price; // Si se envía, asegurar que sea el precio unitario sin descuentos manuales de app.
      // WC se encarga de aplicar precios de oferta si corresponden al producto/variante.

      // Los atributos para la creación de un pedido con variaciones
      // se manejan enviando `variation_id`. WC usa esto para obtener los detalles de la variante.
      // No es usual enviar `meta_data` con atributos para las líneas al crear,
      // a menos que un plugin específico lo requiera o para atributos personalizados no de variante.
      // if (productType == 'variation' && attributes != null && attributes!.isNotEmpty) {
      //   data['meta_data'] = attributes!.map((a) {
      //     String key = a['name']!;
      //     return {'key': key, 'value': a['option']};
      //   }).toList();
      // }

      // El individualDiscount es un concepto de la app.
      // Si WC soportara un campo para descuento de línea (que no sea cupón), se enviaría aquí.
      // Algunos plugins añaden `meta_data` para esto. Ejemplo:
      // if (individualDiscount != null && individualDiscount! > 0) {
      //   if(data['meta_data'] == null) data['meta_data'] = [];
      //   (data['meta_data'] as List).add({'key': '_line_discount_amount', 'value': individualDiscount.toString()});
      // }
    }
    return data;
  }
}

// Extensión simple para capitalizar la primera letra de un String
extension StringExtension on String {
  String capitalizeFirst() {
    if (isEmpty) return '';
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

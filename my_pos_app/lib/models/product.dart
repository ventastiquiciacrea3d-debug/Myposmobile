// lib/models/product.dart
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

part 'product.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String sku;

  @HiveField(3)
  final String type; // 'simple', 'variable', 'variation'

  @HiveField(4)
  final double price;

  @HiveField(5)
  final String? thumbnailUrl;

  @HiveField(6)
  final int? parentId;

  @HiveField(7)
  final String? barcode;

  @HiveField(8)
  final double? regularPrice;

  @HiveField(9)
  final double? salePrice;

  @HiveField(10)
  final bool onSale;

  @HiveField(11)
  final bool manageStock;

  @HiveField(12)
  final int? stockQuantity;

  @HiveField(13)
  final String? stockStatus;

  @HiveField(14)
  final List<String>? categoryNames;

  @HiveField(15)
  final List<Map<String, dynamic>>? attributes; // Atributos de la variación (ej. Color: Rojo)

  @HiveField(16)
  final List<Map<String, dynamic>>? fullAttributesWithOptions; // Atributos configurables del padre (ej. Color: [Rojo, Azul])

  @HiveField(17)
  final List<String> imageUrls;

  @HiveField(18)
  final DateTime? dateModified;

  @HiveField(19)
  final String? description;

  @HiveField(20)
  final String? shortDescription;

  @HiveField(21)
  final List<int>? variations; // IDs de las variaciones hijas

  bool get isSimple => type == 'simple';
  bool get isVariable => type == 'variable';
  bool get isVariation => type == 'variation';

  bool get isAvailable {
    if (manageStock == false && stockStatus == 'onbackorder') return true;
    if (manageStock == false && stockStatus != 'outofstock') return true;
    if (manageStock == true && (stockStatus == 'instock' || stockStatus == 'onbackorder')) return true;
    if (manageStock == true && stockStatus == null && (stockQuantity ?? 0) > 0) return true;
    return false;
  }

  String? get displayImageUrl => thumbnailUrl;
  double get displayPrice => price;
  double get basePriceForDiscount => regularPrice ?? price;

  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.type,
    required this.price,
    this.thumbnailUrl,
    this.parentId,
    this.barcode,
    this.regularPrice,
    this.salePrice,
    this.onSale = false,
    this.manageStock = false,
    this.stockQuantity,
    this.stockStatus,
    this.categoryNames,
    this.attributes,
    this.fullAttributesWithOptions,
    this.imageUrls = const [],
    this.dateModified,
    this.description,
    this.shortDescription,
    this.variations,
  });

  factory Product.fromJson(Map<String, dynamic> json, {String? parentNameForVariation}) {
    if (json['source'] == 'mypos_plugin_v1' || json['source'] == 'mypos_plugin_v1_search') {
      return Product._fromPluginJson(json, parentNameForVariation: parentNameForVariation);
    } else {
      return Product._fromWooCommerceJson(json, parentNameForVariation: parentNameForVariation);
    }
  }

  factory Product._fromPluginJson(Map<String, dynamic> json, {String? parentNameForVariation}) {
    double pDouble(dynamic v, {double d = 0.0}) => (v is num ? v.toDouble() : (v is String ? (double.tryParse(v.replaceAll(',','.')) ?? d) : d));
    bool pBool(dynamic v, {bool d=false}) => (v is bool ? v : (v is String ? (v.toLowerCase()=='true' || v=='1') : (v is num ? v!=0 : d)));

    final String finalType = json['type'] as String? ?? 'simple';
    String? barcodeVal;
    if (json.containsKey('barcode') && json['barcode'] is String && json['barcode'].isNotEmpty) {
      barcodeVal = json['barcode'];
    } else if (json['meta_data'] is List) {
      final meta = (json['meta_data'] as List).firstWhereOrNull( (m) => m is Map && (m['key'] == '_barcode' || m['key'] == 'barcode' || m['key'] == '_mpbm_barcode') && m['value'] != null && m['value'].toString().isNotEmpty );
      if (meta != null) { barcodeVal = meta['value'].toString(); }
    }

    List<String> imageUrls = [];
    if (json['image']?['src'] != null) {
      imageUrls.add(json['image']['src']);
    }

    List<Map<String, dynamic>>? parsedAttributes;
    List<Map<String, dynamic>>? parsedFullAttributesWithOptions;

    final attributesSource = json['attributes'];
    final fullAttributesSource = json['full_attributes_with_options'];

    if (finalType == 'variable') {
      if (fullAttributesSource is List) {
        parsedFullAttributesWithOptions = [];
        for (var attrJson in fullAttributesSource) {
          if (attrJson is Map<String, dynamic>) {
            final List<String> options = (attrJson['options'] as List?)?.map((o) => o.toString()).where((o) => o.isNotEmpty).toList() ?? [];
            if (options.isNotEmpty) {
              parsedFullAttributesWithOptions.add(Map<String, dynamic>.from(attrJson));
            }
          }
        }
        if (parsedFullAttributesWithOptions.isEmpty) parsedFullAttributesWithOptions = null;
      }
      if (attributesSource is List) {
        parsedAttributes = attributesSource.map((e) => Map<String, dynamic>.from(e)).toList();
      }

    } else if (finalType == 'variation') {
      if (attributesSource is List) {
        parsedAttributes = attributesSource.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }


    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Sin Nombre',
      sku: json['sku'] as String? ?? '',
      type: finalType,
      price: pDouble(json['price']),
      regularPrice: json['regular_price'] != null ? pDouble(json['regular_price']) : null,
      salePrice: json['sale_price'] != null ? pDouble(json['sale_price']) : null,
      onSale: pBool(json['on_sale']),
      manageStock: pBool(json['manage_stock']),
      stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
      stockStatus: json['stock_status'] as String?,
      parentId: (json['parent_id'] as num?)?.toInt(),
      barcode: barcodeVal,
      thumbnailUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
      imageUrls: imageUrls,
      attributes: parsedAttributes,
      fullAttributesWithOptions: parsedFullAttributesWithOptions,
      variations: (json['variations'] as List<dynamic>?)?.map((e) => e as int).toList(),
      categoryNames: null,
      dateModified: null,
      description: null,
      shortDescription: null,
    );
  }

  factory Product._fromWooCommerceJson(Map<String, dynamic> json, {String? parentNameForVariation}) {
    double pDouble(dynamic v, {double d = 0.0}) => (v is num ? v.toDouble() : (v is String ? (double.tryParse(v.replaceAll(',','.')) ?? d) : d));
    bool pBool(dynamic v, {bool d=false}) => (v is bool ? v : (v is String ? (v.toLowerCase()=='true' || v=='1') : (v is num ? v!=0 : d)));
    DateTime? pDate(dynamic v) => (v is String && v.isNotEmpty) ? DateTime.tryParse(v)?.toLocal() : null;

    final String idApi = json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    String typeApiFromJson = json['type'] as String? ?? 'simple';
    final int? parentIdFromApi = json['parent_id'] as int?;
    String finalType = typeApiFromJson;
    int? finalParentId = parentIdFromApi;

    if (parentIdFromApi != null && parentIdFromApi > 0) {
      finalType = 'variation';
    } else {
      finalParentId = null;
    }

    String nameApi = json['name'] as String? ?? '';
    final skuApiValue = json['sku'] as String? ?? '';

    bool manageStockEffective = false;
    if (json['manage_stock'] is bool) {
      manageStockEffective = json['manage_stock'];
    } else if (json['manage_stock'] == 'parent' && finalType == 'variation') {
      manageStockEffective = json['stock_quantity'] is num || json['stock_status'] != null;
    } else {
      manageStockEffective = pBool(json['manage_stock']);
    }

    String? stockStatusApiValue = json['stock_status'] as String?;
    final stockQuantityApiValue = json['stock_quantity'] as int?;

    if (manageStockEffective && stockStatusApiValue == null) {
      stockStatusApiValue = (stockQuantityApiValue == null || stockQuantityApiValue <= 0) ? 'outofstock' : 'instock';
    } else if (!manageStockEffective && stockStatusApiValue == null) {
      stockStatusApiValue = 'instock';
    }

    final priceFromApiString = json['price']?.toString() ?? '';
    final regularPriceFromApiString = json['regular_price']?.toString() ?? '';
    final salePriceFromApiString = json['sale_price']?.toString() ?? '';

    double effectivePrice = pDouble(priceFromApiString);
    double? regularPriceValue = regularPriceFromApiString.isNotEmpty ? pDouble(regularPriceFromApiString) : null;
    double? salePriceValue = salePriceFromApiString.isNotEmpty ? pDouble(salePriceFromApiString) : null;

    regularPriceValue ??= effectivePrice;

    final bool onSaleApiValue = pBool(json['on_sale'], d: false) ||
        (salePriceValue != null && regularPriceValue != null && salePriceValue < regularPriceValue && salePriceValue == effectivePrice);

    List<Map<String, dynamic>> parsedAttributesForThisInstance = [];
    List<Map<String, dynamic>> parsedFullAttributesForParentVariable = [];

    if (json['attributes'] is List) {
      for (var attrJson in (json['attributes'] as List)) {
        if (attrJson is Map<String, dynamic>) {
          final String? attrName = attrJson['name']?.toString();
          if (attrName == null || attrName.isEmpty) continue;
          final attrSlug = attrJson['slug']?.toString() ?? attrName.toLowerCase().replaceAll(' ', '-');
          final bool isVariationDefining = pBool(attrJson['variation'], d: false);
          final bool isVisibleOnProductPage = pBool(attrJson['visible'], d: false);
          final List<String> attrOptionsList = (attrJson['options'] as List?)?.map((o) => o?.toString()).whereNotNull().where((o) => o.isNotEmpty).toList() ?? [];

          if (finalType == 'variable') {
            if (isVariationDefining && attrOptionsList.isNotEmpty) {
              parsedFullAttributesForParentVariable.add({ 'name': attrName, 'slug': attrSlug, 'options': attrOptionsList, 'variation': true, 'visible': isVisibleOnProductPage, });
            }
          } else if (finalType == 'variation') {
            final attrOption = attrJson['option']?.toString();
            if (attrOption != null && attrOption.isNotEmpty) {
              parsedAttributesForThisInstance.add({'name': attrName, 'option': attrOption, 'slug': attrSlug});
            }
          } else {
            if (isVisibleOnProductPage && attrOptionsList.isNotEmpty) {
              parsedAttributesForThisInstance.add({ 'name': attrName, 'slug': attrSlug, 'options': attrOptionsList, 'variation': false, 'visible': true, });
            }
          }
        }
      }
    }

    if (finalType == 'variation') {
      String variationSuffix = parsedAttributesForThisInstance.map((a) => a['option']?.toString()).whereNotNull().where((o) => o.isNotEmpty).join(' - ');
      bool needsNameToBuild = nameApi.isEmpty || nameApi.toLowerCase() == "sin nombre" || (parentNameForVariation != null && nameApi == parentNameForVariation);
      if (needsNameToBuild) {
        if (parentNameForVariation != null && parentNameForVariation.isNotEmpty) {
          nameApi = variationSuffix.isNotEmpty ? "$parentNameForVariation - $variationSuffix" : parentNameForVariation;
        } else if (variationSuffix.isNotEmpty) {
          nameApi = variationSuffix;
        } else {
          nameApi = "Variación (ID: $idApi)";
        }
      } else {
        if (variationSuffix.isNotEmpty && parentNameForVariation != null && nameApi.startsWith(parentNameForVariation) && !nameApi.endsWith(variationSuffix) && nameApi.length == parentNameForVariation.length) {
          nameApi = "$parentNameForVariation - $variationSuffix";
        }
      }
    }
    if (nameApi.isEmpty) nameApi = "Producto (ID: $idApi)";

    List<String> categoryNamesApi = (json['categories'] as List?)?.map((cat) => cat is Map ? cat['name'] as String? ?? '' : '').where((name) => name.isNotEmpty).toList() ?? [];
    String? barcodeApi;
    if (json['meta_data'] is List) {
      final meta = (json['meta_data'] as List).firstWhereOrNull( (m) => m is Map && (m['key'] == '_barcode' || m['key'] == 'barcode' || m['key'] == '_mpbm_barcode') && m['value'] != null && m['value'].toString().isNotEmpty );
      if (meta != null) { barcodeApi = meta['value'].toString(); }
    }

    List<String> imagesApi = [];
    if (finalType == 'variation' && json['image'] is Map && json['image']['src'] is String) {
      final variationImageSrc = json['image']['src'] as String?;
      if (variationImageSrc != null && variationImageSrc.isNotEmpty) {
        imagesApi = [variationImageSrc];
      }
    }
    if (imagesApi.isEmpty && json['images'] is List && (json['images'] as List).isNotEmpty) {
      imagesApi = (json['images'] as List).map((img) => (img is Map && img['src'] is String) ? img['src'] as String : null).where((url) => url != null && url.isNotEmpty).cast<String>().toList();
    }
    if (imagesApi.isEmpty && json['image'] is Map && json['image']['src'] is String ) {
      final singleImageSrc = json['image']['src'] as String?;
      if(singleImageSrc != null && singleImageSrc.isNotEmpty) {
        imagesApi = [singleImageSrc];
      }
    }
    String? firstImageUrl = imagesApi.isNotEmpty ? imagesApi.first : null;

    List<int>? variationsList;
    if (json['variations'] is List) {
      variationsList = (json['variations'] as List).whereType<int>().toList();
    }

    return Product(
      id: idApi,
      name: nameApi,
      sku: skuApiValue,
      type: finalType,
      price: effectivePrice,
      thumbnailUrl: firstImageUrl,
      parentId: finalParentId,
      barcode: barcodeApi,
      regularPrice: regularPriceValue,
      salePrice: (onSaleApiValue && salePriceValue != null) ? salePriceValue : null,
      onSale: onSaleApiValue,
      manageStock: manageStockEffective,
      stockQuantity: stockQuantityApiValue,
      stockStatus: stockStatusApiValue,
      categoryNames: categoryNamesApi.isNotEmpty ? categoryNamesApi : null,
      attributes: parsedAttributesForThisInstance.isNotEmpty ? parsedAttributesForThisInstance : null,
      fullAttributesWithOptions: parsedFullAttributesForParentVariable.isNotEmpty ? parsedFullAttributesForParentVariable : null,
      imageUrls: imagesApi,
      dateModified: pDate(json['date_modified_gmt'] ?? json['date_modified']),
      description: json['description'] as String?,
      shortDescription: json['short_description'] as String?,
      variations: variationsList,
    );
  }

  Product copyWith({
    String? id, String? name, String? sku, String? type, double? price,
    ValueGetter<String?>? thumbnailUrl,
    ValueGetter<int?>? parentId, ValueGetter<String?>? barcode,
    ValueGetter<double?>? regularPrice, ValueGetter<double?>? salePrice, bool? onSale, bool? manageStock,
    ValueGetter<int?>? stockQuantity, ValueGetter<String?>? stockStatus, ValueGetter<List<String>?>? categoryNames,
    ValueGetter<List<Map<String, dynamic>>?>? attributes, ValueGetter<List<Map<String, dynamic>>?>? fullAttributesWithOptions,
    List<String>? imageUrls, DateTime? dateModified, ValueGetter<String?>? description, ValueGetter<String?>? shortDescription,
    ValueGetter<List<int>?>? variations,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      type: type ?? this.type,
      price: price ?? this.price,
      thumbnailUrl: thumbnailUrl != null ? thumbnailUrl() : this.thumbnailUrl,
      parentId: parentId != null ? parentId() : this.parentId,
      barcode: barcode != null ? barcode() : this.barcode,
      regularPrice: regularPrice != null ? regularPrice() : this.regularPrice,
      salePrice: salePrice != null ? salePrice() : this.salePrice,
      onSale: onSale ?? this.onSale,
      manageStock: manageStock ?? this.manageStock,
      stockQuantity: stockQuantity != null ? stockQuantity() : this.stockQuantity,
      stockStatus: stockStatus != null ? stockStatus() : this.stockStatus,
      categoryNames: categoryNames != null ? categoryNames() : (this.categoryNames != null ? List<String>.from(this.categoryNames!) : null),
      attributes: attributes != null ? attributes() : (this.attributes != null ? List<Map<String, dynamic>>.from(this.attributes!) : null),
      fullAttributesWithOptions: fullAttributesWithOptions != null ? fullAttributesWithOptions() : (this.fullAttributesWithOptions != null ? List<Map<String, dynamic>>.from(this.fullAttributesWithOptions!) : null),
      imageUrls: imageUrls ?? List<String>.from(this.imageUrls),
      dateModified: dateModified ?? this.dateModified,
      description: description != null ? description() : this.description,
      shortDescription: shortDescription != null ? shortDescription() : this.shortDescription,
      variations: variations != null ? variations() : (this.variations != null ? List<int>.from(this.variations!) : null),
    );
  }

  Product toHiveObject() {
    return Product(
      id: id,
      name: name,
      sku: sku,
      type: type,
      price: price,
      thumbnailUrl: thumbnailUrl,
      parentId: parentId,
      barcode: barcode,
      regularPrice: regularPrice,
      salePrice: salePrice,
      onSale: onSale,
      manageStock: manageStock,
      stockQuantity: stockQuantity,
      stockStatus: stockStatus,
      categoryNames: categoryNames,
      attributes: attributes,
      fullAttributesWithOptions: fullAttributesWithOptions,
      imageUrls: imageUrls,
      dateModified: dateModified,
      description: description,
      shortDescription: shortDescription,
      variations: variations,
    );
  }

  @override
  String toString() {
    return 'Product(id: $id, name: "$name", type: $type, price: $price, parentId: $parentId, sku: $sku, stock: $stockQuantity, status: $stockStatus, variations: ${variations?.length ?? 0}, attributes: ${attributes?.map((e) => e['name'])} )';
  }
}
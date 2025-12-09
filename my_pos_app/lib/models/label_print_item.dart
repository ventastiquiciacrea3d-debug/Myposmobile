// lib/models/label_print_item.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'product.dart' as app_product;

part 'label_print_item.g.dart';

@immutable
class LabelSettings {
  final int printerResolutionDPI;
  final Map<String, double> labelLayout;
  final Map<String, bool> visibleAttributes;
  final List<String> fieldOrder;
  final Map<String, Map<String, dynamic>> fieldLayouts;

  // ⚡ NUEVOS CAMPOS: Configuración de impresora
  final int density;      // 1-15 (oscuridad de impresión)
  final int speed;        // 1-6 (velocidad de impresión)
  final int direction;    // 0 o 1 (dirección de impresión)
  final double gapMm;     // Gap entre etiquetas en mm

  // ⚡ NUEVOS CAMPOS: Márgenes
  final int marginTop;       // Margen superior en dots
  final int marginBottom;    // Margen inferior en dots
  final int marginLeft;      // Margen izquierdo en dots
  final int marginRight;     // Margen derecho en dots

  const LabelSettings({
    this.printerResolutionDPI = 203,
    this.labelLayout = const {'width': 50.0, 'height': 38.0},
    this.visibleAttributes = const {
      'productName': true, 'variants': true, 'sku': true, 'brand': true,
      'barcode': true, 'lotNumber': false, 'date': true, 'quantity': true,
    },
    this.fieldOrder = const [
      'productName', 'variants', 'quantity', 'lotNumber', 'date', 'brand', 'sku', 'barcode'
    ],
    this.fieldLayouts = const {
      'productName': {'columns': 1, 'size': 'large', 'weight': 'bold', 'fit': 'truncate', 'spacing': 1.5, 'align': 'left'},
      'variants':    {'columns': 2, 'size': 'small', 'weight': 'normal', 'fit': 'truncate', 'spacing': 1.0, 'align': 'left'},
      'quantity':    {'columns': 2, 'size': 'small', 'weight': 'bold', 'fit': 'truncate', 'spacing': 1.0, 'align': 'left'},
      'lotNumber':   {'columns': 2, 'size': 'small', 'weight': 'normal', 'fit': 'truncate', 'spacing': 1.0, 'align': 'left'},
      'date':        {'columns': 2, 'size': 'small', 'weight': 'normal', 'fit': 'truncate', 'spacing': 1.0, 'align': 'left'},
      'brand':       {'columns': 1, 'size': 'small', 'weight': 'normal', 'fit': 'truncate', 'spacing': 1.0, 'align': 'left'},
      'sku':         {'columns': 1, 'size': 'small', 'weight': 'normal', 'fit': 'truncate', 'spacing': 1.0, 'align': 'center'},
      'barcode':     {'columns': 1},
    },
    // ⚡ Valores por defecto para configuración de impresora
    this.density = 12,
    this.speed = 4,
    this.direction = 1,
    this.gapMm = 3.0,
    // ⚡ Valores por defecto para márgenes
    this.marginTop = 15,
    this.marginBottom = 15,
    this.marginLeft = 15,
    this.marginRight = 15,
  });

  LabelSettings copyWith({
    int? printerResolutionDPI,
    Map<String, double>? labelLayout,
    Map<String, bool>? visibleAttributes,
    List<String>? fieldOrder,
    Map<String, Map<String, dynamic>>? fieldLayouts,
    int? density,
    int? speed,
    int? direction,
    double? gapMm,
    int? marginTop,
    int? marginBottom,
    int? marginLeft,
    int? marginRight,
  }) {
    return LabelSettings(
      printerResolutionDPI: printerResolutionDPI ?? this.printerResolutionDPI,
      labelLayout: labelLayout ?? this.labelLayout,
      visibleAttributes: visibleAttributes ?? this.visibleAttributes,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      fieldLayouts: fieldLayouts ?? this.fieldLayouts,
      density: density ?? this.density,
      speed: speed ?? this.speed,
      direction: direction ?? this.direction,
      gapMm: gapMm ?? this.gapMm,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
    );
  }

  Map<String, dynamic> toJson() => {
    'printerResolutionDPI': printerResolutionDPI,
    'labelLayout': labelLayout,
    'visibleAttributes': visibleAttributes,
    'fieldOrder': fieldOrder,
    'fieldLayouts': fieldLayouts,
    'density': density,
    'speed': speed,
    'direction': direction,
    'gapMm': gapMm,
    'marginTop': marginTop,
    'marginBottom': marginBottom,
    'marginLeft': marginLeft,
    'marginRight': marginRight,
  };

  factory LabelSettings.fromJson(Map<String, dynamic> json) {
    final defaultSettings = const LabelSettings();
    final loadedAttributes = (json['visibleAttributes'] as Map<String, dynamic>?)
        ?.map((key, value) => MapEntry(key, value as bool)) ?? {};

    final Map<String, Map<String, dynamic>> parsedFieldLayouts = {};
    if (json['fieldLayouts'] is Map) {
      (json['fieldLayouts'] as Map).forEach((key, value) {
        if (value is Map) {
          parsedFieldLayouts[key] = Map<String, dynamic>.from(value);
          if (value['spacing'] is String) {
            switch (value['spacing']) {
              case 'compact': parsedFieldLayouts[key]!['spacing'] = 1.0; break;
              case 'extended': parsedFieldLayouts[key]!['spacing'] = 2.0; break;
              case 'normal': default: parsedFieldLayouts[key]!['spacing'] = 1.5; break;
            }
          }
        }
      });
    }

    return LabelSettings(
      printerResolutionDPI: (json['printerResolutionDPI'] as num?)?.toInt() ?? defaultSettings.printerResolutionDPI,
      labelLayout: (json['labelLayout'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, (value as num).toDouble()))
          ?? defaultSettings.labelLayout,
      visibleAttributes: {...defaultSettings.visibleAttributes, ...loadedAttributes},
      fieldOrder: (json['fieldOrder'] as List<dynamic>?)?.cast<String>() ?? defaultSettings.fieldOrder,
      fieldLayouts: {...defaultSettings.fieldLayouts, ...parsedFieldLayouts},
      density: (json['density'] as num?)?.toInt() ?? defaultSettings.density,
      speed: (json['speed'] as num?)?.toInt() ?? defaultSettings.speed,
      direction: (json['direction'] as num?)?.toInt() ?? defaultSettings.direction,
      gapMm: (json['gapMm'] as num?)?.toDouble() ?? defaultSettings.gapMm,
      marginTop: (json['marginTop'] as num?)?.toInt() ?? defaultSettings.marginTop,
      marginBottom: (json['marginBottom'] as num?)?.toInt() ?? defaultSettings.marginBottom,
      marginLeft: (json['marginLeft'] as num?)?.toInt() ?? defaultSettings.marginLeft,
      marginRight: (json['marginRight'] as num?)?.toInt() ?? defaultSettings.marginRight,
    );
  }
}

@HiveType(typeId: 7)
class LabelPrintItem extends HiveObject {
  @HiveField(0) String? id;
  @HiveField(1) final String productId;
  @HiveField(2) final String? resolvedVariantId;
  @HiveField(3) final int quantity;
  @HiveField(4) final Map<String, String> selectedVariants;
  @HiveField(5) final String? barcode;
  @HiveField(6) final String? lotNumber;

  // ⚡ NUEVOS CAMPOS: Almacenar nombre y SKU en caché para carga rápida
  final String? cachedProductName;
  final String? cachedSku;

  app_product.Product? product;
  app_product.Product? resolvedVariant;

  LabelPrintItem({
    this.id,
    required this.productId,
    this.resolvedVariantId,
    required this.quantity,
    this.selectedVariants = const {},
    this.barcode,
    this.lotNumber,
    this.cachedProductName,
    this.cachedSku,
    this.product,
    this.resolvedVariant,
  }) {
    id ??= const Uuid().v4();
  }

  /// ⚡ OPTIMIZACIÓN: Usar valores en caché primero, luego productos completos si están cargados
  String get displayName => cachedProductName ?? resolvedVariant?.name ?? product?.name ?? 'Producto';
  String get displaySku => cachedSku ?? resolvedVariant?.sku ?? product?.sku ?? 'N/A';

  SerializableLabelData toSerializableData() {
    // --- INICIO DE LA CORRECCIÓN ---
    // La marca es un atributo del producto PADRE (`this.product`), no necesariamente de la variante.
    // Buscamos la marca siempre en el producto padre.
    final brandAttribute = product?.attributes?.firstWhereOrNull(
            (attr) => attr['name']?.toLowerCase() == 'brand' || attr['name']?.toLowerCase() == 'marca'
    );
    final brandName = brandAttribute?['option'] as String? ?? '';
    // --- FIN DE LA CORRECCIÓN ---

    // ⚡ FIX: Formatear fecha manualmente para evitar LocaleDataException en isolates
    // DateFormat('dd/MM/yy', 'es_CR') no funciona dentro de compute() porque el locale no está inicializado
    final now = DateTime.now();
    final formattedDate = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${(now.year % 100).toString().padLeft(2, '0')}';

    return SerializableLabelData(
      displayName: displayName,
      displaySku: displaySku,
      quantity: quantity,
      selectedVariants: selectedVariants,
      brand: brandName,
      barcode: barcode ?? displaySku,
      lotNumber: lotNumber,
      date: formattedDate,
    );
  }
}

@immutable
class SerializableLabelData {
  final String displayName;
  final String displaySku;
  final int quantity;
  final Map<String, String> selectedVariants;
  final String brand;
  final String? barcode;
  final String? lotNumber;
  final String date;

  const SerializableLabelData({
    required this.displayName,
    required this.displaySku,
    required this.quantity,
    required this.selectedVariants,
    required this.brand,
    this.barcode,
    this.lotNumber,
    required this.date,
  });
}
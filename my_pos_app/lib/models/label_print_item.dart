// lib/models/label_print_item.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
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
  });

  LabelSettings copyWith({
    int? printerResolutionDPI,
    Map<String, double>? labelLayout,
    Map<String, bool>? visibleAttributes,
    List<String>? fieldOrder,
    Map<String, Map<String, dynamic>>? fieldLayouts,
  }) {
    return LabelSettings(
      printerResolutionDPI: printerResolutionDPI ?? this.printerResolutionDPI,
      labelLayout: labelLayout ?? this.labelLayout,
      visibleAttributes: visibleAttributes ?? this.visibleAttributes,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      fieldLayouts: fieldLayouts ?? this.fieldLayouts,
    );
  }

  Map<String, dynamic> toJson() => {
    'printerResolutionDPI': printerResolutionDPI,
    'labelLayout': labelLayout,
    'visibleAttributes': visibleAttributes,
    'fieldOrder': fieldOrder,
    'fieldLayouts': fieldLayouts,
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
    this.product,
    this.resolvedVariant,
  }) {
    id ??= const Uuid().v4();
  }

  String get displayName => resolvedVariant?.name ?? product?.name ?? 'Cargando...';
  String get displaySku => resolvedVariant?.sku ?? product?.sku ?? 'N/A';

  SerializableLabelData toSerializableData() {
    // --- INICIO DE LA CORRECCIÓN ---
    // La marca es un atributo del producto PADRE (`this.product`), no necesariamente de la variante.
    // Buscamos la marca siempre en el producto padre.
    final brandAttribute = product?.attributes?.firstWhereOrNull(
            (attr) => attr['name']?.toLowerCase() == 'brand' || attr['name']?.toLowerCase() == 'marca'
    );
    final brandName = brandAttribute?['option'] as String? ?? '';
    // --- FIN DE LA CORRECCIÓN ---

    return SerializableLabelData(
      displayName: displayName,
      displaySku: displaySku,
      quantity: quantity,
      selectedVariants: selectedVariants,
      brand: brandName,
      barcode: barcode ?? displaySku,
      lotNumber: lotNumber,
      date: DateFormat('dd/MM/yy', 'es_CR').format(DateTime.now()),
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
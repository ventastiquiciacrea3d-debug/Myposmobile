// lib/models/shared_dictionaries.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Diccionarios Compartidos para Compresión
///
/// Total: ~25 KB para toda la app
/// Reduce espacio 90% al evitar duplicar strings
class SharedDictionaries {
  // Singleton
  static final SharedDictionaries _instance = SharedDictionaries._internal();
  factory SharedDictionaries() => _instance;
  SharedDictionaries._internal();

  // ==================== BRANDS DICTIONARY ====================
  // ~100 marcas × 20 bytes = 2 KB

  final Map<int, String> _brands = {};
  final Map<String, int> _brandsReverse = {};

  void loadBrands(Map<int, String> brands) {
    _brands.clear();
    _brandsReverse.clear();

    _brands.addAll(brands);
    brands.forEach((id, name) {
      _brandsReverse[name.toLowerCase()] = id;
    });

    debugPrint('[Dictionaries] Loaded ${_brands.length} brands');
  }

  String? getBrand(int id) => _brands[id];
  int? getBrandId(String name) => _brandsReverse[name.toLowerCase()];

  Map<String, int> get brandsForApi => _brandsReverse;

  // ==================== CATEGORIES DICTIONARY ====================
  // ~200 categorías × 30 bytes = 6 KB

  final Map<int, Category> _categories = {};
  final Map<String, int> _categoriesReverse = {};

  void loadCategories(Map<int, Category> categories) {
    _categories.clear();
    _categoriesReverse.clear();

    _categories.addAll(categories);
    categories.forEach((id, category) {
      _categoriesReverse[category.name.toLowerCase()] = id;
    });

    debugPrint('[Dictionaries] Loaded ${_categories.length} categories');
  }

  Category? getCategory(int id) => _categories[id];
  int? getCategoryId(String name) => _categoriesReverse[name.toLowerCase()];

  List<Category> getCategoryHierarchy(int id) {
    final hierarchy = <Category>[];
    var current = _categories[id];

    while (current != null) {
      hierarchy.insert(0, current);
      current = current.parentId > 0 ? _categories[current.parentId] : null;
    }

    return hierarchy;
  }

  // ==================== ATTRIBUTES DICTIONARY ====================
  // ~50 atributos × 10 bytes = 500 bytes

  final Map<int, String> _attributes = {};
  final Map<String, int> _attributesReverse = {};

  void loadAttributes(Map<int, String> attributes) {
    _attributes.clear();
    _attributesReverse.clear();

    _attributes.addAll(attributes);
    attributes.forEach((id, name) {
      _attributesReverse[name.toLowerCase()] = id;
    });

    debugPrint('[Dictionaries] Loaded ${_attributes.length} attributes');
  }

  String? getAttribute(int id) => _attributes[id];
  int? getAttributeId(String name) => _attributesReverse[name.toLowerCase()];

  // ==================== ATTRIBUTE VALUES DICTIONARY ====================
  // ~500 valores × 15 bytes = 7.5 KB

  final Map<int, AttributeValue> _attributeValues = {};
  final Map<String, int> _attributeValuesReverse = {};

  void loadAttributeValues(Map<int, AttributeValue> values) {
    _attributeValues.clear();
    _attributeValuesReverse.clear();

    _attributeValues.addAll(values);
    values.forEach((id, value) {
      final key = '${value.attributeId}:${value.value.toLowerCase()}';
      _attributeValuesReverse[key] = id;
    });

    debugPrint('[Dictionaries] Loaded ${_attributeValues.length} attribute values');
  }

  AttributeValue? getAttributeValue(int id) => _attributeValues[id];

  int? getAttributeValueId(int attributeId, String value) {
    final key = '$attributeId:${value.toLowerCase()}';
    return _attributeValuesReverse[key];
  }

  // ==================== COMPRESSION HELPERS ====================

  /// Comprimir atributos a formato binario
  ///
  /// Ejemplo:
  /// Input: {Color: Negro, Talla: M, Capacidad: 64GB}
  /// Output: [1, 15, 2, 8, 3, 42] = 6 bytes
  /// (vs 45 bytes en JSON)
  Uint8List compressAttributes(Map<String, String> attributes) {
    final bytes = <int>[];

    attributes.forEach((attrName, value) {
      final attrId = getAttributeId(attrName);
      if (attrId == null) return;

      final valueId = getAttributeValueId(attrId, value);
      if (valueId == null) return;

      // 2 bytes por atributo
      bytes.add(attrId);
      bytes.add(valueId);
    });

    return Uint8List.fromList(bytes);
  }

  /// Descomprimir atributos desde binario
  Map<String, String> decompressAttributes(Uint8List? compressed) {
    if (compressed == null || compressed.isEmpty) {
      return {};
    }

    final attributes = <String, String>{};

    for (int i = 0; i < compressed.length; i += 2) {
      if (i + 1 >= compressed.length) break;

      final attrId = compressed[i];
      final valueId = compressed[i + 1];

      final attrName = getAttribute(attrId);
      final attrValue = getAttributeValue(valueId);

      if (attrName != null && attrValue != null) {
        attributes[attrName] = attrValue.value;
      }
    }

    return attributes;
  }

  // ==================== INITIAL LOAD ====================

  /// Cargar diccionarios por defecto
  void loadDefaults() {
    // Brands comunes
    loadBrands({
      1: 'Samsung',
      2: 'Apple',
      3: 'LG',
      4: 'Sony',
      5: 'Huawei',
      6: 'Xiaomi',
      7: 'Nokia',
      8: 'Motorola',
      9: 'HP',
      10: 'Dell',
      // ... más marcas
      0: 'Unknown',
    });

    // Categorías comunes
    loadCategories({
      1: Category(id: 1, name: 'Electrónica', parentId: 0),
      2: Category(id: 2, name: 'Smartphones', parentId: 1),
      3: Category(id: 3, name: 'Laptops', parentId: 1),
      4: Category(id: 4, name: 'Ropa', parentId: 0),
      5: Category(id: 5, name: 'Camisetas', parentId: 4),
      6: Category(id: 6, name: 'Pantalones', parentId: 4),
      7: Category(id: 7, name: 'Alimentos', parentId: 0),
      8: Category(id: 8, name: 'Bebidas', parentId: 7),
      // ... más categorías
      0: Category(id: 0, name: 'Uncategorized', parentId: 0),
    });

    // Atributos comunes
    loadAttributes({
      1: 'Color',
      2: 'Talla',
      3: 'Capacidad',
      4: 'Tamaño',
      5: 'Material',
      6: 'Marca',
      // ... más atributos
    });

    // Valores de atributos
    loadAttributeValues({
      // Colores (attributeId: 1)
      1: AttributeValue(id: 1, attributeId: 1, value: 'Negro'),
      2: AttributeValue(id: 2, attributeId: 1, value: 'Blanco'),
      3: AttributeValue(id: 3, attributeId: 1, value: 'Azul'),
      4: AttributeValue(id: 4, attributeId: 1, value: 'Rojo'),
      5: AttributeValue(id: 5, attributeId: 1, value: 'Verde'),

      // Tallas (attributeId: 2)
      10: AttributeValue(id: 10, attributeId: 2, value: 'XS'),
      11: AttributeValue(id: 11, attributeId: 2, value: 'S'),
      12: AttributeValue(id: 12, attributeId: 2, value: 'M'),
      13: AttributeValue(id: 13, attributeId: 2, value: 'L'),
      14: AttributeValue(id: 14, attributeId: 2, value: 'XL'),

      // Capacidades (attributeId: 3)
      20: AttributeValue(id: 20, attributeId: 3, value: '32GB'),
      21: AttributeValue(id: 21, attributeId: 3, value: '64GB'),
      22: AttributeValue(id: 22, attributeId: 3, value: '128GB'),
      23: AttributeValue(id: 23, attributeId: 3, value: '256GB'),
      24: AttributeValue(id: 24, attributeId: 3, value: '512GB'),

      // ... más valores
    });

    debugPrint('[Dictionaries] ✅ Default dictionaries loaded');
  }

  // ==================== STATS ====================

  Map<String, int> getStats() {
    return {
      'brands': _brands.length,
      'categories': _categories.length,
      'attributes': _attributes.length,
      'attribute_values': _attributeValues.length,
      'total_entries': _brands.length +
          _categories.length +
          _attributes.length +
          _attributeValues.length,
    };
  }

  int estimateSizeInBytes() {
    // Estimación aproximada
    final brandsSize = _brands.values.fold(0, (sum, name) => sum + name.length);
    final categoriesSize =
        _categories.values.fold(0, (sum, cat) => sum + cat.name.length);
    final attributesSize =
        _attributes.values.fold(0, (sum, name) => sum + name.length);
    final valuesSize =
        _attributeValues.values.fold(0, (sum, val) => sum + val.value.length);

    return brandsSize + categoriesSize + attributesSize + valuesSize;
  }
}

/// Modelo de Categoría
class Category {
  final int id;
  final String name;
  final int parentId;

  Category({
    required this.id,
    required this.name,
    required this.parentId,
  });

  @override
  String toString() => 'Category(id: $id, name: $name, parent: $parentId)';
}

/// Modelo de Valor de Atributo
class AttributeValue {
  final int id;
  final int attributeId;
  final String value;

  AttributeValue({
    required this.id,
    required this.attributeId,
    required this.value,
  });

  @override
  String toString() =>
      'AttributeValue(id: $id, attribute: $attributeId, value: $value)';
}

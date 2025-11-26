// lib/utils/attribute_compressor.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/dictionaries.dart';
import '../services/database_service.dart';
import '../objectbox.g.dart'; // Para query helpers (AttributeDictionary_, etc.)

/// Compresor de Atributos
///
/// Convierte atributos de formato JSON a binario ultra-comprimido
///
/// Ejemplo:
/// JSON: {"Color": "Negro", "Talla": "M", "Capacidad": "64GB"}
/// Tamaño: ~45 bytes
///
/// Binario: [1, 5, 2, 12, 3, 8]
/// Tamaño: 6 bytes (7.5x más pequeño!)
///
/// Formato: [attrId1, valueId1, attrId2, valueId2, ...]
class AttributeCompressor {
  final DatabaseService _db;

  AttributeCompressor(this._db);

  /// Comprimir atributos a formato binario
  Uint8List compress(Map<String, dynamic> attributes) {
    if (attributes.isEmpty) {
      return Uint8List(0);
    }

    final buffer = BytesBuilder();

    attributes.forEach((attributeName, attributeValue) {
      try {
        // Buscar ID del atributo
        final attrId = _getAttributeId(attributeName);
        if (attrId == null) {
          debugPrint('[AttributeCompressor] ⚠️ Attribute "$attributeName" not found in dictionary');
          return;
        }

        // Buscar ID del valor
        final valueId = _getAttributeValueId(attrId, attributeValue.toString());
        if (valueId == null) {
          debugPrint('[AttributeCompressor] ⚠️ Value "$attributeValue" not found for attribute "$attributeName"');
          return;
        }

        // Agregar al buffer (2 bytes por atributo)
        buffer.addByte(attrId);
        buffer.addByte(valueId);

      } catch (e) {
        debugPrint('[AttributeCompressor] Error compressing $attributeName=$attributeValue: $e');
      }
    });

    final compressed = buffer.toBytes();
    debugPrint('[AttributeCompressor] Compressed ${attributes.length} attrs → ${compressed.length} bytes');

    return compressed;
  }

  /// Descomprimir atributos desde formato binario
  Map<String, dynamic> decompress(Uint8List data) {
    if (data.isEmpty) {
      return {};
    }

    final result = <String, dynamic>{};

    // Leer pares de bytes
    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 >= data.length) {
        debugPrint('[AttributeCompressor] ⚠️ Incomplete attribute pair at index $i');
        break;
      }

      final attrId = data[i];
      final valueId = data[i + 1];

      try {
        // Buscar nombre del atributo
        final attributeName = _getAttributeName(attrId);
        if (attributeName == null) {
          debugPrint('[AttributeCompressor] ⚠️ Attribute ID $attrId not found');
          continue;
        }

        // Buscar valor del atributo
        final attributeValue = _getAttributeValueName(valueId);
        if (attributeValue == null) {
          debugPrint('[AttributeCompressor] ⚠️ Value ID $valueId not found');
          continue;
        }

        result[attributeName] = attributeValue;

      } catch (e) {
        debugPrint('[AttributeCompressor] Error decompressing pair [$attrId, $valueId]: $e');
      }
    }

    debugPrint('[AttributeCompressor] Decompressed ${data.length} bytes → ${result.length} attrs');
    return result;
  }

  /// Comprimir lista de atributos de variación
  ///
  /// Ejemplo: ["Negro", "M", "64GB"] → [5, 12, 8]
  Uint8List compressVariationAttributes(List<String> attributeValues) {
    if (attributeValues.isEmpty) {
      return Uint8List(0);
    }

    final buffer = BytesBuilder();

    for (final value in attributeValues) {
      // Buscar ID del valor (sin necesidad de attrId)
      final valueId = _searchValueId(value);
      if (valueId != null) {
        buffer.addByte(valueId);
      }
    }

    return buffer.toBytes();
  }

  /// Descomprimir lista de atributos de variación
  List<String> decompressVariationAttributes(Uint8List data) {
    if (data.isEmpty) {
      return [];
    }

    final result = <String>[];

    for (final valueId in data) {
      final value = _getAttributeValueName(valueId);
      if (value != null) {
        result.add(value);
      }
    }

    return result;
  }

  // ==================== HELPERS PRIVADOS ====================

  /// Obtener ID de atributo por nombre
  int? _getAttributeId(String attributeName) {
    final box = _db.store.box<AttributeDictionary>();
    final query = box.query(
      AttributeDictionary_.name.equals(attributeName, caseSensitive: false)
    ).build();

    final attr = query.findFirst();
    query.close();

    return attr?.id;
  }

  /// Obtener nombre de atributo por ID
  String? _getAttributeName(int attrId) {
    final box = _db.store.box<AttributeDictionary>();
    final attr = box.get(attrId);
    return attr?.name;
  }

  /// Obtener ID de valor de atributo
  int? _getAttributeValueId(int attrId, String valueName) {
    final box = _db.store.box<AttributeValueDictionary>();
    final query = box.query(
      AttributeValueDictionary_.attributeId.equals(attrId)
        .and(AttributeValueDictionary_.value.equals(valueName, caseSensitive: false))
    ).build();

    final attrValue = query.findFirst();
    query.close();

    return attrValue?.id;
  }

  /// Obtener nombre de valor de atributo por ID
  String? _getAttributeValueName(int valueId) {
    final box = _db.store.box<AttributeValueDictionary>();
    final attrValue = box.get(valueId);
    return attrValue?.value;
  }

  /// Buscar ID de valor sin conocer el attrId (para variaciones)
  int? _searchValueId(String valueName) {
    final box = _db.store.box<AttributeValueDictionary>();
    final query = box.query(
      AttributeValueDictionary_.value.equals(valueName, caseSensitive: false)
    ).build();

    final attrValue = query.findFirst();
    query.close();

    return attrValue?.id;
  }

  /// Calcular ratio de compresión
  double calculateCompressionRatio(Map<String, dynamic> attributes) {
    if (attributes.isEmpty) return 0.0;

    // Tamaño JSON aproximado
    final jsonString = attributes.toString();
    final jsonSize = jsonString.length;

    // Tamaño comprimido
    final compressed = compress(attributes);
    final compressedSize = compressed.length;

    if (compressedSize == 0) return 0.0;

    final ratio = jsonSize / compressedSize;
    return ratio;
  }

  /// Obtener estadísticas
  Map<String, dynamic> getStats() {
    final attrBox = _db.store.box<AttributeDictionary>();
    final valueBox = _db.store.box<AttributeValueDictionary>();

    return {
      'total_attributes': attrBox.count(),
      'total_values': valueBox.count(),
      'estimated_dictionary_size_kb': ((attrBox.count() * 50) + (valueBox.count() * 30)) / 1024,
    };
  }
}

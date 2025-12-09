// lib/utils/product_attribute_serializer.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Serializer para atributos de productos
///
/// Convierte atributos entre formato JSON y binario (Uint8List)
/// para almacenamiento eficiente en ObjectBox.
///
/// **Formato de atributos:**
///
/// 1. attributes (variación específica):
/// ```json
/// [
///   {"id": 1, "name": "Color", "option": "Rojo", "slug": "pa_color"},
///   {"id": 2, "name": "Marca", "option": "CREALITY", "slug": "pa_marca"}
/// ]
/// ```
///
/// 2. fullAttributesWithOptions (opciones del padre):
/// ```json
/// [
///   {
///     "id": 1,
///     "name": "Color",
///     "slug": "pa_color",
///     "options": ["Rojo", "Azul", "Verde"],
///     "visible": true,
///     "variation": true
///   }
/// ]
/// ```
class ProductAttributeSerializer {
  /// Comprime AMBOS tipos de atributos en un solo Uint8List
  ///
  /// **Formato combinado:**
  /// ```json
  /// {
  ///   "attrs": [...],           // attributes (variación)
  ///   "fullAttrs": [...]        // fullAttributesWithOptions (padre)
  /// }
  /// ```
  ///
  /// **Proceso:**
  /// 1. Crear objeto combinado
  /// 2. Serializar a JSON string
  /// 3. Convertir a UTF-8 bytes
  /// 4. Retornar como Uint8List
  ///
  /// **Returns:** Uint8List comprimido, o null si no hay atributos
  static Uint8List? compressBoth({
    List<Map<String, dynamic>>? attributes,
    List<Map<String, dynamic>>? fullAttributesWithOptions,
  }) {
    // Si ambos son null o vacíos, retornar null
    if ((attributes == null || attributes.isEmpty) &&
        (fullAttributesWithOptions == null || fullAttributesWithOptions.isEmpty)) {
      return null;
    }

    try {
      // Crear objeto combinado (solo incluir campos no vacíos)
      final combined = <String, dynamic>{};

      if (attributes != null && attributes.isNotEmpty) {
        combined['attrs'] = attributes;
      }

      if (fullAttributesWithOptions != null && fullAttributesWithOptions.isNotEmpty) {
        combined['fullAttrs'] = fullAttributesWithOptions;
      }

      // Serializar a JSON y convertir a bytes
      final jsonString = jsonEncode(combined);
      final bytes = utf8.encode(jsonString);

      // ⚡ PERFORMANCE: Comentado para evitar spam de logs al guardar productos
      // debugPrint(
      //   '[ProductAttributeSerializer] Compressed: '
      //   '${attributes?.length ?? 0} attrs + ${fullAttributesWithOptions?.length ?? 0} fullAttrs '
      //   '→ ${bytes.length} bytes'
      // );

      return Uint8List.fromList(bytes);

    } catch (e) {
      debugPrint('[ProductAttributeSerializer] ❌ Error compressing: $e');
      return null;
    }
  }

  /// Descomprime AMBOS tipos de atributos desde Uint8List
  ///
  /// **Returns:** Map con claves 'attributes' y 'fullAttributesWithOptions'
  ///
  /// **Ejemplo:**
  /// ```dart
  /// final result = ProductAttributeSerializer.decompressBoth(data);
  /// final attrs = result['attributes'];  // List<Map<String, dynamic>>?
  /// final fullAttrs = result['fullAttributesWithOptions'];  // List<Map<String, dynamic>>?
  /// ```
  static Map<String, List<Map<String, dynamic>>?> decompressBoth(
    Uint8List? compressedData,
  ) {
    // Valor por defecto (ambos null)
    final defaultResult = <String, List<Map<String, dynamic>>?>{
      'attributes': null,
      'fullAttributesWithOptions': null,
    };

    if (compressedData == null || compressedData.isEmpty) {
      return defaultResult;
    }

    try {
      // Convertir bytes a JSON string
      final jsonString = utf8.decode(compressedData);

      // Decodificar JSON
      final decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        debugPrint('[ProductAttributeSerializer] ⚠️ Invalid format: expected Map');
        return defaultResult;
      }

      // Extraer atributos
      List<Map<String, dynamic>>? attributes;
      if (decoded['attrs'] != null) {
        attributes = (decoded['attrs'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      List<Map<String, dynamic>>? fullAttrs;
      if (decoded['fullAttrs'] != null) {
        fullAttrs = (decoded['fullAttrs'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      // ⚡ PERFORMANCE: Comentado para evitar spam de logs al leer productos
      // debugPrint(
      //   '[ProductAttributeSerializer] Decompressed: '
      //   '${compressedData.length} bytes → '
      //   '${attributes?.length ?? 0} attrs + ${fullAttrs?.length ?? 0} fullAttrs'
      // );

      return {
        'attributes': attributes,
        'fullAttributesWithOptions': fullAttrs,
      };

    } catch (e) {
      debugPrint('[ProductAttributeSerializer] ❌ Error decompressing: $e');
      return defaultResult;
    }
  }

  /// Comprime solo un tipo de atributos (helper)
  ///
  /// **Uso:** Cuando solo tienes uno de los dos tipos
  static Uint8List? compress(List<Map<String, dynamic>>? attributes) {
    if (attributes == null || attributes.isEmpty) {
      return null;
    }

    try {
      final jsonString = jsonEncode(attributes);
      final bytes = utf8.encode(jsonString);

      // ⚡ PERFORMANCE: Comentado para evitar spam de logs al guardar productos
      // debugPrint(
      //   '[ProductAttributeSerializer] Compressed: '
      //   '${attributes.length} items → ${bytes.length} bytes'
      // );

      return Uint8List.fromList(bytes);

    } catch (e) {
      debugPrint('[ProductAttributeSerializer] ❌ Error compressing: $e');
      return null;
    }
  }

  /// Descomprime solo un tipo de atributos (helper)
  static List<Map<String, dynamic>>? decompress(Uint8List? compressedData) {
    if (compressedData == null || compressedData.isEmpty) {
      return null;
    }

    try {
      final jsonString = utf8.decode(compressedData);
      final decoded = jsonDecode(jsonString);

      if (decoded is! List) {
        debugPrint('[ProductAttributeSerializer] ⚠️ Invalid format: expected List');
        return null;
      }

      final result = decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      // ⚡ PERFORMANCE: Comentado para evitar spam de logs al leer productos
      // debugPrint(
      //   '[ProductAttributeSerializer] Decompressed: '
      //   '${compressedData.length} bytes → ${result.length} items'
      // );

      return result;

    } catch (e) {
      debugPrint('[ProductAttributeSerializer] ❌ Error decompressing: $e');
      return null;
    }
  }

  /// Calcula ratio de compresión
  ///
  /// **Returns:** Ratio (ej: 3.5 significa 3.5x más pequeño que JSON raw)
  static double calculateCompressionRatio({
    List<Map<String, dynamic>>? attributes,
    List<Map<String, dynamic>>? fullAttributesWithOptions,
  }) {
    if ((attributes == null || attributes.isEmpty) &&
        (fullAttributesWithOptions == null || fullAttributesWithOptions.isEmpty)) {
      return 0.0;
    }

    try {
      // Tamaño JSON sin comprimir (pretty print)
      final combined = <String, dynamic>{};
      if (attributes != null && attributes.isNotEmpty) {
        combined['attrs'] = attributes;
      }
      if (fullAttributesWithOptions != null && fullAttributesWithOptions.isNotEmpty) {
        combined['fullAttrs'] = fullAttributesWithOptions;
      }

      final jsonString = jsonEncode(combined);
      final uncompressedSize = jsonString.length;

      // Tamaño comprimido (UTF-8 bytes)
      final compressed = compressBoth(
        attributes: attributes,
        fullAttributesWithOptions: fullAttributesWithOptions,
      );

      if (compressed == null || compressed.isEmpty) {
        return 0.0;
      }

      final compressedSize = compressed.length;

      // Calcular ratio
      final ratio = uncompressedSize / compressedSize;

      return ratio;

    } catch (e) {
      debugPrint('[ProductAttributeSerializer] ❌ Error calculating ratio: $e');
      return 0.0;
    }
  }

  /// Obtiene estadísticas de tamaño
  ///
  /// **Returns:** Map con información detallada
  static Map<String, dynamic> getSizeStats({
    List<Map<String, dynamic>>? attributes,
    List<Map<String, dynamic>>? fullAttributesWithOptions,
  }) {
    final compressed = compressBoth(
      attributes: attributes,
      fullAttributesWithOptions: fullAttributesWithOptions,
    );

    final combined = <String, dynamic>{};
    if (attributes != null && attributes.isNotEmpty) {
      combined['attrs'] = attributes;
    }
    if (fullAttributesWithOptions != null && fullAttributesWithOptions.isNotEmpty) {
      combined['fullAttrs'] = fullAttributesWithOptions;
    }

    final jsonString = jsonEncode(combined);

    return {
      'uncompressed_bytes': jsonString.length,
      'compressed_bytes': compressed?.length ?? 0,
      'compression_ratio': calculateCompressionRatio(
        attributes: attributes,
        fullAttributesWithOptions: fullAttributesWithOptions,
      ),
      'attributes_count': attributes?.length ?? 0,
      'full_attributes_count': fullAttributesWithOptions?.length ?? 0,
    };
  }
}

// lib/services/tspl_batch_service.dart
import 'package:flutter/foundation.dart';

/// Servicio para generar comandos TSPL en batch usando isolates
/// Esto previene que el UI thread se congele durante la generación
class TsplBatchService {

  /// Genera TODOS los comandos TSPL en background thread
  ///
  /// **Performance**: Genera 100+ etiquetas sin congelar la UI
  ///
  /// **Parámetros**:
  /// - [productsData]: Lista de productos con datos básicos (nombre, sku, precio, barcode)
  /// - [settings]: Configuración de etiquetas (ancho, alto, campos visibles)
  /// - [onProgress]: Callback para actualizar progreso (current/total)
  ///
  /// **Returns**: Lista de comandos TSPL listos para enviar a impresora
  static Future<List<String>> generateBatchInBackground({
    required List<Map<String, dynamic>> productsData,
    required Map<String, dynamic> settings,
    required void Function(int current, int total)? onProgress,
  }) async {
    debugPrint('[TsplBatch] 🚀 Starting batch generation for ${productsData.length} items');

    // ⚡ OPTIMIZACIÓN: Si son pocos items (<10), generar directamente sin isolate
    // Evita overhead de crear isolate para tareas pequeñas
    if (productsData.length < 10) {
      final commands = <String>[];
      for (int i = 0; i < productsData.length; i++) {
        commands.add(_generateSingleLabel(productsData[i], settings));
        onProgress?.call(i + 1, productsData.length);
        // Permitir que UI se actualice
        await Future.delayed(Duration(milliseconds: 1));
      }
      debugPrint('[TsplBatch] ✅ Generation complete (direct): ${commands.length} commands');
      return commands;
    }

    // Para muchos items, usar compute() - más simple y robusto que Isolate.spawn
    try {
      final result = await compute(
        _generateAllInIsolate,
        {
          'products': productsData,
          'settings': settings,
        },
      );

      // Actualizar progreso al 100% cuando compute() termina
      onProgress?.call(productsData.length, productsData.length);

      debugPrint('[TsplBatch] ✅ Generation complete: ${result.length} commands');
      return result;

    } catch (e) {
      debugPrint('[TsplBatch] ❌ Error: $e');
      rethrow;
    }
  }

  /// Función estática para compute() - genera todos los comandos
  /// Esta función se ejecuta en un isolate separado automáticamente
  static List<String> _generateAllInIsolate(Map<String, dynamic> params) {
    final products = params['products'] as List<Map<String, dynamic>>;
    final settings = params['settings'] as Map<String, dynamic>;

    final commands = <String>[];

    for (final product in products) {
      commands.add(_generateSingleLabel(product, settings));
    }

    return commands;
  }


  /// Genera un comando TSPL individual (versión ligera sin dependencias)
  ///
  /// **Formato TSPL**: Comandos de texto para impresoras térmicas
  static String _generateSingleLabel(
    Map<String, dynamic> product,
    Map<String, dynamic> settings,
  ) {
    final buffer = StringBuffer();

    // Configuración de tamaño de etiqueta
    final width = settings['width'] ?? 50.0;
    final height = settings['height'] ?? 38.0;
    final density = settings['density'] ?? 12;
    final speed = settings['speed'] ?? 4;

    // Header TSPL
    buffer.writeln('SIZE $width mm, $height mm');
    buffer.writeln('DENSITY $density');
    buffer.writeln('SPEED $speed');
    buffer.writeln('CLS');

    // Posiciones (ajustables según tamaño)
    int currentY = 10;

    // Nombre del producto
    if (settings['showName'] ?? true) {
      final name = product['name'] ?? 'Producto';
      buffer.writeln('TEXT 10,$currentY,"3",0,1,1,"${_escapeText(name)}"');
      currentY += 40;
    }

    // SKU
    if (settings['showSku'] ?? true) {
      final sku = product['sku'] ?? 'N/A';
      buffer.writeln('TEXT 10,$currentY,"2",0,1,1,"SKU: ${_escapeText(sku)}"');
      currentY += 30;
    }

    // Precio
    if (settings['showPrice'] ?? true) {
      final price = product['price'] ?? 0.0;
      buffer.writeln('TEXT 10,$currentY,"2",0,1,1,"\$$price"');
      currentY += 30;
    }

    // Código de barras
    if ((settings['showBarcode'] ?? true) && product['barcode'] != null) {
      final barcode = product['barcode'];
      buffer.writeln('BARCODE 10,$currentY,"128",80,1,0,2,2,"$barcode"');
      currentY += 100;
    }

    // Cantidad (repetir etiqueta)
    final quantity = product['quantity'] ?? 1;
    buffer.writeln('PRINT $quantity,1');

    return buffer.toString();
  }

  /// Escapar texto para TSPL (remover caracteres problemáticos)
  static String _escapeText(String text) {
    return text
        .replaceAll('"', "'")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '')
        .trim();
  }
}


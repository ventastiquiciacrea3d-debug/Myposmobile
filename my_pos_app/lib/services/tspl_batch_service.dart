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

    // ⚡ NUEVA OPTIMIZACIÓN: Para muchos items, dividir en chunks
    // Esto permite reportar progreso gradual en lugar de saltar de 30% a 100%
    try {
      final allCommands = <String>[];
      const chunkSize = 10; // Procesar 10 items por chunk
      final totalItems = productsData.length;
      final totalChunks = (totalItems / chunkSize).ceil();

      for (int chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        final startIndex = chunkIndex * chunkSize;
        final endIndex = (startIndex + chunkSize).clamp(0, totalItems);
        final chunk = productsData.sublist(startIndex, endIndex);

        // Generar comandos para este chunk en compute()
        final chunkCommands = await compute(
          _generateAllInIsolate,
          {
            'products': chunk,
            'settings': settings,
          },
        );

        allCommands.addAll(chunkCommands);

        // Reportar progreso después de cada chunk
        onProgress?.call(endIndex, totalItems);

        debugPrint('[TsplBatch] 📊 Progress: $endIndex/$totalItems');

        // Pequeño delay entre chunks para no saturar el UI thread
        if (chunkIndex < totalChunks - 1) {
          await Future.delayed(Duration(milliseconds: 10));
        }
      }

      debugPrint('[TsplBatch] ✅ Generation complete: ${allCommands.length} commands');
      return allCommands;

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
  /// ⚡ OPTIMIZADO: Pre-construye el header y reduce operaciones de StringBuffer
  static String _generateSingleLabel(
    Map<String, dynamic> product,
    Map<String, dynamic> settings,
  ) {
    // Configuración de tamaño de etiqueta (extraer una sola vez)
    final width = settings['width'] ?? 50.0;
    final height = settings['height'] ?? 38.0;
    final density = settings['density'] ?? 12;
    final speed = settings['speed'] ?? 4;
    final showName = settings['showName'] ?? true;
    final showSku = settings['showSku'] ?? true;
    final showPrice = settings['showPrice'] ?? false;
    final showBarcode = settings['showBarcode'] ?? true;

    // Pre-construir header TSPL (siempre igual para cada etiqueta)
    final header = 'SIZE $width mm, $height mm\nDENSITY $density\nSPEED $speed\nCLS\n';

    // Construir comandos de forma más eficiente
    final parts = <String>[header];
    int currentY = 10;

    // Nombre del producto
    if (showName) {
      final name = product['name'] ?? 'Producto';
      parts.add('TEXT 10,$currentY,"3",0,1,1,"${_escapeText(name)}"\n');
      currentY += 40;
    }

    // SKU
    if (showSku) {
      final sku = product['sku'] ?? 'N/A';
      parts.add('TEXT 10,$currentY,"2",0,1,1,"SKU: ${_escapeText(sku)}"\n');
      currentY += 30;
    }

    // Precio (típicamente oculto)
    if (showPrice) {
      final price = product['price'] ?? 0.0;
      parts.add('TEXT 10,$currentY,"2",0,1,1,"\$$price"\n');
      currentY += 30;
    }

    // Código de barras
    if (showBarcode && product['barcode'] != null) {
      final barcode = product['barcode'];
      parts.add('BARCODE 10,$currentY,"128",80,1,0,2,2,"$barcode"\n');
      currentY += 100;
    }

    // Cantidad (repetir etiqueta)
    final quantity = product['quantity'] ?? 1;
    parts.add('PRINT $quantity,1\n');

    // Unir todas las partes de una vez (más rápido que múltiples writeln)
    return parts.join();
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


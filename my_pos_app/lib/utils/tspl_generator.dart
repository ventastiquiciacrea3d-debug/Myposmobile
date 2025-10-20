// lib/utils/tspl_generator.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/label_print_item.dart';

// Clase contenedora para pasar todos los datos necesarios al Isolate.
class TsplGenerationData {
  final LabelPrintItem item;
  final LabelSettings settings;
  final int quantity;
  final int density;
  final int speed;

  TsplGenerationData({
    required this.item,
    required this.settings,
    required this.quantity,
    required this.density,
    required this.speed,
  });
}

// Esta es la función de nivel superior que se ejecutará en el Isolate.
// Es una función pura: toma datos y devuelve un resultado, sin efectos secundarios.
String generateTsplCommandsIsolate(TsplGenerationData data) {
  final sb = StringBuffer();
  final serializableData = data.item.toSerializableData();

  final double labelWidthMm = data.settings.labelLayout['width'] ?? 50.0;
  final double labelHeightMm = data.settings.labelLayout['height'] ?? 38.0;
  final int widthDots = (labelWidthMm * 8).round();
  final int heightDots = (labelHeightMm * 8).round();

  sb.writeln('SIZE ${labelWidthMm} mm, ${labelHeightMm} mm');
  sb.writeln('GAP 3 mm, 0 mm');
  sb.writeln('SPEED ${data.speed}');
  sb.writeln('DENSITY ${data.density}');
  sb.writeln('DIRECTION 1');
  sb.writeln('CLS');

  const int topMargin = 15;
  const int bottomMargin = 15;
  const int horizontalMargin = 15;
  final int printableWidthDots = widthDots - (2 * horizontalMargin);
  int currentYDots = topMargin;
  int textBottomBoundaryDots = heightDots - bottomMargin;

  final bool isBarcodeVisible = data.settings.visibleAttributes['barcode'] ?? true;
  final String barcodeData = serializableData.barcode ?? serializableData.displaySku;

  if (isBarcodeVisible && barcodeData.isNotEmpty) {
    final int barcodeHeightDots = (heightDots * 0.25).round().clamp(40, 70);
    const int barcodeTextHeightDots = 25;
    const int barcodeAreaGapDots = 8;
    final int totalBarcodeHeight = barcodeHeightDots + barcodeTextHeightDots + barcodeAreaGapDots;
    textBottomBoundaryDots = heightDots - bottomMargin - totalBarcodeHeight;
    final int barcodeY = textBottomBoundaryDots + barcodeAreaGapDots;

    final int narrowBarWidth = 2;
    final int estimatedBarcodeWidth = (barcodeData.length + 3) * 11 * narrowBarWidth;
    final int barcodeX = ((widthDots - estimatedBarcodeWidth) / 2).round().clamp(0, widthDots);

    sb.writeln('BARCODE $barcodeX,$barcodeY,"128",$barcodeHeightDots,2,0,$narrowBarWidth,4,"${_sanitize(barcodeData)}"');
  }

  final layouts = data.settings.fieldLayouts;
  final fieldsToDraw = data.settings.fieldOrder.where((k) => (data.settings.visibleAttributes[k] ?? false) && k != 'barcode').toList();

  final rows = <List<String>>[];
  for (var i = 0; i < fieldsToDraw.length;) {
    final key1 = fieldsToDraw[i];
    final columns = layouts[key1]?['columns'] ?? 1;
    if (columns == 1 || i + 1 >= fieldsToDraw.length) {
      rows.add([key1]);
      i++;
    } else {
      rows.add([key1, fieldsToDraw[i + 1]]);
      i += 2;
    }
  }

  for (final row in rows) {
    final rowItemsData = row.map((key) {
      final text = _getTextForKey(key, serializableData);
      return text.isNotEmpty ? {'key': key, 'text': text, 'layout': layouts[key] ?? {}} : null;
    }).where((item) => item != null).cast<Map<String,dynamic>>().toList();

    if (rowItemsData.isEmpty) continue;

    int maxRowHeightDots = 0;
    double maxSpacingMultiplier = 1.0;
    final rowCommands = StringBuffer();

    if (rowItemsData.length == 1) {
      final itemData = rowItemsData.first;
      final layout = itemData['layout'];
      final fontMap = _getFontMapping(layout['size'] ?? 'medium');
      final result = _generateTextCommand(
          text: itemData['text'], y: currentYDots, colX: horizontalMargin,
          colWidth: printableWidthDots, fontMap: fontMap,
          fit: layout['fit'] ?? 'truncate', align: layout['align'] ?? 'left'
      );
      rowCommands.write(result['command']);
      maxRowHeightDots = result['height'];
      maxSpacingMultiplier = (layout['spacing'] as num?)?.toDouble() ?? 1.0;
    } else {
      final item1Data = rowItemsData[0];
      final item2Data = rowItemsData[1];
      final colWidth = (printableWidthDots - 10) ~/ 2;

      final layout1 = item1Data['layout'];
      final fontMap1 = _getFontMapping(layout1['size'] ?? 'medium');
      final result1 = _generateTextCommand(
          text: item1Data['text'], y: currentYDots, colX: horizontalMargin,
          colWidth: colWidth, fontMap: fontMap1, fit: 'truncate',
          align: layout1['align'] ?? 'left'
      );

      final layout2 = item2Data['layout'];
      final fontMap2 = _getFontMapping(layout2['size'] ?? 'medium');
      final result2 = _generateTextCommand(
          text: item2Data['text'], y: currentYDots, colX: horizontalMargin + colWidth + 10,
          colWidth: colWidth, fontMap: fontMap2, fit: 'truncate',
          align: layout2['align'] ?? 'left'
      );

      rowCommands.write(result1['command']);
      rowCommands.write(result2['command']);
      maxRowHeightDots = max(result1['height'] as int, result2['height'] as int);
      maxSpacingMultiplier = max((layout1['spacing'] as num?)?.toDouble() ?? 1.0, (layout2['spacing'] as num?)?.toDouble() ?? 1.0);
    }

    if (currentYDots + maxRowHeightDots < textBottomBoundaryDots) {
      sb.write(rowCommands.toString());
      currentYDots += (maxRowHeightDots * maxSpacingMultiplier).round();
    } else {
      break;
    }
  }

  sb.writeln('PRINT ${data.quantity},1');
  return sb.toString();
}

String _sanitize(String text) {
  if (text.isEmpty) return '';
  return text.replaceAll('"', '""').replaceAll('\\', '\\\\');
}

Map<String, dynamic> _getFontMapping(String sizeKey) {
  if (sizeKey == 'large') return {'font': "3", 'h': 24, 'w': 16};
  if (sizeKey == 'medium') return {'font': "2", 'h': 20, 'w': 12};
  return {'font': "1", 'h': 12, 'w': 8};
}

String _getTextForKey(String key, SerializableLabelData data) {
  switch (key) {
    case 'productName': return data.displayName;
    case 'variants': return data.selectedVariants.values.join(' / ');
    case 'quantity': return 'Cant: ${data.quantity}';
    case 'date': return data.date;
    case 'lotNumber': return (data.lotNumber != null && data.lotNumber!.isNotEmpty) ? 'Lote: ${data.lotNumber}' : '';
    case 'brand': return data.brand;
    case 'sku': return 'SKU: ${data.displaySku}';
    default: return '';
  }
}

Map<String, dynamic> _generateTextCommand({
  required String text, required int y, required int colX,
  required int colWidth, required Map<String, dynamic> fontMap,
  required String fit, required String align,
}) {
  final sanitizedText = _sanitize(text);
  final double charWidth = (fontMap['w'] as int).toDouble();
  final int maxChars = (colWidth / charWidth).floor().clamp(1, 100);
  final int lineHeight = (fontMap['h'] as int) + 4;

  String command = '';
  int totalHeight = 0;
  List<String> linesToPrint = [];

  if (fit == 'wrap') {
    String currentLine = '';
    for (String word in sanitizedText.split(' ')) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if ((currentLine.length + word.length + 1) <= maxChars) {
        currentLine += ' $word';
      } else {
        linesToPrint.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) linesToPrint.add(currentLine);
  } else {
    String textToPrint = sanitizedText;
    if (fit == 'truncate' && sanitizedText.length > maxChars) {
      textToPrint = sanitizedText.substring(0, maxChars);
    }
    linesToPrint.add(textToPrint);
  }

  int lineY = y;
  for (String line in linesToPrint.where((l) => l.isNotEmpty).take(2)) {
    int startX;
    int textWidthInDots = (line.length * charWidth).round();
    switch (align) {
      case 'center': startX = colX + (colWidth - textWidthInDots) ~/ 2; break;
      case 'right': startX = colX + colWidth - textWidthInDots; break;
      case 'left': default: startX = colX; break;
    }
    startX = startX.clamp(0, colX + colWidth);
    command += 'TEXT $startX,$lineY,"${fontMap['font']}",0,1,1,"$line"\r\n';
    lineY += lineHeight;
    totalHeight += lineHeight;
  }
  totalHeight = max(totalHeight, lineHeight);

  return {'command': command, 'height': totalHeight};
}

class TsplGenerator {
  static Future<List<int>> generateCommands({
    required LabelPrintItem item,
    required LabelSettings settings,
    required int quantity,
    int density = 12,
    int speed = 4,
  }) async {
    final data = TsplGenerationData(
      item: item,
      settings: settings,
      quantity: quantity,
      density: density,
      speed: speed,
    );
    // Ejecuta la función de generación en un Isolate separado usando compute.
    final tsplString = await compute(generateTsplCommandsIsolate, data);

    // Descomentar para depuración si es necesario
    // debugPrint("--- FINAL GENERATED TSPL ---\n$tsplString\n--------------------------");

    return latin1.encode(tsplString);
  }
}
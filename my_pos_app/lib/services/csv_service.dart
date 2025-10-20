// lib/services/csv_service.dart
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../models/product.dart' as app_product;

class CsvService {
  Future<void> shareCsv(String fileName, List<List<dynamic>> data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/$fileName";
      final file = File(path);

      String csvData = const ListToCsvConverter().convert(data);
      await file.writeAsString(csvData);

      final xFile = XFile(path);
      await Share.shareXFiles([xFile], text: 'Aquí está el archivo de inventario.');
    } catch (e) {
      debugPrint("Error al compartir CSV: $e");
      throw Exception("No se pudo generar o compartir el archivo CSV.");
    }
  }

  Future<void> downloadInventoryTemplate() async {
    final List<List<dynamic>> templateData = [
      ['name', 'attribute', 'sku', 'stock_actual', 'conteo_fisico', 'anadir_stock'],
      ['Nombre Producto Simple', '', 'SKU-SIMPLE-1', 10, '0', '0'],
      ['Nombre Producto Variable - Atributo', 'Color: Rojo', 'SKU-VARIACION-1', 25, '0', '0'],
    ];
    await shareCsv('plantilla_ajuste_inventario.csv', templateData);
  }

  Future<void> exportCurrentInventory({
    required List<app_product.Product> products,
    required List<Map<String, dynamic>> categories,
    String? categoryFilterId,
    String? typeFilter,
  }) async {
    final List<List<dynamic>> exportData = [
      ['name', 'attribute', 'sku', 'stock_actual', 'conteo_fisico', 'anadir_stock', 'manage_stock', 'price', 'type', 'category']
    ];

    List<app_product.Product> filteredProducts = products;

    if (categoryFilterId != null && categoryFilterId != 'all') {
      final category = categories.firstWhereOrNull((c) => c['id'].toString() == categoryFilterId);
      final catName = category?['name'];
      if(catName != null) {
        filteredProducts = filteredProducts.where((p) {
          if (p.isVariation) {
            final parent = products.firstWhereOrNull((parent) => parent.id == p.parentId.toString());
            return parent?.categoryNames?.contains(catName) ?? false;
          }
          return p.categoryNames?.contains(catName) ?? false;
        }).toList();
      }
    }

    if (typeFilter != null && typeFilter != 'all') {
      filteredProducts = filteredProducts.where((p) => p.type == typeFilter).toList();
    }


    for (final product in filteredProducts) {
      if(product.isVariable) continue;

      String categoryName = 'Sin Categoría';
      app_product.Product? productForCategory = product;
      if (product.isVariation) {
        productForCategory = products.firstWhereOrNull((p) => p.id == product.parentId.toString());
      }
      categoryName = productForCategory?.categoryNames?.firstOrNull ?? 'Sin Categoría';

      String attributesText = '';
      if (product.isVariation && product.attributes != null) {
        attributesText = product.attributes!
            .map((attr) => '${attr['name']}: ${attr['option']}')
            .join(' | ');
      }

      exportData.add([
        product.name,
        attributesText,
        product.sku,
        product.stockQuantity ?? 0,
        '0', // conteo_fisico
        '0', // anadir_stock
        product.manageStock ? 'Habilitado' : 'Deshabilitado',
        product.price,
        product.type,
        categoryName,
      ]);
    }

    await shareCsv('exportacion_inventario.csv', exportData);
  }
}
// lib/screens/inventory_csv_import_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:collection/collection.dart'; // <-- LÍNEA AÑADIDA PARA LA CORRECCIÓN

import '../models/inventory_movement.dart';
import '../models/product.dart' as app_product;
import '../providers/inventory_provider.dart';
import '../repositories/product_repository.dart';
import '../services/csv_service.dart';
import '../widgets/app_header.dart';
import '../locator.dart';

class CsvAdjustmentPreview {
  final app_product.Product product;
  final int newQuantity;
  final int oldQuantity;
  final int quantityChange;
  final String sku;
  final String operation; // 'Conteo Físico' o 'Añadir Stock'

  CsvAdjustmentPreview({
    required this.product,
    required this.newQuantity,
    required this.oldQuantity,
    required this.quantityChange,
    required this.sku,
    required this.operation,
  });
}

class InventoryCsvImportScreen extends StatefulWidget {
  const InventoryCsvImportScreen({Key? key}) : super(key: key);

  @override
  State<InventoryCsvImportScreen> createState() => _InventoryCsvImportScreenState();
}

class _InventoryCsvImportScreenState extends State<InventoryCsvImportScreen> {
  final CsvService _csvService = getIt<CsvService>();
  List<CsvAdjustmentPreview> _previewLines = [];
  String? _filePath;
  bool _isLoading = false;
  String? _loadingMessage;
  String? _error;

  String _exportCategoryFilter = 'all';
  String _exportTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<InventoryProvider>();
      if (provider.inventoryProducts.isEmpty) {
        provider.loadInventoryProducts();
      }
    });
  }

  Future<void> _pickAndProcessCsv() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Seleccionando archivo...";
      _error = null;
      _previewLines = [];
      _filePath = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _filePath = result.files.single.name;
        _loadingMessage = "Procesando archivo CSV...";
      });

      final file = File(result.files.single.path!);
      final csvString = await file.readAsString(encoding: utf8);
      // Usar un decodificador que maneje tanto comas como punto y coma podría ser más robusto,
      // pero por ahora asumimos el formato correcto basado en la lógica del plugin.
      final List<List<dynamic>> csvData = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(csvString);

      if (csvData.length < 2) {
        throw Exception("El archivo CSV está vacío o solo contiene la cabecera.");
      }

      final header = csvData[0].map((h) => h.toString().toLowerCase().trim()).toList();
      final skuIndex = header.indexOf('sku');
      final physicalCountIndex = header.indexOf('conteo_fisico');
      final addStockIndex = header.indexOf('anadir_stock');

      if (skuIndex == -1 || (physicalCountIndex == -1 && addStockIndex == -1)) {
        throw Exception("El CSV debe contener la columna 'sku' y al menos una de 'conteo_fisico' o 'anadir_stock'.");
      }

      final productRepo = getIt<ProductRepository>();
      List<CsvAdjustmentPreview> previews = [];
      int rowNum = 1;
      for (final row in csvData.skip(1)) {
        rowNum++;
        if(row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) continue;

        final sku = row.length > skuIndex ? row[skuIndex]?.toString().trim() : null;
        if (sku == null || sku.isEmpty) continue;

        final physicalCountVal = (physicalCountIndex != -1 && row.length > physicalCountIndex) ? int.tryParse(row[physicalCountIndex]?.toString().trim() ?? '') : null;
        final addStockVal = (addStockIndex != -1 && row.length > addStockIndex) ? int.tryParse(row[addStockIndex]?.toString().trim() ?? '') : null;

        String? operation;
        int? value;

        if (physicalCountVal != null && physicalCountVal != 0) {
          operation = 'Conteo Físico';
          value = physicalCountVal;
        } else if (addStockVal != null && addStockVal != 0) {
          operation = 'Añadir Stock';
          value = addStockVal;
        }

        if (operation == null || value == null) continue;

        setState(() { _loadingMessage = "Buscando producto ${previews.length + 1}..."; });

        final product = await productRepo.searchProductByBarcodeOrSku(sku, searchOnlyAvailable: false);
        if (product == null) continue;

        final oldQty = product.stockQuantity ?? 0;
        int newQty;
        int qtyChange;

        if (operation == 'Conteo Físico') {
          newQty = value;
          qtyChange = newQty - oldQty;
        } else { // Añadir Stock
          qtyChange = value;
          newQty = oldQty + qtyChange;
        }

        previews.add(CsvAdjustmentPreview(
          product: product,
          newQuantity: newQty,
          oldQuantity: oldQty,
          quantityChange: qtyChange,
          sku: sku,
          operation: operation,
        ));
      }

      setState(() {
        _previewLines = previews;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _error = "Error: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAdjustment() async {
    if (_previewLines.isEmpty) return;

    setState(() { _isLoading = true; _loadingMessage = "Guardando ajuste masivo..."; });
    final inventoryProvider = context.read<InventoryProvider>();

    final groupedByOperation = groupBy(_previewLines, (p) => p.operation);
    bool anySuccess = false;
    String finalMessage = "";

    for (var entry in groupedByOperation.entries) {
      final operation = entry.key;
      final lines = entry.value;

      final itemsToAdjust = lines.where((p) => p.quantityChange != 0).map((preview) {
        return InventoryMovementLine(
          productId: preview.product.isVariation ? preview.product.parentId.toString() : preview.product.id,
          variationId: preview.product.isVariation ? preview.product.id : null,
          productName: preview.product.name,
          sku: preview.sku,
          quantityChanged: preview.quantityChange,
          stockBefore: preview.oldQuantity,
          stockAfter: preview.newQuantity,
        );
      }).toList();

      if (itemsToAdjust.isEmpty) continue;

      final success = await inventoryProvider.performMassInventoryAdjustment(
        type: operation == 'Conteo Físico' ? InventoryMovementType.stockCorrection : InventoryMovementType.supplierReceipt,
        description: "Ajuste masivo desde CSV: $_filePath ($operation)",
        itemsToAdjust: itemsToAdjust,
      );
      if (success) anySuccess = true;
      finalMessage += "$operation: ${success ? 'Éxito' : (inventoryProvider.errorMessage ?? 'Fallo')}. ";
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(finalMessage.trim()),
        backgroundColor: anySuccess ? Colors.green : Colors.red,
      ),
    );

    if (anySuccess) {
      Navigator.pop(context, true);
    }
  }

  void _handleExport(InventoryProvider provider) async {
    setState(() { _isLoading = true; _loadingMessage = "Generando archivo de exportación..."; });
    try {
      await _csvService.exportCurrentInventory(
        products: provider.inventoryProducts,
        categories: provider.allCategories,
        categoryFilterId: _exportCategoryFilter,
        typeFilter: _exportTypeFilter,
      );
    } catch(e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e"), backgroundColor: Colors.red,));
      }
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const AppHeader(title: 'Importar / Exportar CSV', showBackButton: true,),
      body: Center(
        child: _isLoading
            ? Column( mainAxisAlignment: MainAxisAlignment.center, children: [ const CircularProgressIndicator(), const SizedBox(height: 20), Text(_loadingMessage ?? "Cargando..."), ],)
            : _error != null
            ? Padding( padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red)),)
            : _previewLines.isEmpty
            ? _buildInitialView(theme)
            : _buildPreviewView(theme),
      ),
      bottomSheet: (_previewLines.isNotEmpty && !_isLoading) ? _buildBottomActionBar(theme) : null,
    );
  }

  Widget _buildInitialView(ThemeData theme) {
    final inventoryProvider = context.watch<InventoryProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Exportar Inventario Actual", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text("Descarga un archivo CSV con tu inventario actual para facilitar el conteo de inventario.", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isDense: true,
                          decoration: const InputDecoration(labelText: 'Categoría', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                          value: _exportCategoryFilter,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('Todas')),
                            ...inventoryProvider.allCategories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))),
                          ],
                          onChanged: (val) => setState(() => _exportCategoryFilter = val ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isDense: true,
                          decoration: const InputDecoration(labelText: 'Tipo', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                          value: _exportTypeFilter,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Todos')),
                            DropdownMenuItem(value: 'simple', child: Text('Simple')),
                            DropdownMenuItem(value: 'variation', child: Text('Variación')),
                          ],
                          onChanged: (val) => setState(() => _exportTypeFilter = val ?? 'all'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text("Exportar Inventario"), onPressed: inventoryProvider.isLoadingProducts ? null : () => _handleExport(inventoryProvider),),
                ],
              ),
            ),
          ),
          const Divider(height: 40),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Importar Ajuste de Stock", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text("Sube un archivo CSV para actualizar el stock. Rellena solo una de las columnas de ajuste por producto.", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(icon: const Icon(Icons.description_outlined), label: const Text("Descargar Plantilla CSV"), onPressed: () => _csvService.downloadInventoryTemplate(),),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.file_upload), label: const Text("Seleccionar Archivo de Ajuste"), onPressed: _pickAndProcessCsv,),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewView(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text("Vista Previa de Cambios (${_previewLines.length} productos)", style: theme.textTheme.titleLarge),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _previewLines.length,
            itemBuilder: (context, index) {
              final line = _previewLines[index];
              final changeColor = line.quantityChange > 0 ? Colors.green : (line.quantityChange < 0 ? Colors.red : Colors.grey);
              final changeSign = line.quantityChange > 0 ? '+' : '';
              return ListTile(
                title: Text(line.product.name),
                subtitle: Text("SKU: ${line.sku} • Operación: ${line.operation}"),
                trailing: Text(
                  '${line.oldQuantity} → ${line.newQuantity} ($changeSign${line.quantityChange})',
                  style: TextStyle(color: changeColor, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0 + MediaQuery.of(context).padding.bottom * 0.6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0,-2))],
      ),
      child: ElevatedButton(
        onPressed: _saveAdjustment,
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),),
        child: const Text('Confirmar y Guardar Ajuste'),
      ),
    );
  }
}
// lib/screens/label_printing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart' as app_product;
import '../models/label_print_item.dart';
import '../providers/label_provider.dart';
import '../providers/scanner_provider.dart';
import '../widgets/app_header.dart';
import '../widgets/quantity_selector.dart';
import '../repositories/product_repository.dart';
import '../locator.dart';
import '../config/routes.dart';
import '../services/woocommerce_service.dart';

class LabelPrintingScreen extends StatefulWidget {
  const LabelPrintingScreen({Key? key}) : super(key: key);

  @override
  State<LabelPrintingScreen> createState() => _LabelPrintingScreenState();
}

class _LabelPrintingScreenState extends State<LabelPrintingScreen> {
  final TextEditingController _productSearchController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  final FocusNode _productSearchFocusNode = FocusNode();
  bool _showSearchResults = false;

  app_product.Product? _selectedProduct;
  app_product.Product? _resolvedVariant;
  Map<String, String?> _selectedAttributes = {};
  int _quantity = 1;
  bool _isLoadingProductDetails = false;
  String? _currentProductError;

  List<app_product.Product> _availableVariations = [];

  late LabelProvider _labelProvider;

  @override
  void initState() {
    super.initState();
    _labelProvider = context.read<LabelProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ScannerProvider>().clearSearch();
        _labelProvider.addListener(_onEditingStateChanged);
        _onEditingStateChanged();
      }
    });

    _productSearchController.addListener(_onSearchChanged);
    _productSearchFocusNode.addListener(() {
      if (mounted && _showSearchResults != _productSearchFocusNode.hasFocus) {
        setState(() => _showSearchResults = _productSearchFocusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _labelProvider.removeListener(_onEditingStateChanged);
    _productSearchController.removeListener(_onSearchChanged);
    _productSearchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _productSearchFocusNode.dispose();
    super.dispose();
  }

  void _onEditingStateChanged() {
    if (!mounted) return;
    final itemToEdit = _labelProvider.itemBeingEdited;
    final isProductAlreadyInForm = (_selectedProduct?.id == itemToEdit?.productId && _labelProvider.editingItemId == itemToEdit?.id);

    if (itemToEdit != null && !isProductAlreadyInForm) {
      _loadItemForEditing(itemToEdit);
    } else if (itemToEdit == null && _selectedProduct != null) {
      if (_labelProvider.editingItemId == null) {
        _resetForm(keepSelectedProduct: false);
      }
    }
  }

  void _onSearchChanged() {
    if (!mounted) return;

    if (!_showSearchResults && _productSearchController.text.isNotEmpty) {
      setState(() { _showSearchResults = true; });
    } else if (_showSearchResults && _productSearchController.text.isEmpty) {
      setState(() { _showSearchResults = false; });
    }

    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        final searchTerm = _productSearchController.text;
        if (searchTerm.length > 1) {
          context.read<ScannerProvider>().performSearch(searchTerm);
        } else {
          context.read<ScannerProvider>().clearSearch();
        }
      }
    });
  }

  void _resetForm({required bool keepSelectedProduct}) {
    if (!mounted) return;
    setState(() {
      _quantity = 1;
      _currentProductError = null;
      _isLoadingProductDetails = false;
      _resolvedVariant = null;
      _selectedAttributes.clear();
      _availableVariations.clear();
      if (context.read<LabelProvider>().itemBeingEdited != null) {
        context.read<LabelProvider>().cancelEditing();
      }

      if (!keepSelectedProduct) {
        _selectedProduct = null;
        _productSearchController.clear();
        context.read<ScannerProvider>().clearSearch();
        _showSearchResults = false;
      } else if (_selectedProduct != null && _selectedProduct!.isVariable) {
        if (_selectedProduct!.fullAttributesWithOptions != null) {
          for (var attr in _selectedProduct!.fullAttributesWithOptions!) {
            final String? attrSlug = attr['slug'] as String?;
            if (attrSlug != null) _selectedAttributes[attrSlug] = null;
          }
        }
      }
    });
  }

  Future<void> _selectProduct(app_product.Product product) async {
    if (!mounted) return;
    _productSearchFocusNode.unfocus();
    context.read<ScannerProvider>().clearSearch();

    _productSearchController.removeListener(_onSearchChanged);
    setState(() {
      _showSearchResults = false;
      _isLoadingProductDetails = true;
      _productSearchController.text = product.name;
      _availableVariations.clear();
    });
    _productSearchController.addListener(_onSearchChanged);

    try {
      final productToProcess = (product.isVariable && (product.fullAttributesWithOptions == null || product.fullAttributesWithOptions!.isEmpty))
          ? await getIt<ProductRepository>().getProductById(product.id, forceApi: true)
          : product;

      if (!mounted) return;
      if (productToProcess != null) {
        if (productToProcess.isVariable) {
          _availableVariations = await getIt<ProductRepository>().getAllVariations(productToProcess.id);
        }

        if (!mounted) return;
        setState(() {
          _selectedProduct = productToProcess;
          _resolvedVariant = productToProcess.isSimple ? productToProcess : null;
          _selectedAttributes = {};
          _currentProductError = null;
          if (productToProcess.isVariable) {
            if (productToProcess.fullAttributesWithOptions != null && productToProcess.fullAttributesWithOptions!.isNotEmpty) {
              for (var attr in productToProcess.fullAttributesWithOptions!) {
                final String? attrSlug = attr['slug'] as String?;
                if (attrSlug != null) _selectedAttributes[attrSlug] = null;
              }
              if (_availableVariations.isEmpty && (productToProcess.variations?.isNotEmpty ?? false)) {
                _currentProductError = "No se pudieron cargar las variantes de este producto.";
              }
            } else {
              _currentProductError = "Este producto variable no tiene opciones configurables.";
            }
          }
          _isLoadingProductDetails = false;
          _quantity = 1;
        });
      } else {
        throw Exception("Producto no encontrado.");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar detalles: $e"), backgroundColor: Colors.red));
      _resetForm(keepSelectedProduct: false);
    }
  }

  void _handleVariantSelection(String attributeSlug, String? option) {
    if (!mounted || _selectedProduct == null) return;

    setState(() {
      _selectedAttributes[attributeSlug] = option;
      _resolvedVariant = null;
      _currentProductError = null;
    });

    final allAttributesSelected = _selectedAttributes.values.every((value) => value != null);

    if (allAttributesSelected) {
      final attributesForSearch = _selectedAttributes.cast<String, String>();
      final matchingVariant = _availableVariations.firstWhereOrNull((variant) {
        if (variant.attributes == null) return false;

        return attributesForSearch.entries.every((selectedAttr) {
          final selectedKeyLower = selectedAttr.key.toLowerCase();
          final selectedValueLower = selectedAttr.value.toLowerCase();

          return variant.attributes!.any((variantAttr) {
            final apiSlugLower = variantAttr['slug']?.toString().toLowerCase();
            final apiNameLower = variantAttr['name']?.toString().toLowerCase();
            final apiOptionLower = variantAttr['option']?.toString().toLowerCase();

            if (apiOptionLower == null) return false;

            final bool keyMatches = (apiSlugLower == selectedKeyLower || (apiSlugLower?.replaceFirst('attribute_', '') ?? '') == selectedKeyLower) || (apiNameLower == selectedKeyLower);
            final bool optionMatches = apiOptionLower == selectedValueLower;

            return keyMatches && optionMatches;
          });
        });
      });

      setState(() {
        _resolvedVariant = matchingVariant;
        _currentProductError = (matchingVariant == null) ? "Combinación de variante no encontrada." : null;
      });
    }
  }

  Future<void> _loadItemForEditing(LabelPrintItem item) async {
    if (!mounted) return;

    _productSearchFocusNode.unfocus();
    setState(() {
      _isLoadingProductDetails = true;
      _selectedProduct = null;
      _resolvedVariant = null;
      _productSearchController.text = "Cargando para editar...";
      _showSearchResults = false;
      _availableVariations.clear();
    });

    try {
      final fullProduct = await getIt<ProductRepository>().getProductById(item.productId, forceApi: true);
      if (!mounted) return;
      if (fullProduct == null) throw Exception("Producto padre (ID: ${item.productId}) no encontrado.");

      if (fullProduct.isVariable) {
        _availableVariations = await getIt<ProductRepository>().getAllVariations(fullProduct.id);
      }
      if (!mounted) return;

      if (!fullProduct.isVariable) {
        setState(() {
          _selectedProduct = fullProduct;
          _quantity = item.quantity;
          _isLoadingProductDetails = false;
          _productSearchController.removeListener(_onSearchChanged);
          _productSearchController.text = fullProduct.name;
          _productSearchController.addListener(_onSearchChanged);
        });
        return;
      }

      app_product.Product? resolvedVariant;
      if (item.resolvedVariantId != null && item.resolvedVariantId!.isNotEmpty) {
        resolvedVariant = _availableVariations.firstWhereOrNull((v) => v.id == item.resolvedVariantId);
      }
      if (!mounted) return;

      _productSearchController.removeListener(_onSearchChanged);
      _productSearchController.text = fullProduct.name;
      _productSearchController.addListener(_onSearchChanged);

      setState(() {
        _selectedProduct = fullProduct;
        _quantity = item.quantity;
        _resolvedVariant = resolvedVariant;
        _selectedAttributes.clear();

        if (fullProduct.fullAttributesWithOptions != null) {
          for (var attrDef in fullProduct.fullAttributesWithOptions!) {
            final attrName = attrDef['name'] as String?;
            final attrSlug = attrDef['slug'] as String?;
            if (attrName != null && attrSlug != null) {
              final savedOption = item.selectedVariants.entries.firstWhereOrNull((entry) => entry.key == attrName)?.value;
              _selectedAttributes[attrSlug] = savedOption;
            }
          }
        }
        _isLoadingProductDetails = false;
      });

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar para editar: $e"), backgroundColor: Colors.red));
      _labelProvider.cancelEditing();
    }
  }

  void _addOrUpdateItem() {
    if (!mounted || !_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Seleccione un producto."), backgroundColor: Colors.orange));
      return;
    }
    if (_selectedProduct!.isVariable && _resolvedVariant == null) {
      setState(() => _currentProductError = "Seleccione todas las opciones de la variante.");
      return;
    }

    Map<String, String> friendlySelectedVariants = {};
    if(_selectedProduct != null && _selectedProduct!.isVariable) {
      _selectedAttributes.entries.where((e) => e.value != null).forEach((entry) {
        final slug = entry.key;
        final option = entry.value!;
        final attrDef = _selectedProduct?.fullAttributesWithOptions?.firstWhereOrNull((attr) => attr['slug'] == slug);
        final attrName = attrDef?['name'] as String? ?? slug;
        friendlySelectedVariants[attrName] = option;
      });
    }

    final isEditing = _labelProvider.itemBeingEdited != null;
    final item = LabelPrintItem(
      id: _labelProvider.editingItemId ?? const Uuid().v4(),
      productId: _selectedProduct!.id,
      resolvedVariantId: _resolvedVariant?.id,
      quantity: _quantity,
      selectedVariants: friendlySelectedVariants,
      barcode: _resolvedVariant?.barcode ?? _selectedProduct!.barcode ?? _resolvedVariant?.sku ?? _selectedProduct!.sku,
      product: _selectedProduct,
      resolvedVariant: _resolvedVariant,
    );

    _labelProvider.addOrUpdateItem(item);
    final message = isEditing ? "'${item.displayName}' actualizado." : "'${item.displayName}' añadido a la cola.";

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));

    _resetForm(keepSelectedProduct: true);
  }

  void _duplicateItem(LabelPrintItem item) {
    if (!mounted) return;
    context.read<LabelProvider>().duplicateAndPrepareForEditing(item.id!);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("'${item.displayName}' cargado para editar."),
      backgroundColor: Colors.blueAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  void _navigateToThermalScreen() {
    if (_labelProvider.printQueue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Añada productos a la cola antes de imprimir."), backgroundColor: Colors.orange));
      return;
    }
    Navigator.pushNamed(context, Routes.thermalPrinting, arguments: _labelProvider.printQueue)
        .then((printedSuccessfully) {
      if (printedSuccessfully == true && mounted) {
        context.read<LabelProvider>().clearQueue();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scannerProvider = context.watch<ScannerProvider>();
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppHeader(
          title: 'Impresión de Etiquetas',
          showBackButton: true,
          showSettingsButton: true,
          onSettingsPressed: () => Routes.navigateTo(context, Routes.labelSettings),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 120 + MediaQuery.of(context).padding.bottom),
            children: [
              _buildProductSelectionCard(scannerProvider),
              const SizedBox(height: 20),
              _buildPrintQueueCard(),
            ],
          ),
        ),
        bottomSheet: isKeyboardVisible ? const SizedBox.shrink() : _buildBottomActionBar(),
      ),
    );
  }


  Widget _buildProductSelectionCard(ScannerProvider scannerProvider) {
    final theme = Theme.of(context);
    final isEditing = _labelProvider.itemBeingEdited != null;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? "Editando Producto" : "Añadir Producto a la Cola", style: theme.textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _productSearchController,
              focusNode: _productSearchFocusNode,
              decoration: InputDecoration(
                  hintText: "Buscar producto por nombre o SKU...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: scannerProvider.isSearching
                      ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_productSearchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _resetForm(keepSelectedProduct: false)) : null)
              ),
            ),
            if (_showSearchResults && scannerProvider.searchResults.isNotEmpty)
              _buildSearchResults(scannerProvider.searchResults),

            if (!_showSearchResults) ...[
              if (_isLoadingProductDetails)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (_currentProductError != null && _selectedProduct != null)
                Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_currentProductError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
              if (_selectedProduct != null && !_isLoadingProductDetails)
                _buildProductForm(theme, isEditing),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPrintQueueCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Cola de Impresión (${_labelProvider.printQueue.length})", style: theme.textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_labelProvider.printQueue.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("La cola está vacía.")))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _labelProvider.printQueue.length,
                itemBuilder: (context, index) {
                  final item = _labelProvider.printQueue[index];
                  final isCurrentlyEditingThis = _labelProvider.editingItemId == item.id;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isCurrentlyEditingThis ? Colors.blue.shade50 : null,
                    child: ListTile(
                      title: Text(item.displayName),
                      subtitle: Text("SKU: ${item.displaySku} | ${item.selectedVariants.values.join(' / ')}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("x${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.copy_all_outlined, color: Colors.blueGrey, size: 20), tooltip: "Duplicar", onPressed: () => _duplicateItem(item)),
                          IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 20), tooltip: "Editar", onPressed: () => _labelProvider.startEditing(item.id!)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22), tooltip: "Eliminar", onPressed: () => _labelProvider.removeItem(item.id!)),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<app_product.Product> results) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.only(top: 4),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final product = results[index];
            return ListTile(
                title: Text(product.name),
                subtitle: Text("SKU: ${product.sku}"),
                onTap: () => _selectProduct(product));
          },
        ),
      ),
    );
  }

  Widget _buildProductForm(ThemeData theme, bool isEditing) {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }

    final productForDisplay = _resolvedVariant ?? _selectedProduct!;

    return Column(
      children: [
        const SizedBox(height: 16),
        ListTile(
          title: Text(productForDisplay.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("SKU: ${productForDisplay.sku}"),
          trailing: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => _resetForm(keepSelectedProduct: false)),
        ),
        if (_selectedProduct!.isVariable)
          Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildVariantSelectors(theme)),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text("Cantidad de Etiquetas:")),
          QuantitySelector(
              key: ValueKey(productForDisplay.id),
              value: _quantity,
              onChanged: (val) {
                if (mounted) setState(() => _quantity = val);
              },
              minValue: 1,
              maxValue: 999)
        ]),
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
                icon: Icon(isEditing ? Icons.save_as_outlined : Icons.playlist_add_rounded),
                onPressed: _addOrUpdateItem,
                label: Text(isEditing ? "Guardar Cambios" : "Añadir a la Cola"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: isEditing ? Colors.blue.shade700 : theme.primaryColor))),
        if (isEditing)
          TextButton(
              onPressed: () {
                _labelProvider.cancelEditing();
                _resetForm(keepSelectedProduct: false);
              },
              child: const Text("Cancelar Edición"))
      ],
    );
  }

  Widget _buildVariantSelectors(ThemeData theme) {
    if (_selectedProduct?.fullAttributesWithOptions == null ||
        _selectedProduct!.fullAttributesWithOptions!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: _selectedProduct!.fullAttributesWithOptions!.map((attr) {
        final String attrName = attr['name'] as String? ?? 'Atributo';
        final String attrSlug = attr['slug'] as String? ?? attrName.toLowerCase();

        final List<String> options = (attr['options'] as List<dynamic>?)
            ?.map((o) => o.toString())
            .where((o) => o.isNotEmpty)
            .toList() ?? [];

        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: DropdownButtonFormField<String>(
            value: _selectedAttributes[attrSlug],
            decoration: InputDecoration(
              labelText: attrName,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            isExpanded: true,
            items: options
                .map((option) => DropdownMenuItem(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (value) => _handleVariantSelection(attrSlug, value),
            validator: (value) => value == null ? 'Seleccione una opción' : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomActionBar() {
    final theme = Theme.of(context);
    final labelProvider = context.watch<LabelProvider>();
    final bool isEnabled =
        !labelProvider.printQueue.isEmpty && !labelProvider.isPrinting;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16,
          16 + MediaQuery.of(context).padding.bottom * 0.5),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2))
          ]),
      child: Row(
        children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: isEnabled
                      ? () {
                    context.read<LabelProvider>().clearQueue();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Cola de impresión limpiada.")));
                  }
                      : null,
                  child: const Text('Limpiar Cola'))),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: labelProvider.isPrinting
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: Text(
                  labelProvider.isPrinting ? "Procesando..." : "PROCEDER A IMPRIMIR"),
              onPressed: isEnabled ? _navigateToThermalScreen : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor:
                isEnabled ? theme.primaryColor : Colors.grey.shade400,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// lib/widgets/add_to_cart_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:collection/collection.dart';

import '../models/product.dart' as app_product;
import '../providers/order_notifier.dart';
import '../providers/shared_providers.dart';
import '../repositories/product_repository.dart';
import '../services/woocommerce_service.dart';
import '../locator.dart';
import '../config/constants.dart';
import 'quantity_selector.dart';

class AddToCartDialog extends ConsumerStatefulWidget {
  final String productId;

  const AddToCartDialog({super.key, required this.productId});

  @override
  ConsumerState<AddToCartDialog> createState() => _AddToCartDialogState();
}

class _AddToCartDialogState extends ConsumerState<AddToCartDialog> {
  app_product.Product? _product; // Siempre el producto padre si es variable
  bool _isLoadingProduct = true;
  String? _productLoadError;
  int _selectedQuantity = 1;
  final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');

  final Map<String, String?> _selectedAttributes = {};
  app_product.Product? _selectedVariationProduct;
  bool _isLoadingVariation = false;
  String? _variationError;
  final List<Map<String, dynamic>> _configurableAttributesUI = [];
  List<app_product.Product> _availableVariations = [];

  double _currentDisplayPrice = 0.0;
  double? _currentRegularPrice;
  bool _currentOnSale = false;
  String? _currentDisplayImageUrl;
  bool _currentIsAvailable = false;
  int _currentStockQuantity = 0;
  String _currentSku = '';

  final ProductRepository _productRepository = getIt<ProductRepository>();

  // ✅ NUEVO: Configuración para permitir cambiar variación después de escanear
  bool _allowChangeVariationAfterScan = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadProductData();
  }

  void _loadSettings() {
    final prefs = ref.read(sharedPreferencesProvider);
    _allowChangeVariationAfterScan = prefs.getBool(allowChangeVariationAfterScanPrefKey) ?? false;
  }

  Future<void> _loadProductData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProduct = true; _productLoadError = null; _variationError = null;
      _selectedVariationProduct = null; _isLoadingVariation = false;
      _selectedAttributes.clear(); _configurableAttributesUI.clear();
      _selectedQuantity = 1; _availableVariations.clear();
    });

    try {
      // ✅ FIX: Usar cache local (forceApi: false) para carga instantánea
      // El scanner ya encontró el producto localmente, no necesitamos API call
      final initialProduct = await _productRepository.getProductById(widget.productId, forceApi: false);
      if (!mounted) return;
      if (initialProduct == null) throw ProductNotFoundException(widget.productId);

      app_product.Product parentProduct;
      app_product.Product? initialVariant;

      if (initialProduct.isVariation && initialProduct.parentId != null) {
        // ✅ FIX: También usar cache local para el producto padre
        final loadedParent = await _productRepository.getProductById(initialProduct.parentId.toString(), forceApi: false);
        if (!mounted) return;
        if (loadedParent == null) throw ProductNotFoundException(initialProduct.parentId.toString());

        parentProduct = loadedParent;
        initialVariant = initialProduct;
      } else {
        parentProduct = initialProduct;
        initialVariant = initialProduct.isSimple ? initialProduct : null;
      }

      // Pre-cargar todas las variantes en segundo plano
      if (parentProduct.isVariable) {
        _productRepository.getAllVariations(parentProduct.id).then((variations) {
          if (mounted) {
            setState(() {
              _availableVariations = variations;
              // ✅ CONFIGURACIÓN: Buscar variación según preferencia del usuario
              // - Si _allowChangeVariationAfterScan: siempre buscar (permite cambiar atributos)
              // - Si NO: solo buscar si no hay variación seleccionada (preservar escaneada)
              if (_allowChangeVariationAfterScan || _selectedVariationProduct == null) {
                _findAndLoadMatchingVariation();
              }
            });
          }
        });
      }

      _product = parentProduct;
      _updateStateWithProductData(parentProduct, initialVariant: initialVariant);

    } catch (e) {
      if (mounted) {
        String errorMessage = "Error cargando: ${e.toString()}";
        if (e is ProductNotFoundException) {
          errorMessage = "Producto o variante no encontrado.";
        } else if (e is NetworkException) errorMessage = "Error de red al cargar el producto.";
        else if (e is ApiException) errorMessage = "Error de API: ${e.message}";
        setState(() => _productLoadError = errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoadingProduct = false);
    }
  }

  void _updateStateWithProductData(app_product.Product product, {app_product.Product? initialVariant}) {
    if (!mounted) return;

    _configurableAttributesUI.clear();
    _selectedAttributes.clear();
    _selectedVariationProduct = null;
    _variationError = null;

    if (product.isVariable && product.fullAttributesWithOptions != null && product.fullAttributesWithOptions!.isNotEmpty) {
      _prepareConfigurableAttributes(product);

      if (initialVariant != null && initialVariant.isVariation && initialVariant.attributes != null) {
        for (var variantAttr in initialVariant.attributes!) {
          final slug = variantAttr['slug']?.toString() ?? variantAttr['name']?.toString().toLowerCase();
          final option = variantAttr['option']?.toString();
          if (slug != null && option != null && _selectedAttributes.containsKey(slug)) {
            _selectedAttributes[slug] = option;
          }
        }
        _selectedVariationProduct = initialVariant;
      }
    } else {
      _selectedVariationProduct = initialVariant;
    }

    _updateDisplayData();
    _updateSelectedQuantityBasedOnStock();
  }

  void _prepareConfigurableAttributes(app_product.Product parentProduct) {
    _configurableAttributesUI.clear();
    _selectedAttributes.clear();
    if (parentProduct.fullAttributesWithOptions != null) {
      for (var attrJson in parentProduct.fullAttributesWithOptions!) {
        final String? uiName = attrJson['name']?.toString();
        final List<String> rawOpts = (attrJson['options'] as List<dynamic>?)
            ?.map((o) => o.toString())
            .where((o) => o.isNotEmpty)
            .toList() ?? [];

        // ✅ FIX: Deduplicate options here as well
        // After WordPress fix, duplicate option names may exist in the API response
        final List<String> opts = rawOpts.toSet().toList();

        if (uiName != null && uiName.isNotEmpty && opts.isNotEmpty) {
          String slug = attrJson['slug']?.toString() ?? uiName.toLowerCase().replaceAll(' ', '-');
          _configurableAttributesUI.add({'name': uiName, 'options': opts, 'slug': slug});
          _selectedAttributes[slug] = null;
        }
      }
    }
  }

  void _handleAttributeSelection(String attributeSlug, String? selectedOption) {
    if (!mounted) return;
    setState(() {
      _selectedAttributes[attributeSlug] = selectedOption;
      _selectedVariationProduct = null;
      _variationError = null;

      final changedAttrIndex = _configurableAttributesUI.indexWhere((attr) => attr['slug'] == attributeSlug);
      for (int i = changedAttrIndex + 1; i < _configurableAttributesUI.length; i++) {
        final slugToReset = _configurableAttributesUI[i]['slug'];
        _selectedAttributes[slugToReset] = null;
      }
    });

    _findAndLoadMatchingVariation();
  }

  List<String> _getAvailableOptionsForAttribute(String attributeSlug) {
    if (_product == null || !_product!.isVariable || _availableVariations.isEmpty) {
      final attrDef = _configurableAttributesUI.firstWhereOrNull((a) => a['slug'] == attributeSlug);
      final rawOptions = attrDef?['options'] as List<String>? ?? [];
      // ✅ FIX: Deduplicate options to prevent DropdownButton assertion error
      // After WordPress fix, same option names (e.g., "Rojo") may appear multiple times
      return rawOptions.toSet().toList()..sort();
    }

    List<app_product.Product> filteredVariations = List.from(_availableVariations);

    _selectedAttributes.forEach((slug, value) {
      if (slug != attributeSlug && value != null) {
        filteredVariations.retainWhere((variant) {
          return variant.attributes?.any((attr) =>
          (attr['slug'] == slug || attr['name'] == slug) && attr['option'] == value
          ) ?? false;
        });
      }
    });

    final options = <String>{};
    for (var variant in filteredVariations) {
      final attr = variant.attributes?.firstWhereOrNull((a) => a['slug'] == attributeSlug || a['name'] == attributeSlug);
      if (attr != null && attr['option'] != null) {
        options.add(attr['option']!);
      }
    }
    return options.toList()..sort();
  }

  void _findAndLoadMatchingVariation() {
    if (!mounted || _product == null || !_product!.isVariable) return;

    bool allRequiredOptionsSelected = _configurableAttributesUI.every((attr) => _selectedAttributes[attr['slug']] != null);

    if (!allRequiredOptionsSelected) {
      _updateDisplayData();
      _updateSelectedQuantityBasedOnStock();
      return;
    }

    if (_availableVariations.isEmpty) {
      setState(() => _isLoadingVariation = true);
      return;
    }

    final matchingVariant = _availableVariations.firstWhereOrNull((variant) {
      if (variant.attributes == null) return false;
      return _selectedAttributes.entries.every((selectedAttr) {
        final selectedKeyLower = selectedAttr.key.toLowerCase();
        final selectedValueLower = selectedAttr.value?.toLowerCase();
        if (selectedValueLower == null) return false;

        return variant.attributes!.any((variantAttr) {
          final apiSlugLower = variantAttr['slug']?.toString().toLowerCase();
          final apiNameLower = variantAttr['name']?.toString().toLowerCase();
          final apiOptionLower = variantAttr['option']?.toString().toLowerCase();

          final bool keyMatches = (apiSlugLower == selectedKeyLower || (apiSlugLower?.replaceFirst('attribute_', '') ?? '') == selectedKeyLower) || (apiNameLower == selectedKeyLower);
          final bool optionMatches = apiOptionLower == selectedValueLower;

          return keyMatches && optionMatches;
        });
      });
    });

    if (!mounted) return;
    setState(() {
      _isLoadingVariation = false;
      if (matchingVariant != null) {
        if (matchingVariant.isAvailable) {
          _selectedVariationProduct = matchingVariant;
          _variationError = null;
        } else {
          _selectedVariationProduct = null;
          _variationError = "Esta combinación está agotada o no disponible.";
        }
      } else {
        _selectedVariationProduct = null;
        _variationError = "Combinación de atributos no encontrada.";
      }
      _updateDisplayData();
      _updateSelectedQuantityBasedOnStock();
    });
  }

  void _updateDisplayData() {
    if (!mounted) return;
    final productToDisplay = _selectedVariationProduct ?? _product;

    // ✅ FIX: Calcular stock disponible real (descontando lo que ya está en el pedido)
    int stockReal = productToDisplay?.stockQuantity ?? (productToDisplay?.manageStock ?? false ? 0 : -1);

    if (stockReal != -1 && productToDisplay != null) {
      // Obtener cantidad ya en el pedido actual
      final orderState = ref.read(currentOrderProvider);
      if (orderState.hasValue) {
        final currentOrder = orderState.value?.order;
        if (currentOrder != null) {
          final uniqueItemId = productToDisplay.isVariation
              ? '${productToDisplay.parentId}_${productToDisplay.id}'
              : productToDisplay.id;

          final existingItem = currentOrder.items.firstWhereOrNull(
            (item) {
              final itemUniqueId = item.variationId != null
                  ? '${item.productId}_${item.variationId}'
                  : item.productId;
              return itemUniqueId == uniqueItemId;
            },
          );

          if (existingItem != null) {
            // Restar cantidad ya en pedido del stock disponible
            stockReal = (stockReal - existingItem.quantity).clamp(0, stockReal);
            debugPrint("[AddToCartDialog] 📦 Stock apartado: ${existingItem.quantity} unidades en pedido");
            debugPrint("[AddToCartDialog] ✅ Stock disponible real: $stockReal unidades");
          }
        }
      }
    }

    setState(() {
      _currentDisplayPrice = productToDisplay?.displayPrice ?? 0.0;
      _currentRegularPrice = productToDisplay?.regularPrice;
      _currentOnSale = productToDisplay?.onSale ?? false;
      _currentDisplayImageUrl = productToDisplay?.displayImageUrl;
      _currentIsAvailable = productToDisplay?.isAvailable ?? false;
      _currentStockQuantity = stockReal; // ✅ Usar stock real (ya descontado)
      _currentSku = productToDisplay?.sku ?? '';
    });
  }

  void _updateSelectedQuantityBasedOnStock() {
    if (!mounted) return;
    final productToDisplay = _selectedVariationProduct ?? _product;
    int newQuantity = _selectedQuantity;

    if (productToDisplay == null || !_currentIsAvailable) {
      newQuantity = 0;
    } else if (productToDisplay.manageStock) {
      final stock = productToDisplay.stockQuantity ?? 0;
      if (stock <= 0) {
        newQuantity = 0;
      } else {
        if (newQuantity > stock) newQuantity = stock;
        if (newQuantity <= 0 && stock > 0) newQuantity = 1;
      }
    } else {
      if (newQuantity <= 0) newQuantity = 1;
    }

    if (_selectedQuantity != newQuantity) {
      setState(() => _selectedQuantity = newQuantity);
    }
  }

  Future<void> _addToCart() async {
    if (!mounted) return;
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    final productToAdd = _selectedVariationProduct ?? _product;

    if (productToAdd == null || _selectedQuantity <= 0 || !_currentIsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_selectedQuantity <= 0 ? 'Seleccione una cantidad válida.' : 'Producto/Variante no disponible.'), backgroundColor: Colors.orange),
      );
      return;
    }

    List<Map<String, String>>? attributesForOrder;
    if (_selectedVariationProduct != null && _selectedVariationProduct!.attributes != null) {
      attributesForOrder = _selectedVariationProduct!.attributes!.map((attr) {
        return <String,String>{
          'name': attr['name']?.toString() ?? '',
          'option': attr['option']?.toString() ?? '',
          'slug': attr['slug']?.toString() ?? (attr['name']?.toString() ?? '').toLowerCase().replaceAll(' ', '-')
        };
      }).toList();
    }

    try {
      await orderNotifier.addProduct(
        productToAdd,
        _selectedQuantity,
        explicitAttributes: attributesForOrder,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${productToAdd.name}" x$_selectedQuantity agregado.'), duration: const Duration(seconds: 2), backgroundColor: Colors.green.shade700),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString();

      // ✅ FIX: Detectar error de stock insuficiente y mostrar diálogo con opciones
      if (errorMessage.contains('Stock insuficiente')) {
        // Extraer información del error: "Stock insuficiente para 'Nombre'. Disponible: X. Solicitado en total: Y"
        final RegExp regExp = RegExp(r"Disponible: (\d+)\. Solicitado en total: (\d+)");
        final match = regExp.firstMatch(errorMessage);

        int? stockDisponible;
        int? stockSolicitado;

        if (match != null) {
          stockDisponible = int.tryParse(match.group(1) ?? '');
          stockSolicitado = int.tryParse(match.group(2) ?? '');
        }

        await _showStockInsuficienteDialog(
          productToAdd,
          stockDisponible,
          stockSolicitado,
          attributesForOrder,
        );
      } else {
        // Otro tipo de error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage.replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _showStockInsuficienteDialog(
    app_product.Product product,
    int? stockDisponible,
    int? stockSolicitado,
    List<Map<String, String>>? attributesForOrder,
  ) async {
    if (!mounted) return;

    final orderNotifier = ref.read(currentOrderProvider.notifier);
    final orderState = ref.read(currentOrderProvider);

    // Calcular cantidad actual en el carrito
    int cantidadEnCarrito = 0;
    if (orderState.hasValue) {
      final currentOrder = orderState.value?.order;
      if (currentOrder != null) {
        final uniqueItemId = product.isVariation
            ? '${product.parentId}_${product.id}'
            : product.id;

        final existingItem = currentOrder.items.firstWhereOrNull(
          (item) {
            final itemUniqueId = item.variationId != null
                ? '${item.productId}_${item.variationId}'
                : item.productId;
            return itemUniqueId == uniqueItemId;
          },
        );

        if (existingItem != null) {
          cantidadEnCarrito = existingItem.quantity;
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('Stock Insuficiente')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No hay suficiente stock para "${product.name}"',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 16),
            if (stockDisponible != null && stockSolicitado != null) ...[
              _buildInfoRow('Stock disponible:', '$stockDisponible unidades'),
              const SizedBox(height: 8),
              _buildInfoRow('Ya en pedido:', '$cantidadEnCarrito unidades'),
              const SizedBox(height: 8),
              _buildInfoRow('Intentando agregar:', '${stockSolicitado - cantidadEnCarrito} unidades'),
              const SizedBox(height: 8),
              _buildInfoRow('Total solicitado:', '$stockSolicitado unidades', isError: true),
            ] else ...[
              Text('Stock disponible: ${stockDisponible ?? "Desconocido"}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCELAR'),
          ),
          if (cantidadEnCarrito > 0)
            TextButton(
              onPressed: () async {
                // Eliminar producto del pedido
                final uniqueItemId = product.isVariation
                    ? '${product.parentId}_${product.id}'
                    : product.id;

                await orderNotifier.removeItem(uniqueItemId);

                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Producto eliminado del pedido'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('ELIMINAR DEL PEDIDO'),
            ),
          if (stockDisponible != null && stockDisponible > cantidadEnCarrito)
            ElevatedButton(
              onPressed: () async {
                // Ajustar a máximo disponible
                final cantidadParaAgregar = stockDisponible - cantidadEnCarrito;

                try {
                  await orderNotifier.addProduct(
                    product,
                    cantidadParaAgregar,
                    explicitAttributes: attributesForOrder,
                  );

                  if (mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ajustado a máximo disponible: ${stockDisponible} unidades'),
                        backgroundColor: Colors.green.shade700,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    Navigator.of(context).pop(); // Cerrar AddToCartDialog
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text('AJUSTAR A MÁXIMO ($stockDisponible)'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isError = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isError ? Colors.red.shade700 : Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    if (_isLoadingProduct && _product == null) {
      return const _LoadingDialogContent(message: "Cargando producto...");
    }
    if (_productLoadError != null && _product == null) {
      return WillPopScope(onWillPop: () => Future.value(true), child: _ErrorDialogContent(errorMessage: _productLoadError!));
    }
    if (_product == null) {
      return WillPopScope(onWillPop: () => Future.value(true), child: const _ErrorDialogContent(errorMessage: "Error inesperado al cargar producto."));
    }

    final productForDisplay = _selectedVariationProduct ?? _product!;

    bool canAddToCart = _currentIsAvailable && _selectedQuantity > 0;
    if (_product!.isVariable && _configurableAttributesUI.isNotEmpty && _selectedVariationProduct == null) {
      canAddToCart = false;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(productForDisplay.name, style: theme.textTheme.titleLarge?.copyWith(fontSize: 18), maxLines: 2, overflow: TextOverflow.ellipsis ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox( width: double.maxFinite, child: ConstrainedBox( constraints: BoxConstraints(maxHeight: screenSize.height * 0.65), child: SingleChildScrollView(
        child: Column( mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container( width: 80, height: 80, clipBehavior: Clip.antiAlias, decoration: BoxDecoration( borderRadius: BorderRadius.circular(8), color: Colors.grey.shade200, ), child: CachedNetworkImage( key: ValueKey("${productForDisplay.id}_${_currentDisplayImageUrl ?? 'noimg'}"), imageUrl: _currentDisplayImageUrl ?? '', fit: BoxFit.cover, placeholder: (c, u) => const Center(child: Icon(Icons.image_outlined, color: Colors.grey)), errorWidget: (c, u, e) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)), ), ), const SizedBox(width: 12),
            Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row( crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [ Flexible( child: Text( currencyFormat.format(_currentDisplayPrice), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: _currentOnSale ? theme.primaryColor : Colors.black87), softWrap: false, overflow: TextOverflow.fade, ), ), if (_currentOnSale && _currentRegularPrice != null && (_currentRegularPrice! - _currentDisplayPrice).abs() > 0.01) Flexible( child: Padding( padding: const EdgeInsets.only(left: 6.0), child: Text( currencyFormat.format(_currentRegularPrice), style: theme.textTheme.titleMedium?.copyWith( color: Colors.grey.shade500, decoration: TextDecoration.lineThrough, fontSize: 13 ), softWrap: false, overflow: TextOverflow.fade, ), ), ), ], ), const SizedBox(height: 6),
              if (_currentSku.isNotEmpty) Text("SKU: $_currentSku", style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
              Padding( padding: const EdgeInsets.only(top: 4.0), child: (_isLoadingProduct || _isLoadingVariation) ? Row(mainAxisSize: MainAxisSize.min, children: [ const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 1.5)), const SizedBox(width: 4), Text(_isLoadingProduct ? "Cargando..." : "Verificando...", style: theme.textTheme.bodySmall?.copyWith(color: Colors.blueGrey)) ]) : Text( _currentIsAvailable ? (_currentStockQuantity == -1 ? "Disponible" : "Stock: $_currentStockQuantity") : "Agotado", style: theme.textTheme.bodySmall?.copyWith(color: _currentIsAvailable ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis, ), ),
            ], ), ),
          ],
          ),
          if (_product!.isVariable && _configurableAttributesUI.isNotEmpty) ...[
            const Divider(height: 24),
            ..._configurableAttributesUI.map((attr) => _buildAttributeSelector(attr)),
            if (_variationError != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_variationError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
          ],
          const SizedBox(height:12),
          Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text('Cantidad:', style: theme.textTheme.titleMedium), QuantitySelector(
            // 🔥 SOLUCIÓN 1: Eliminamos la cantidad de la KEY
            // Antes: ValueKey('${productForDisplay.id}_qtySelector_$_selectedQuantity')
            // Ahora: La key es estable para el producto. Si escribes "1", el estado se actualiza en el padre
            // pero el widget QuantitySelector NO se reconstruye desde cero, manteniendo el foco.
            key: ValueKey('${productForDisplay.id}_qtySelector'),
            value: _selectedQuantity,
            minValue: 0,
            maxValue: _currentIsAvailable ? (_currentStockQuantity == -1 ? 9999 : _currentStockQuantity) : 0,
            onChanged: (value) { if (mounted) setState(() => _selectedQuantity = value); },
          ),
          ],
          ), const SizedBox(height: 8),
        ],
        ),
      ),
      ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton( child: const Text("CANCELAR"), onPressed: () => Navigator.of(context).pop(), ),
              ElevatedButton.icon( icon: const Icon(Icons.add_shopping_cart, size: 18), label: const Text("AGREGAR"),
                onPressed: canAddToCart ? _addToCart : null,
                style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), ),
              ),
            ]
        )
      ],
    );
  }

  Widget _buildAttributeSelector(Map<String, dynamic> attrDef) {
    final String attributeUiName = attrDef['name']?.toString() ?? 'Atributo';
    final String attributeSlug = attrDef['slug']?.toString() ?? attributeUiName.toLowerCase().replaceAll(' ', '-');

    final List<String> options = _getAvailableOptionsForAttribute(attributeSlug);
    final String? currentSelectionForThisAttr = _selectedAttributes[attributeSlug];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$attributeUiName:", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            value: (options.contains(currentSelectionForThisAttr)) ? currentSelectionForThisAttr : null,
            hint: const Text("Seleccionar..."),
            isExpanded: true,
            items: options.map((option) => DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (_isLoadingVariation || options.isEmpty) ? null : (value) {
              _handleAttributeSelection(attributeSlug, value!);
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingDialogContent extends StatelessWidget {
  final String message;
  const _LoadingDialogContent({this.message = "Cargando..."});
  @override Widget build(BuildContext context) { return Dialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Padding(padding: const EdgeInsets.all(20.0), child: Row(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(width:20), Text(message)]) ) ); }
}

class _ErrorDialogContent extends StatelessWidget {
  final String errorMessage;
  const _ErrorDialogContent({required this.errorMessage});
  @override Widget build(BuildContext context) { return AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), title: const Row(children: [Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 8), Text("Error")]), content: SizedBox( width: double.maxFinite, child: Text(errorMessage, textAlign: TextAlign.center,) ), actions: [ TextButton( onPressed: () => Navigator.pop(context), child: const Text("CERRAR") ) ], ); }
}
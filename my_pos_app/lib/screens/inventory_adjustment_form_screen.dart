// lib/screens/inventory_adjustment_form_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../models/product.dart' as app_product;
import '../models/inventory_movement.dart';
import '../models/label_print_item.dart';
import '../providers/inventory_provider.dart';
import '../providers/label_provider.dart';
import '../providers/app_state_provider.dart';
import '../repositories/product_repository.dart';
import '../locator.dart';
import '../widgets/app_header.dart';
import '../widgets/quantity_selector.dart';
import '../models/inventory_movement_extensions.dart';
import '../config/routes.dart';

class InventoryAdjustmentFormScreenArguments {
  final String operationType;
  final String? initialReasonValue;
  final app_product.Product? initialProduct;

  InventoryAdjustmentFormScreenArguments({
    required this.operationType,
    this.initialReasonValue,
    this.initialProduct,
  });
}

class InventoryAdjustmentFormScreen extends StatefulWidget {
  final InventoryAdjustmentFormScreenArguments? arguments;

  const InventoryAdjustmentFormScreen({Key? key, this.arguments}) : super(key: key);

  @override
  State<InventoryAdjustmentFormScreen> createState() =>
      _InventoryAdjustmentFormScreenState();
}

class _InventoryAdjustmentFormScreenState
    extends State<InventoryAdjustmentFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _productSearchInputController = TextEditingController();
  final FocusNode _productSearchInputFocusNode = FocusNode();
  Timer? _productSearchDebounce;

  final ValueNotifier<List<app_product.Product>> _searchResultsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> _searchErrorNotifier = ValueNotifier(null);
  final ScrollController _searchResultsScrollController = ScrollController();

  app_product.Product? _currentFoundProduct;
  app_product.Product? _currentResolvedVariant;
  Map<String, String?> _currentSelectedAttributes = {};
  List<Map<String, dynamic>> _configurableAttributesUI = [];
  List<app_product.Product> _availableVariations = [];
  bool _isLoadingProductDetails = false;
  String? _currentProductError;

  int _currentQuantity = 1;
  int _newTotalStock = 0;
  bool _isCurrentItemEntry = true;

  final List<InventoryMovementLine> _massAdjustmentBatch = [];
  InventoryMovementType _overallMovementType = InventoryMovementType.massManualAdjustment;
  final TextEditingController _overallMovementDescriptionController = TextEditingController();

  bool _isSavingBatch = false;
  MobileScannerController? _cameraScannerController;
  int? _editingBatchItemIndex;
  Timer? _cacheSaveDebounce;
  bool _sendPositiveAdjustmentsToLabelQueue = false;

  bool get _isStockTakeMode => _overallMovementType == InventoryMovementType.stockCorrection;
  bool get _isEntryMode {
    switch (_overallMovementType) {
      case InventoryMovementType.initialStock:
      case InventoryMovementType.stockReceipt:
      case InventoryMovementType.transferIn:
      case InventoryMovementType.massEntry:
      case InventoryMovementType.supplierReceipt:
      case InventoryMovementType.refund:
      case InventoryMovementType.customerReturnMass:
        return true;
      default:
        return false;
    }
  }
  bool get _isExitMode {
    switch (_overallMovementType) {
      case InventoryMovementType.sale:
      case InventoryMovementType.damageOrLoss:
      case InventoryMovementType.transferOut:
      case InventoryMovementType.massExit:
      case InventoryMovementType.toTrash:
        return true;
      default:
        return false;
    }
  }

  String get _screenTitle {
    if (_isEntryMode) return 'Registrar Entrada de Inventario';
    if (_isExitMode) return 'Registrar Salida de Inventario';
    if (_isStockTakeMode) return 'Conteo/Ajuste Físico de Stock';
    return 'Ajuste de Inventario';
  }

  @override
  void initState() {
    super.initState();
    _productSearchInputController.addListener(_onProductSearchChanged);
    _overallMovementDescriptionController.addListener(_triggerCacheSave);

    _searchResultsScrollController.addListener(() {
      if (_productSearchInputFocusNode.hasFocus && _searchResultsScrollController.position.isScrollingNotifier.value) {
        _productSearchInputFocusNode.unfocus();
      }
    });

    _initializeMovementType();

    if (widget.arguments?.initialProduct != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _processFoundProductDetails(widget.arguments!.initialProduct!, fromScanOrDirectCode: true);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<InventoryProvider>().loadCachedAdjustment().then((cachedData) {
          if (mounted && cachedData != null) {
            _showResumeFromCacheDialog(cachedData.description, cachedData.items);
          }
        });

        if (widget.arguments?.initialProduct == null) {
          FocusScope.of(context).requestFocus(_productSearchInputFocusNode);
        }
      }
    });
  }

  void _initializeMovementType() {
    if (widget.arguments == null) {
      _overallMovementType = InventoryMovementType.manualAdjustment;
      _updateOperationModeFromType(_overallMovementType);
      return;
    }

    final args = widget.arguments!;
    InventoryMovementType initialType = InventoryMovementType.manualAdjustment;

    if (args.initialReasonValue != null) {
      try {
        initialType = InventoryMovementType.values.firstWhere((e) => e.name == args.initialReasonValue);
      } catch (e) {
        if (kDebugMode) print("[InventoryForm] Error parsing initialReasonValue '${args.initialReasonValue}': $e");
      }
    } else {
      switch (args.operationType) {
        case 'entry':
          initialType = InventoryMovementType.supplierReceipt;
          break;
        case 'exit':
          initialType = InventoryMovementType.damageOrLoss;
          break;
        case 'stockTake':
          initialType = InventoryMovementType.stockCorrection;
          break;
      }
    }
    _overallMovementType = initialType;
    _updateOperationModeFromType(initialType);
  }

  void _updateOperationModeFromType(InventoryMovementType type) {
    setState(() {
      _overallMovementType = type;
      if (_isEntryMode) {
        _isCurrentItemEntry = true;
      } else if (_isExitMode) {
        _isCurrentItemEntry = false;
      }
    });
  }

  bool _shouldShowPrintOption() {
    switch (_overallMovementType) {
      case InventoryMovementType.manualAdjustment:
      case InventoryMovementType.initialStock:
      case InventoryMovementType.stockReceipt:
      case InventoryMovementType.stockCorrection:
      case InventoryMovementType.transferIn:
      case InventoryMovementType.massEntry:
      case InventoryMovementType.supplierReceipt:
      case InventoryMovementType.massManualAdjustment:
      case InventoryMovementType.customerReturnMass:
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _productSearchInputController.removeListener(_onProductSearchChanged);
    _overallMovementDescriptionController.removeListener(_triggerCacheSave);
    _productSearchInputController.dispose();
    _productSearchInputFocusNode.dispose();
    _productSearchDebounce?.cancel();
    _cacheSaveDebounce?.cancel();
    _overallMovementDescriptionController.dispose();
    _cameraScannerController?.dispose();
    _searchResultsScrollController.dispose();
    _searchResultsNotifier.dispose();
    _isSearchingNotifier.dispose();
    _searchErrorNotifier.dispose();
    super.dispose();
  }

  void _triggerCacheSave() {
    _cacheSaveDebounce?.cancel();
    _cacheSaveDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted && _massAdjustmentBatch.isNotEmpty) {
        context.read<InventoryProvider>().cacheAdjustment(
          _overallMovementDescriptionController.text,
          _massAdjustmentBatch,
        );
      }
    });
  }

  void _showResumeFromCacheDialog(String description, List<InventoryMovementLine> items) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Ajuste sin finalizar encontrado"),
        content: Text("Encontramos un ajuste de inventario con ${items.length} producto(s) que no fue guardado. ¿Deseas continuar con él?"),
        actions: [
          TextButton(
            child: const Text("Descartar"),
            onPressed: () {
              context.read<InventoryProvider>().clearCachedAdjustment();
              Navigator.pop(dialogContext);
            },
          ),
          ElevatedButton(
            child: const Text("Continuar"),
            onPressed: () {
              setState(() {
                _overallMovementDescriptionController.text = description;
                _massAdjustmentBatch.addAll(items);
              });
              Navigator.pop(dialogContext);
            },
          ),
        ],
      ),
    );
  }

  void _onProductSearchChanged() {
    if (_productSearchDebounce?.isActive ?? false) _productSearchDebounce!.cancel();
    final searchTerm = _productSearchInputController.text.trim();
    if (searchTerm.isEmpty) {
      _searchResultsNotifier.value = [];
      _searchErrorNotifier.value = null;
      setState(() {
        _clearCurrentProductSelection(resetSearchFieldAndResults: false);
      });
      return;
    }
    _productSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _productSearchInputController.text.trim() == searchTerm && searchTerm.length >=2) {
        _searchProduct(searchTerm, isDirectCodeSearch: false);
      }
    });
  }

  Future<void> _searchProduct(String term, {required bool isDirectCodeSearch}) async {
    if (!mounted) return;

    if (isDirectCodeSearch) {
      setState(() {
        _isLoadingProductDetails = true;
        _currentProductError = null;
        _currentFoundProduct = null;
        _currentResolvedVariant = null;
        _currentSelectedAttributes.clear();
        _searchResultsNotifier.value = [];
      });
    } else {
      _isSearchingNotifier.value = true;
      _searchErrorNotifier.value = null;
    }

    final appState = context.read<AppStateProvider>();
    if (appState.connectionStatus == ConnectionStatus.offline) {
      final errorMsg = "Sin conexión para buscar producto.";
      if (isDirectCodeSearch) {
        if(mounted) setState(() { _currentProductError = errorMsg; _isLoadingProductDetails = false; });
      } else {
        _searchErrorNotifier.value = errorMsg;
        _isSearchingNotifier.value = false;
      }
      return;
    }

    try {
      if (isDirectCodeSearch) {
        final product = await getIt<ProductRepository>().searchProductByBarcodeOrSku(term, searchOnlyAvailable: !_isStockTakeMode);
        if (!mounted) return;
        if (product != null) {
          await _processFoundProductDetails(product, fromScanOrDirectCode: true);
        } else {
          if (mounted) setState(() {
            _currentProductError = "Producto no encontrado con código: $term";
            _isLoadingProductDetails = false;
          });
        }
      } else {
        if (term.length < 2) {
          _searchErrorNotifier.value = "Término de búsqueda muy corto (mín. 2).";
          _isSearchingNotifier.value = false;
          return;
        }
        final apiResponse = await getIt<ProductRepository>().searchProductsByTerm(term, limit: 25, searchOnlyAvailable: !_isStockTakeMode);
        final List<app_product.Product> nameResults = (apiResponse['products'] as List?)
            ?.map((p) => p as app_product.Product)
            .toList() ?? [];

        if (!mounted) return;
        _searchResultsNotifier.value = nameResults;
        if (nameResults.isEmpty) {
          _searchErrorNotifier.value = "No se encontraron productos para: '$term'";
        } else {
          _searchErrorNotifier.value = null;
        }
      }
    } catch (e) {
      final errorMsg = "Error buscando: ${e.toString()}";
      if(isDirectCodeSearch) {
        if(mounted) setState(() => _currentProductError = errorMsg);
      } else {
        _searchErrorNotifier.value = errorMsg;
      }
    } finally {
      if (mounted) {
        if (isDirectCodeSearch) {
          setState(() => _isLoadingProductDetails = false);
        } else {
          _isSearchingNotifier.value = false;
        }
      }
    }
  }

  Future<void> _processFoundProductDetails(app_product.Product productFromSearch, {bool fromScanOrDirectCode = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoadingProductDetails = true;
      _currentProductError = null;
      if (fromScanOrDirectCode) {
        _productSearchInputController.text = productFromSearch.name;
      }
      _searchResultsNotifier.value = [];
      _availableVariations.clear();
      FocusScope.of(context).unfocus();
    });

    try {
      final bool needsDetails = productFromSearch.isVariable &&
          (productFromSearch.fullAttributesWithOptions == null || productFromSearch.fullAttributesWithOptions!.isEmpty);

      final productToProcess = needsDetails
          ? await getIt<ProductRepository>().getProductById(productFromSearch.id, forceApi: true)
          : productFromSearch;

      if (!mounted) return;
      if (productToProcess == null) throw Exception("Producto no encontrado.");

      if (productToProcess.isVariable) {
        _availableVariations = await getIt<ProductRepository>().getAllVariations(productToProcess.id);
      }

      if (!mounted) return;
      _updateStateAfterProductLoad(productToProcess, fromScanOrDirectCode: fromScanOrDirectCode);

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentProductError = "Error al obtener detalles del producto: ${e.toString()}";
        _isLoadingProductDetails = false;
      });
    }
  }

  void _updateStateAfterProductLoad(app_product.Product product, {bool fromScanOrDirectCode = false}) {
    if (!mounted) return;

    setState(() {
      _currentProductError = null;
      _currentFoundProduct = product;
      _configurableAttributesUI = [];

      if (fromScanOrDirectCode) {
        _productSearchInputController.text = product.name;
      }
      _searchResultsNotifier.value = [];

      if (product.isVariable) {
        _currentResolvedVariant = null;
        _currentSelectedAttributes.clear();
        if (product.fullAttributesWithOptions != null && product.fullAttributesWithOptions!.isNotEmpty) {
          for (var attrDef in product.fullAttributesWithOptions!) {
            final String? uiName = attrDef['name']?.toString();
            final List<String> opts = (attrDef['options'] as List<dynamic>?)
                ?.map((o) => o.toString())
                .where((o) => o.isNotEmpty)
                .toList() ?? [];

            if (uiName != null && uiName.isNotEmpty && opts.isNotEmpty) {
              String slug = attrDef['slug']?.toString() ?? uiName.toLowerCase().replaceAll(' ', '-');
              _configurableAttributesUI.add({'name': uiName, 'options': opts, 'slug': slug});
              _currentSelectedAttributes[slug] = null;
            }
          }
          _currentProductError = null;
        } else {
          _currentProductError = "Este producto variable no tiene opciones de atributos configurables.";
        }
      } else {
        _currentResolvedVariant = product;
        _currentProductError = null;
      }

      final productForStock = _currentResolvedVariant ?? _currentFoundProduct;
      if (productForStock != null) {
        if (_isStockTakeMode) {
          _newTotalStock = productForStock.stockQuantity ?? 0;
        } else {
          _currentQuantity = 1;
        }
      } else {
        if (_isStockTakeMode) _newTotalStock = 0; else _currentQuantity = 1;
        _currentProductError = _currentProductError ?? "No se pudo determinar el producto para el stock.";
      }
      _isLoadingProductDetails = false;
    });
  }

  Future<void> _scanBarcodeAndSearch() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    var cameraPermissionStatus = await Permission.camera.status;
    if (cameraPermissionStatus.isDenied || cameraPermissionStatus.isRestricted) {
      cameraPermissionStatus = await Permission.camera.request();
    }

    if (!mounted) return;
    if (cameraPermissionStatus.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permiso de cámara denegado permanentemente. Habilítelo en ajustes."), backgroundColor: Colors.red, duration: Duration(seconds: 5)),
      );
      await openAppSettings();
      return;
    }
    if (!cameraPermissionStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permiso de cámara necesario para escanear."), backgroundColor: Colors.orange),
      );
      return;
    }

    final String? scannedCode = await _showCameraScannerDialog();

    if (scannedCode != null && scannedCode.isNotEmpty && mounted) {
      await _searchProduct(scannedCode, isDirectCodeSearch: true);
    } else if (mounted && scannedCode != null && scannedCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se detectó un código válido."), backgroundColor: Colors.orange)
      );
    }
  }

  Future<String?> _showCameraScannerDialog() async {
    if (_cameraScannerController != null) {
      try { _cameraScannerController!.dispose(); } catch (e) { if (kDebugMode) print("Error disposing existing camera controller: $e"); }
      _cameraScannerController = null;
    }
    _cameraScannerController = MobileScannerController( detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back, torchEnabled: false, detectionTimeoutMs: 2000, );
    String? result;
    bool popped = false;
    bool isTorchOn = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Escanear Código de Barras', style: TextStyle(fontSize: 18)),
              contentPadding: const EdgeInsets.fromLTRB(0,12,0,0),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width * 0.9,
                height: MediaQuery.of(dialogContext).size.height * 0.45,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: MobileScanner(
                    key: ValueKey('inventory_adj_scanner_${DateTime.now().millisecondsSinceEpoch}'),
                    controller: _cameraScannerController!,
                    onDetect: (capture) {
                      if (popped || !mounted || !Navigator.of(dialogContext).canPop()) return;
                      final firstValidBarcode = capture.barcodes.firstWhere((b) => b.rawValue != null && b.rawValue!.isNotEmpty, orElse: () => const Barcode(rawValue: null));
                      if (firstValidBarcode.rawValue != null) {
                        result = firstValidBarcode.rawValue;
                        _cameraScannerController?.stop().catchError((e) => print("Error stopping camera in onDetect: $e"));
                        popped = true;
                        if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop(result);
                      }
                    },
                    errorBuilder: (context, error) {
                      return Center(child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text("Error de cámara: ${error.errorCode.name}.\nVerifique permisos y reinicie.", style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
                      ));
                    },
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              actions: <Widget>[
                IconButton(
                  icon: Icon(isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: isTorchOn ? Colors.amber.shade600 : Theme.of(dialogContext).iconTheme.color),
                  tooltip: "Linterna",
                  onPressed: () async {
                    await _cameraScannerController?.toggleTorch();
                    setDialogState(() {
                      isTorchOn = !isTorchOn;
                    });
                  },
                ),
                TextButton(
                  child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    if (popped || !mounted || !Navigator.of(dialogContext).canPop()) return;
                    popped = true;
                    _cameraScannerController?.stop().then((_) {
                      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                    }).catchError((e){
                      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((value) {
      if (_cameraScannerController != null) {
        try { _cameraScannerController!.dispose(); } catch(e) { if (kDebugMode) print("Error disposing camera controller in .then(): $e"); }
        _cameraScannerController = null;
      }
      return value;
    });
  }

  void _handleAttributeSelection(String attributeSlug, String? selectedOption) {
    if (!mounted || _currentFoundProduct == null || !_currentFoundProduct!.isVariable) return;

    setState(() {
      _currentSelectedAttributes[attributeSlug] = selectedOption;
      _currentResolvedVariant = null;
      _currentProductError = null;

      final changedAttrIndex = _configurableAttributesUI.indexWhere((attr) => attr['slug'] == attributeSlug);
      for (int i = changedAttrIndex + 1; i < _configurableAttributesUI.length; i++) {
        final slugToReset = _configurableAttributesUI[i]['slug'];
        _currentSelectedAttributes[slugToReset] = null;
      }

      _findAndLoadMatchingVariation();
    });
  }

  void _findAndLoadMatchingVariation() {
    if (!mounted || _currentFoundProduct == null) return;

    final allAttributesSelected = _configurableAttributesUI.every((attr) => _currentSelectedAttributes[attr['slug']] != null);

    if (allAttributesSelected) {
      final matchingVariant = _availableVariations.firstWhereOrNull((variant) {
        return _currentSelectedAttributes.entries.every((selectedAttr) {
          final selectedKey = selectedAttr.key;
          final selectedValue = selectedAttr.value;
          return variant.attributes?.any((variantAttr) =>
          (variantAttr['slug'] == selectedKey || variantAttr['name'] == selectedKey) && variantAttr['option'] == selectedValue
          ) ?? false;
        });
      });

      setState(() {
        _currentResolvedVariant = matchingVariant;
        _currentProductError = (matchingVariant == null) ? "Combinación de variante no encontrada." : null;
      });
    } else {
      setState(() {
        _currentResolvedVariant = null;
      });
    }
  }

  void _clearCurrentProductSelection({bool resetSearchFieldAndResults = true, bool keepParentProduct = false}) {
    if (!mounted) return;
    setState(() {
      if (!keepParentProduct) {
        _currentFoundProduct = null;
        if (resetSearchFieldAndResults) {
          _productSearchInputController.clear();
          _searchResultsNotifier.value = [];
        }
      }

      _currentResolvedVariant = null;
      _currentSelectedAttributes.clear();

      if (keepParentProduct && _currentFoundProduct != null && _currentFoundProduct!.isVariable) {
        if (_currentFoundProduct!.fullAttributesWithOptions != null) {
          for (var attr in _currentFoundProduct!.fullAttributesWithOptions!) {
            final String? attrSlug = attr['slug'] as String?;
            if (attrSlug != null) _currentSelectedAttributes[attrSlug] = null;
          }
        }
      }

      if (_isStockTakeMode) {
        _newTotalStock = _currentFoundProduct?.stockQuantity ?? 0;
      } else {
        _currentQuantity = 1;
      }

      _currentProductError = null;
      _isLoadingProductDetails = false;
      _editingBatchItemIndex = null;
    });
  }

  Future<void> _loadBatchItemForEditing(InventoryMovementLine itemToEdit, int index) async {
    if (!mounted) return;
    setState(() {
      _isLoadingProductDetails = true;
      _currentProductError = null;
      _editingBatchItemIndex = index;
      _searchResultsNotifier.value = [];
      FocusScope.of(context).unfocus();
    });

    try {
      app_product.Product? loadedProductDetails;
      app_product.Product? parentProductForUi;

      if (itemToEdit.variationId != null && itemToEdit.variationId!.isNotEmpty) {
        loadedProductDetails = await getIt<ProductRepository>().getVariationById(
            itemToEdit.productId, itemToEdit.variationId!, forceApi: true);

        if (loadedProductDetails?.parentId != null) {
          parentProductForUi = await getIt<ProductRepository>().getProductById(
              loadedProductDetails!.parentId.toString(), forceApi: true);
        } else if (loadedProductDetails == null) {
          parentProductForUi = await getIt<ProductRepository>().getProductById(itemToEdit.productId, forceApi: true);
        }
      } else {
        loadedProductDetails = await getIt<ProductRepository>().getProductById(itemToEdit.productId, forceApi: true);
        parentProductForUi = loadedProductDetails;
      }

      if (!mounted) return;

      if (loadedProductDetails == null) {
        setState(() {
          _currentProductError = "No se pudo recargar el producto '${itemToEdit.productName}' para edición.";
          _editingBatchItemIndex = null;
          _isLoadingProductDetails = false;
        });
        return;
      }

      final app_product.Product productDetails = loadedProductDetails;

      if (productDetails.isVariable) {
        _availableVariations = await getIt<ProductRepository>().getAllVariations(productDetails.id);
      }

      if(!mounted) return;

      _productSearchInputController.removeListener(_onProductSearchChanged);
      _productSearchInputController.text = parentProductForUi?.name ?? productDetails.name;
      _productSearchInputController.addListener(_onProductSearchChanged);

      setState(() {
        _currentProductError = null;
        _currentFoundProduct = parentProductForUi ?? productDetails;
        _currentResolvedVariant = productDetails.isVariation
            ? productDetails
            : (productDetails.isSimple ? productDetails : null);
        _currentSelectedAttributes.clear();

        final app_product.Product? currentContextProduct = _currentFoundProduct;

        if (productDetails.isVariation && currentContextProduct?.fullAttributesWithOptions?.isNotEmpty == true) {
          productDetails.attributes?.forEach((attr) {
            final slug = attr['slug']?.toString();
            final option = attr['option']?.toString();
            if (slug != null && option != null &&
                currentContextProduct!.fullAttributesWithOptions!.any((optAttr) => optAttr['slug'] == slug) ) {
              _currentSelectedAttributes[slug] = option;
            }
          });
        } else if (productDetails.isVariable && currentContextProduct?.fullAttributesWithOptions?.isEmpty == true){
          _currentProductError = "Este producto variable no tiene opciones de atributos configurables.";
        }

        if (_isStockTakeMode) {
          _newTotalStock = (itemToEdit.stockBefore ?? 0) + itemToEdit.quantityChanged;
        } else {
          _currentQuantity = itemToEdit.quantityChanged.abs();
          _isCurrentItemEntry = itemToEdit.quantityChanged > 0;
        }
        _isLoadingProductDetails = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentProductError = "Error al recargar '${itemToEdit.productName}': ${e.toString()}";
        _editingBatchItemIndex = null;
        _isLoadingProductDetails = false;
      });
    }
  }


  void _addItemToBatch() {
    final productToAdd = _currentResolvedVariant ?? _currentFoundProduct;
    if (productToAdd == null) { if(mounted) setState(() => _currentProductError = "Seleccione un producto válido para añadir."); return; }

    if (productToAdd.isVariable && _currentResolvedVariant == null) {
      if(mounted) setState(() => _currentProductError = "Por favor, seleccione todas las opciones de la variante para continuar.");
      return;
    }

    int quantityChangedValue;
    int stockBeforeValue = productToAdd.manageStock ? (productToAdd.stockQuantity ?? 0) : 0;

    if (_isStockTakeMode) {
      if (_newTotalStock < 0) { if(mounted) setState(() => _currentProductError = "La nueva cantidad total no puede ser negativa."); return; }
      quantityChangedValue = _newTotalStock - stockBeforeValue;

      if (quantityChangedValue == 0) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No hay cambios en el stock para este producto. No se añadió al lote."), duration: Duration(seconds: 3), backgroundColor: Colors.blueGrey)
          );
          if (_editingBatchItemIndex == null) {
            _clearCurrentProductSelection(resetSearchFieldAndResults: true, keepParentProduct: productToAdd.isVariation);
          }
        }
        return;
      }
    } else {
      if (_currentQuantity <= 0) { if(mounted) setState(() => _currentProductError = "La cantidad a ajustar debe ser mayor a cero."); return; }
      if (!productToAdd.manageStock && !_isCurrentItemEntry) {
        if(mounted) setState(() => _currentProductError = "No se puede dar salida a un producto que no gestiona stock.");
        return;
      }
      if (!_isCurrentItemEntry && _currentQuantity > stockBeforeValue ) {
        if(mounted) setState(() => _currentProductError = "La cantidad de salida (${_currentQuantity}) excede el stock actual ($stockBeforeValue).");
        return;
      }
      quantityChangedValue = _isCurrentItemEntry ? _currentQuantity : -_currentQuantity;
    }

    final inventoryLine = InventoryMovementLine(
      productId: productToAdd.isVariation ? (productToAdd.parentId?.toString() ?? _currentFoundProduct!.id) : productToAdd.id,
      variationId: productToAdd.isVariation ? productToAdd.id : null,
      productName: productToAdd.name, sku: productToAdd.sku,
      quantityChanged: quantityChangedValue,
      stockBefore: stockBeforeValue,
      stockAfter: stockBeforeValue + quantityChangedValue,
    );

    setState(() {
      String message;
      Color snackbarColor;

      if (_editingBatchItemIndex != null) {
        _massAdjustmentBatch[_editingBatchItemIndex!] = inventoryLine;
        message = "'${productToAdd.name}' actualizado en el lote.";
        snackbarColor = Colors.blue.shade700;
      } else {
        _massAdjustmentBatch.add(inventoryLine);
        message = "'${productToAdd.name}' ($quantityChangedValue) añadido al lote.";
        snackbarColor = Colors.green.shade700;
      }

      _clearCurrentProductSelection(resetSearchFieldAndResults: !productToAdd.isVariation, keepParentProduct: productToAdd.isVariation);
      _currentProductError = null;
      _triggerCacheSave();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: snackbarColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ));
    });
  }

  void _duplicateBatchItem(int index) {
    if (index < 0 || index >= _massAdjustmentBatch.length) return;
    final itemToDuplicate = _massAdjustmentBatch[index];
    setState(() {
      _massAdjustmentBatch.insert(index + 1, itemToDuplicate.copyWith());
      _triggerCacheSave();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("'${itemToDuplicate.productName}' duplicado en el lote."), backgroundColor: Colors.blueGrey),
    );
  }

  Future<void> _showFinalizeConfirmationDialog() async {
    if (_massAdjustmentBatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("El lote de ajuste está vacío. Añada productos primero."), backgroundColor: Colors.orange));
      return;
    }
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Por favor, complete los detalles del movimiento."), backgroundColor: Colors.orange));
      return;
    }

    _clearCurrentProductSelection(resetSearchFieldAndResults: true);
    FocusScope.of(context).unfocus();

    bool sendToPrintQueue = _sendPositiveAdjustmentsToLabelQueue;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Confirmar Ajuste de Inventario'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Se registrará un movimiento de tipo "${_overallMovementType.displayName}" para ${_massAdjustmentBatch.length} producto(s).'),
                  const SizedBox(height: 16),
                  Text('Descripción: ${_overallMovementDescriptionController.text.trim().isNotEmpty ? _overallMovementDescriptionController.text.trim() : "(Sin descripción)"}'),
                  if (_shouldShowPrintOption())
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CheckboxListTile(
                        title: const Text("Enviar a cola de impresión"),
                        subtitle: const Text("Añade productos con aumento de stock a la cola para imprimir etiquetas."),
                        value: sendToPrintQueue,
                        onChanged: (value) {
                          setDialogState(() {
                            sendToPrintQueue = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('CONFIRMAR'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _sendPositiveAdjustmentsToLabelQueue = sendToPrintQueue;
      });
      _finalizeAndSubmitBatch();
    }
  }

  Future<void> _finalizeAndSubmitBatch() async {
    if (!mounted) return;
    setState(() => _isSavingBatch = true);

    showDialog(context: context, barrierDismissible: false, builder: (BuildContext dialogContext) => const AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16.0))), content: Row(children: [CircularProgressIndicator(), SizedBox(width: 24), Text("Guardando ajuste...")])));

    final inventoryProvider = context.read<InventoryProvider>();
    final descriptionText = _overallMovementDescriptionController.text.trim().isEmpty
        ? _overallMovementType.displayName
        : _overallMovementDescriptionController.text.trim();

    bool success = await inventoryProvider.performMassInventoryAdjustment(
      type: _overallMovementType, description: descriptionText, itemsToAdjust: List.from(_massAdjustmentBatch),
    );

    if (mounted) {
      await inventoryProvider.clearCachedAdjustment();
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    if (!mounted) return;

    setState(() => _isSavingBatch = false);

    if (success) {
      if (_sendPositiveAdjustmentsToLabelQueue && _shouldShowPrintOption()) {
        await _prepareAndNavigateToLabels();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Ajuste de inventario guardado exitosamente.'), backgroundColor: Colors.green.shade700));
        Navigator.pop(context, true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(inventoryProvider.errorMessage ?? 'Error al guardar el ajuste.'), backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 4),));
    }
  }

  Future<void> _prepareAndNavigateToLabels() async {
    if (!mounted) return;
    final labelProvider = context.read<LabelProvider>();
    final productRepo = getIt<ProductRepository>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 24), Text("Preparando etiquetas...")]),
      ),
    );

    try {
      final itemsForLabels = _massAdjustmentBatch.where((item) => item.quantityChanged > 0);
      for (final item in itemsForLabels) {
        app_product.Product? productDetails;
        app_product.Product? parentDetails;
        if (item.variationId != null && item.variationId!.isNotEmpty) {
          productDetails = await productRepo.getVariationById(item.productId, item.variationId!, forceApi: true);
          if (productDetails?.parentId != null) {
            parentDetails = await productRepo.getProductById(productDetails!.parentId.toString(), forceApi: true);
          }
        } else {
          productDetails = await productRepo.getProductById(item.productId, forceApi: true);
        }

        if (productDetails != null) {
          final labelItem = LabelPrintItem(
            id: const Uuid().v4(),
            productId: item.productId,
            resolvedVariantId: item.variationId,
            quantity: item.quantityChanged,
            selectedVariants: productDetails.attributes?.fold<Map<String, String>>({}, (prev, attr) {
              prev[attr['name'] ?? ''] = attr['option'] ?? '';
              return prev;
            }) ?? {},
            barcode: productDetails.barcode ?? productDetails.sku,
            product: parentDetails ?? productDetails,
            resolvedVariant: item.variationId != null ? productDetails : null,
          );
          labelProvider.addOrUpdateItem(labelItem);
        }
      }
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        Navigator.pop(context, true);
        Navigator.pushNamed(context, Routes.labelPrinting);
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error preparando etiquetas: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productForCurrentDisplay = _currentResolvedVariant ?? _currentFoundProduct;

    bool canAddToBatch = productForCurrentDisplay != null && !_isLoadingProductDetails &&
        (!(productForCurrentDisplay.isVariable) || _currentResolvedVariant != null);

    if (canAddToBatch && productForCurrentDisplay != null) {
      if (_isStockTakeMode) {
        canAddToBatch = true;
      } else {
        canAddToBatch = _currentQuantity > 0;
        if (!_isCurrentItemEntry && productForCurrentDisplay.manageStock) {
          canAddToBatch = _currentQuantity <= (productForCurrentDisplay.stockQuantity ?? 0);
        }
      }
    }

    return WillPopScope(
      onWillPop: () async {
        if (_massAdjustmentBatch.isNotEmpty) {
          _triggerCacheSave();
        } else {
          await context.read<InventoryProvider>().clearCachedAdjustment();
        }
        return true;
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          appBar: AppHeader(
            title: _screenTitle,
            showBackButton: true,
            onBackPressed: () => Navigator.maybePop(context),
            showCartButton: false,
            showSettingsButton: false,
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0 + MediaQuery.of(context).padding.bottom + 90),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMovementDetailsSection(theme),
                        const SizedBox(height: 16),
                        _buildProductSearchSection(theme),
                        const SizedBox(height: 8),
                        _buildSearchResultsList(theme),
                        if (_currentProductError != null && !_isLoadingProductDetails && _searchResultsNotifier.value.isEmpty && productForCurrentDisplay == null)
                          Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Text(_currentProductError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13.5, fontStyle: FontStyle.italic), textAlign: TextAlign.center)),
                        _buildSelectedProductSection(theme, productForCurrentDisplay, canAddToBatch),
                        _buildBatchListSection(theme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomSheet: _buildBottomActionButtonsBar(theme),
        ),
      ),
    );
  }

  Widget _buildMovementDetailsSection(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('movement-details-tile'),
        initiallyExpanded: false,
        title: Text(
          "1. Detalles del Movimiento",
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                DropdownButtonFormField<InventoryMovementType>(
                  decoration: InputDecoration(
                      labelText: 'Razón Principal del Movimiento',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16)
                  ),
                  value: _overallMovementType,
                  items: InventoryMovementType.values
                      .where((t) => ![InventoryMovementType.sale, InventoryMovementType.refund, InventoryMovementType.unknown].contains(t))
                      .map((type) => DropdownMenuItem(value: type, child: Text(type.displayName, style: const TextStyle(fontSize: 15))))
                      .toList(),
                  onChanged: _isSavingBatch ? null : (val) {
                    if (val != null) {
                      _updateOperationModeFromType(val);
                      _triggerCacheSave();
                    }
                  },
                  validator: (value) => value == null ? 'Seleccione una razón' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _overallMovementDescriptionController,
                    decoration: InputDecoration(
                        labelText: 'Descripción Adicional (Opcional)',
                        hintText: 'Ej: Conteo Bodega A, Factura #XYZ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16)
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    minLines: 1,
                    enabled: !_isSavingBatch
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSearchSection(ThemeData theme) {
    if (widget.arguments?.initialProduct != null) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("2. Añadir Producto al Lote", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
                controller: _productSearchInputController,
                focusNode: _productSearchInputFocusNode,
                decoration: InputDecoration(
                    labelText: "Buscar por SKU, Código o Nombre",
                    hintText: "Escriba para buscar...",
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 24),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: _productSearchInputController.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 22), onPressed: () => _clearCurrentProductSelection(resetSearchFieldAndResults: true), splashRadius: 22)
                        : null
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) { /* No hacer nada para evitar que el teclado se cierre */ },
                enabled: !_isSavingBatch && !_isLoadingProductDetails
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                label: const Text("ESCANEAR CÓDIGO", style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: theme.primaryColor, width: 1.5),
                    foregroundColor: theme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
                onPressed: _isSavingBatch || _isLoadingProductDetails ? null : _scanBarcodeAndSearch
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList(ThemeData theme) {
    return ListenableBuilder(
      listenable: Listenable.merge([_searchResultsNotifier, _isSearchingNotifier, _searchErrorNotifier]),
      builder: (context, child) {
        final results = _searchResultsNotifier.value;
        final isLoading = _isSearchingNotifier.value;
        final error = _searchErrorNotifier.value;

        if (isLoading) {
          return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24.0), child: CircularProgressIndicator(strokeWidth: 2.5)));
        }
        if (error != null && results.isEmpty) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Text(error, style: TextStyle(color: Colors.red.shade700, fontSize: 13.5, fontStyle: FontStyle.italic), textAlign: TextAlign.center));
        }
        if (results.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 8.0, left: 4),
              child: Text("Resultados (${results.length}):", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
            ),
            ListView.builder(
                controller: _searchResultsScrollController,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: results.length,
                itemBuilder: (ctx, index) {
                  final product = results[index];
                  return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4.5, horizontal: 0),
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.grey.shade200,
                            child: product.displayImageUrl != null && product.displayImageUrl!.isNotEmpty
                                ? ClipOval(child: CachedNetworkImage(imageUrl: product.displayImageUrl!, fit: BoxFit.cover, width: 44, height: 44, placeholder: (c,u) => const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey)))
                                : const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey),
                          ),
                          title: Text(product.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          subtitle: Text("SKU: ${product.sku.isNotEmpty ? product.sku : 'N/A'}  •  Stock: ${product.stockQuantity ?? (product.manageStock ? 0 : 'No gestionado')}", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                          dense: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          onTap: () {
                            _productSearchInputFocusNode.unfocus();
                            _processFoundProductDetails(product, fromScanOrDirectCode: false);
                          }
                      )
                  );
                }
            ),
            if (_currentFoundProduct == null && results.isNotEmpty) const Divider(height: 16, thickness: 1, indent: 8, endIndent: 8),
          ],
        );
      },
    );
  }

  Widget _buildSelectedProductSection(ThemeData theme, app_product.Product? productForDisplay, bool canAddToBatch) {
    if (productForDisplay == null && !_isLoadingProductDetails) return const SizedBox.shrink();
    if (_isLoadingProductDetails && productForDisplay == null) return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24.0), child: CircularProgressIndicator(strokeWidth: 2.5)));
    if (productForDisplay == null) return const SizedBox.shrink();

    return Column(
      children: [
        if (_searchResultsNotifier.value.isNotEmpty && _currentFoundProduct != null)
          const Divider(height: 28, thickness: 1, indent: 8, endIndent: 8),
        Card(
            elevation: 2.5,
            margin: const EdgeInsets.only(top: 8, bottom:16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Container(width: 80, height: 80, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.grey.shade200),
                            child: (productForDisplay.displayImageUrl != null && productForDisplay.displayImageUrl!.isNotEmpty)
                                ? CachedNetworkImage(imageUrl: productForDisplay.displayImageUrl!, fit: BoxFit.cover, placeholder: (c,u) => const Icon(Icons.image_search_rounded, color: Colors.grey, size: 35), errorWidget: (c,u,e) => const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 35))
                                : const Icon(Icons.inventory_2_rounded, color: Colors.grey, size: 40)
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(productForDisplay.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 17)),
                          const SizedBox(height: 4),
                          Text("SKU: ${productForDisplay.sku.isNotEmpty ? productForDisplay.sku : 'N/A'}", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          Text(
                            "Stock Actual: ${productForDisplay.stockQuantity ?? (productForDisplay.manageStock ? 0 : 'No Gestionado')}",
                            style: TextStyle(fontSize: 13, color: ((productForDisplay.stockQuantity ?? 0) > 0 || !productForDisplay.manageStock) ? Colors.green.shade700 : Colors.orange.shade800, fontWeight: FontWeight.w500),
                          ),
                        ])),
                      ]),
                      if (_currentFoundProduct != null && _currentFoundProduct!.isVariable) ...[
                        const SizedBox(height: 18),
                        Text("Seleccionar Variantes:", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.primaryColor)),
                        const SizedBox(height: 10),
                        if (_currentFoundProduct!.fullAttributesWithOptions != null && _currentFoundProduct!.fullAttributesWithOptions!.isNotEmpty)
                          ..._buildVariantSelectors(theme)
                        else if (_currentProductError != null && _currentProductError!.contains("atributos configurables"))
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                            child: Text(
                              _currentProductError!,
                              style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5, fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                            child: Text(
                              "Cargando opciones de variante o no disponibles...",
                              style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5, fontStyle: FontStyle.italic),
                            ),
                          ),
                        if (_currentProductError != null && !_currentProductError!.contains("atributos configurables"))
                          Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_currentProductError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)))
                      ],
                      const SizedBox(height: 20),
                      Text(_isStockTakeMode ? "Nueva Cantidad Total:" : "Cantidad a Ajustar:", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            flex: _isStockTakeMode ? 1 : 3,
                            child: QuantitySelector(
                                key: ValueKey('${productForDisplay.id}_qty_${_isStockTakeMode ? _newTotalStock : _currentQuantity}_editing_${_editingBatchItemIndex != null}'),
                                value: _isStockTakeMode ? _newTotalStock : _currentQuantity,
                                minValue: _isStockTakeMode ? 0 : 1,
                                maxValue: !_isStockTakeMode && !_isCurrentItemEntry && productForDisplay.manageStock
                                    ? (productForDisplay.stockQuantity ?? 0)
                                    : 9999,
                                onChanged: (val) { if (mounted) setState(() { if (_isStockTakeMode) _newTotalStock = val; else _currentQuantity = val; });}
                            )
                        ),
                        if (!_isStockTakeMode)
                          ...[
                            const SizedBox(width: 16),
                            Expanded(
                                flex: 4,
                                child: SegmentedButton<bool>(
                                    style: SegmentedButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.standard, textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                                    segments: const [ButtonSegment(value: true, label: Text("ENTRADA"), icon: Icon(Icons.add_circle_outline_rounded, size: 20)), ButtonSegment(value: false, label: Text("SALIDA"), icon: Icon(Icons.remove_circle_outline_rounded, size: 20))],
                                    selected: {_isCurrentItemEntry},
                                    onSelectionChanged: (newSelection) { setState(() => _isCurrentItemEntry = newSelection.first); }
                                )
                            )
                          ]
                      ]),
                      if (!_isStockTakeMode && !_isCurrentItemEntry && productForDisplay.manageStock && _currentQuantity > (productForDisplay.stockQuantity ?? 0) )
                        Padding(padding: const EdgeInsets.only(top: 8.0), child: Text("La cantidad de salida excede el stock actual.", style: TextStyle(color: Colors.red.shade700, fontSize: 12.5))),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                          icon: Icon(_editingBatchItemIndex != null ? Icons.edit_note_rounded : Icons.playlist_add_rounded, size: 22),
                          label: Text(_editingBatchItemIndex != null ? "ACTUALIZAR EN LOTE" : "AÑADIR AL LOTE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: canAddToBatch && !(_isLoadingProductDetails || _isSavingBatch) ? (_editingBatchItemIndex != null ? Colors.blue.shade700 : theme.colorScheme.secondary) : Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: canAddToBatch && !(_isLoadingProductDetails || _isSavingBatch) ? _addItemToBatch : null
                      ),
                    ]
                )
            )
        ),
      ],
    );
  }

  Widget _buildBatchListSection(ThemeData theme) {
    if (_massAdjustmentBatch.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height:16),
        Text('Lote de Ajuste Actual (${_massAdjustmentBatch.length} ítem(s)):', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 18)),
        const SizedBox(height: 10),
        ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _massAdjustmentBatch.length,
            itemBuilder: (ctx, index) {
              final item = _massAdjustmentBatch[index];
              final String stockChangeString = (item.quantityChanged > 0 ? "+" : "") + item.quantityChanged.toString();
              final Color stockChangeColor = item.quantityChanged > 0 ? Colors.green.shade700 : Colors.red.shade700;
              return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                      dense: false,
                      leading: CircleAvatar(
                          backgroundColor: stockChangeColor.withOpacity(0.12),
                          radius: 20,
                          child: Icon(item.quantityChanged > 0 ? Icons.file_upload_outlined : Icons.file_download_outlined, color: stockChangeColor, size: 20)
                      ),
                      title: Text('${item.productName} ${item.sku.isNotEmpty ? "(SKU: ${item.sku})" : ""}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text('Stock Ant: ${item.stockBefore ?? 'N/A'}  ➔  Nuevo: ${item.stockAfter ?? 'N/A'}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: stockChangeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                            child: Text(stockChangeString, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: stockChangeColor)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.copy_all_outlined, color: Colors.blueGrey, size: 20),
                            tooltip: "Duplicar ítem",
                            onPressed: _isSavingBatch ? null : () => _duplicateBatchItem(index),
                            splashRadius: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: Colors.blue.shade700, size: 22),
                            tooltip: "Editar ítem",
                            onPressed: _isSavingBatch ? null : () {
                              _loadBatchItemForEditing(item, index);
                            },
                            splashRadius: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                              icon: Icon(Icons.delete_forever_rounded, color: Colors.red.shade400, size: 24),
                              tooltip: "Eliminar del lote",
                              onPressed: _isSavingBatch ? null : () {
                                setState(() {
                                  _massAdjustmentBatch.removeAt(index);
                                  if (_editingBatchItemIndex == index) {
                                    _clearCurrentProductSelection(resetSearchFieldAndResults: true);
                                  } else if (_editingBatchItemIndex != null && _editingBatchItemIndex! > index) {
                                    _editingBatchItemIndex = _editingBatchItemIndex! - 1;
                                  }
                                  _triggerCacheSave();
                                });
                              },
                              splashRadius: 22, visualDensity: VisualDensity.compact
                          ),
                        ],
                      ),
                      contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8)
                  )
              );
            }
        ),
      ],
    );
  }

  Widget _buildBottomActionButtonsBar(ThemeData theme) {
    final bool canSave = _massAdjustmentBatch.isNotEmpty && !_isSavingBatch;
    return Container(
      padding: EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0 + MediaQuery.of(context).padding.bottom * 0.6),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0,-2)),],
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.8))
      ),
      child: Row(
          children: [
            Expanded(
                child: OutlinedButton(
                    child: const Text('CANCELAR'),
                    onPressed: _isSavingBatch ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: Colors.grey.shade400)
                    )
                )
            ),
            const SizedBox(width: 12),
            Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                    icon: _isSavingBatch
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Icon(Icons.save_alt_rounded, size: 20),
                    label: const Text('GUARDAR AJUSTE'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: canSave ? theme.primaryColor : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: canSave ? 2 : 0
                    ),
                    onPressed: canSave ? _showFinalizeConfirmationDialog : null
                )
            )
          ]
      ),
    );
  }

  List<Widget> _buildVariantSelectors(ThemeData theme) {
    if (_currentFoundProduct?.fullAttributesWithOptions == null ||
        _currentFoundProduct!.fullAttributesWithOptions!.isEmpty) {
      return [const SizedBox.shrink()];
    }

    final attributesToDisplay = _currentFoundProduct!.fullAttributesWithOptions!;

    return attributesToDisplay.map<Widget>((attrDef) {
      final String attributeUiName = attrDef['name'] as String? ?? 'Atributo';
      final String attributeSlug = attrDef['slug'] as String? ?? attributeUiName.toLowerCase().replaceAll(' ', '-');

      final List<String> options = (attrDef['options'] as List<dynamic>?)
          ?.map((o) => o.toString())
          .where((o) => o.isNotEmpty)
          .toList() ?? [];

      final String? currentSelectionForThisAttr = _currentSelectedAttributes[attributeSlug];

      if (options.isEmpty) {
        return const SizedBox.shrink();
      }

      return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
                labelText: attributeUiName,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
            ),
            value: currentSelectionForThisAttr,
            hint: const Text("Seleccionar...", style: TextStyle(fontSize: 14)),
            isExpanded: true,
            items: options.map((option) => DropdownMenuItem(
                value: option,
                child: Text(option, style: const TextStyle(fontSize: 14.5), overflow: TextOverflow.ellipsis)
            )).toList(),
            onChanged: _isLoadingProductDetails || _isSavingBatch ? null : (value) => _handleAttributeSelection(attributeSlug, value),
            validator: (value) => value == null ? 'Seleccione una opción para $attributeUiName' : null,
          )
      );
    }).toList();
  }
}
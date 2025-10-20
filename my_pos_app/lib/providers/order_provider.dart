// lib/providers/order_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../services/woocommerce_service.dart';
import '../services/sync_manager.dart';
import '../models/sync_operation.dart';
import '../models/product.dart' as app_product;
import '../models/order.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../config/constants.dart';
import '../locator.dart';

class OrderSummaryData {
  final double subtotal;
  final double wcDiscount;
  final double manualDiscount;
  final double tax;
  final double total;
  final double taxRate;

  const OrderSummaryData({
    required this.subtotal,
    required this.wcDiscount,
    required this.manualDiscount,
    required this.tax,
    required this.total,
    required this.taxRate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is OrderSummaryData &&
              runtimeType == other.runtimeType &&
              subtotal == other.subtotal &&
              wcDiscount == other.wcDiscount &&
              manualDiscount == other.manualDiscount &&
              tax == other.tax &&
              total == other.total &&
              taxRate == other.taxRate;

  @override
  int get hashCode =>
      subtotal.hashCode ^
      wcDiscount.hashCode ^
      manualDiscount.hashCode ^
      tax.hashCode ^
      total.hashCode ^
      taxRate.hashCode;
}


class OrderProvider extends ChangeNotifier {
  final OrderRepository _orderRepository = getIt<OrderRepository>();
  final ProductRepository _productRepository = getIt<ProductRepository>();
  final SyncManager _syncManager = getIt<SyncManager>();
  final SharedPreferences sharedPreferences;

  Order? _currentOrder;
  bool _isLoading = false;
  String? _errorMessage;
  double _taxRate = 0.13;
  Timer? _errorTimer;
  bool _isDisposed = false;
  Timer? _saveOrderDebounce;

  // --- ESTADO PARA PAGINACIÓN DEL HISTORIAL ---
  List<Order> _historyOrders = [];
  int _historyCurrentPage = 1;
  bool _historyIsLoading = false;
  bool _historyIsLoadingMore = false;
  bool _historyCanLoadMore = true;
  String? _historyError;
  int _historyTotalPages = 1;

  Order? get currentOrder => _currentOrder;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  double get taxRate => _taxRate;
  bool get allowIndividualDiscounts => sharedPreferences.getBool(individualDiscountsEnabledPrefKey) ?? true;
  bool get isDisposed => _isDisposed;

  List<Order> get historyOrders => _historyOrders;
  bool get historyIsLoading => _historyIsLoading;
  bool get historyIsLoadingMore => _historyIsLoadingMore;
  bool get historyCanLoadMore => _historyCanLoadMore;
  String? get historyError => _historyError;

  OrderProvider({ required this.sharedPreferences, }) {
    debugPrint("[OrderProvider] Constructor called.");
    _initOrder();
  }

  Future<void> _initOrder() async {
    debugPrint("[OrderProvider] _initOrder START");
    if (_isDisposed) return;

    if (_currentOrder == null) {
      _setLoading(true);
    }

    Future.microtask(() async {
      try {
        final String taxString = sharedPreferences.getString(defaultTaxRatePrefKey) ?? '13';
        final double rate = (double.tryParse(taxString.replaceAll(',','.')) ?? 13.0) / 100.0;
        _taxRate = rate.clamp(0.0, 1.0);
        debugPrint("[OrderProvider] Tax rate loaded: $_taxRate");

        Map<String, Order> pendingOrders = _orderRepository.getPendingOrders();
        final savedCurrentOrder = pendingOrders[hiveCurrentOrderPendingKey];

        if (savedCurrentOrder != null) {
          debugPrint("[OrderProvider] Found saved current order: ${savedCurrentOrder.id}");
          _currentOrder = savedCurrentOrder;
          await recalculateTotals();
        } else {
          debugPrint("[OrderProvider] No saved current order found. Creating new.");
          _currentOrder = _createNewOrderInternal();
        }
      } catch (e, s) {
        debugPrint("[OrderProvider] !! ERROR during _initOrder background task: $e\nStack: $s");
        _setError("Error inicializando el pedido: ${e.toString()}");
        if (_currentOrder == null) {
          _currentOrder = _createNewOrderInternal();
        }
      } finally {
        if (!_isDisposed) {
          _setLoading(false);
        }
      }
    });
  }


  Order _createNewOrderInternal() {
    return Order(
      id: null,
      number: null,
      customerId: null,
      customerName: 'Cliente General',
      items: [],
      subtotal: 0,
      tax: 0,
      discount: 0,
      total: 0,
      date: DateTime.now(),
      orderStatus: 'pending',
      isSynced: false,
    );
  }

  String _getUniqueCartItemId(String productId, int? variationId) {
    return variationId != null && variationId > 0
        ? '${productId}_$variationId'
        : productId;
  }

  void _setLoading(bool loading) {
    if (_isDisposed || _isLoading == loading) return;
    _isLoading = loading;
    if(!loading && _errorMessage == null) {
      clearError();
    } else if (loading) {
      clearError();
    }
    if (!_isDisposed) notifyListeners();
  }

  void _setError(String? message, {int durationSeconds = 7}) {
    if (_isDisposed) return;
    _errorTimer?.cancel();
    if (_errorMessage != message) {
      _errorMessage = message;
      if (!_isDisposed) notifyListeners();
    }
    if (message != null) {
      _errorTimer = Timer(Duration(seconds: durationSeconds), () {
        if (!_isDisposed && _errorMessage == message) {
          _errorMessage = null;
          try { if (!_isDisposed) notifyListeners(); } catch (_) {}
        }
      });
    }
  }

  void clearError() {
    if (_isDisposed) return;
    _errorTimer?.cancel();
    if (_errorMessage != null) {
      _errorMessage = null;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> clearOrder() async {
    if (_isDisposed) return;
    debugPrint("[OrderProvider] Clearing current order.");
    _currentOrder = _createNewOrderInternal();
    await recalculateTotals(forceSave: true);
    clearError();
  }

  Future<void> updateOrderCustomer(String? customerId, String customerName) async {
    if (_isDisposed || _currentOrder == null) return;
    final effectiveName = customerName.isNotEmpty ? customerName : 'Cliente General';

    bool customerChanged = _currentOrder!.customerId != customerId || _currentOrder!.customerName != effectiveName;

    if (customerChanged) {
      debugPrint("[OrderProvider] Updating customer to ID: $customerId, Name: $effectiveName");
      _currentOrder = _currentOrder!.copyWith(
        customerId: customerId,
        customerName: effectiveName,
      );
      if (!_isDisposed) {
        notifyListeners();
      }
      await recalculateTotals();
    }
  }

  Future<void> addProduct(
      app_product.Product productInput,
      int quantity,
      {
        List<Map<String, String>>? explicitAttributes,
      }) async {
    if (_isDisposed || quantity <= 0) {
      if (quantity <= 0) _setError("La cantidad debe ser mayor a 0.", durationSeconds: 3);
      return;
    }
    _currentOrder ??= _createNewOrderInternal();

    debugPrint("[OrderProvider.addProduct] Adding Product ID: ${productInput.id}, Name: '${productInput.name}', Type: '${productInput.type}', Qty: $quantity");

    if (productInput.manageStock) {
      int currentItemQtyInCart = 0;
      final String uniqueItemIdInCart = _getUniqueCartItemId(
          productInput.isVariation ? (productInput.parentId?.toString() ?? productInput.id) : productInput.id,
          productInput.isVariation ? int.tryParse(productInput.id) : null
      );
      final existingItemIndex = _currentOrder!.items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemIdInCart);

      if (existingItemIndex != -1) {
        currentItemQtyInCart = _currentOrder!.items[existingItemIndex].quantity;
      }

      int requestedTotalQty = currentItemQtyInCart + quantity;
      int? availableStock = productInput.stockQuantity;

      if (availableStock == null) {
        _setError("Verificando stock de '${productInput.name}'...", durationSeconds:3);
        app_product.Product? freshProductDetails;
        try {
          if (productInput.isVariation) {
            freshProductDetails = await _productRepository.getVariationById(productInput.parentId!.toString(), productInput.id, forceApi: true);
          } else {
            freshProductDetails = await _productRepository.getProductById(productInput.id, forceApi: true);
          }
        } catch (e) {
          _setError("Error al verificar stock: ${e.toString()}", durationSeconds: 4);
          return;
        }
        if (_isDisposed) return;
        availableStock = freshProductDetails?.stockQuantity;
        if (availableStock == null) {
          _setError("No se pudo verificar el stock de '${productInput.name}'.", durationSeconds: 5);
          return;
        }
      }

      if (requestedTotalQty > availableStock) {
        _setError("Stock insuficiente para '${productInput.name}'. Disponible: $availableStock. Solicitado en total: $requestedTotalQty", durationSeconds: 5);
        return;
      }
    } else if (productInput.stockStatus == 'outofstock') {
      _setError("'${productInput.name}' está agotado.", durationSeconds: 5);
      return;
    }
    clearError();

    final items = List<OrderItem>.from(_currentOrder!.items);
    final String orderItemProductId = productInput.isVariation ? (productInput.parentId?.toString() ?? productInput.id) : productInput.id;
    final int? orderItemVariationId = productInput.isVariation ? int.tryParse(productInput.id) : null;
    final String uniqueCartLookupId = _getUniqueCartItemId(orderItemProductId, orderItemVariationId);

    final index = items.indexWhere((item) =>
    _getUniqueCartItemId(item.productId, item.variationId) == uniqueCartLookupId);

    List<Map<String, String>>? attributesForOrderItem = explicitAttributes;
    if (attributesForOrderItem == null && productInput.isVariation && productInput.attributes != null) {
      attributesForOrderItem = productInput.attributes!.map((attr) {
        return <String, String>{
          'name': attr['name']?.toString() ?? '',
          'option': attr['option']?.toString() ?? '',
          'slug': attr['slug']?.toString() ?? attr['name']?.toString()?.toLowerCase().replaceAll(' ', '-') ?? '',
        };
      }).toList();
      if (attributesForOrderItem.every((attr) => (attr['name'] ?? '').isEmpty || (attr['option'] ?? '').isEmpty )) {
        attributesForOrderItem = null;
      }
    }

    if (index >= 0) {
      final existingItem = items[index];
      final newQuantity = existingItem.quantity + quantity;
      items[index] = existingItem.copyWith(
        quantity: newQuantity,
        price: productInput.displayPrice,
        subtotal: productInput.displayPrice * newQuantity,
        regularPrice: () => productInput.regularPrice ?? productInput.price,
        name: productInput.name,
        sku: productInput.sku,
        productType: productInput.type,
        attributes: attributesForOrderItem,
        manageStock: productInput.manageStock,
        stockQuantity: () => productInput.stockQuantity,
      );
    } else {
      items.add(OrderItem(
          productId: orderItemProductId,
          name: productInput.name,
          sku: productInput.sku,
          quantity: quantity,
          price: productInput.displayPrice,
          subtotal: productInput.displayPrice * quantity,
          variationId: orderItemVariationId,
          attributes: attributesForOrderItem,
          individualDiscount: null,
          regularPrice: productInput.regularPrice ?? productInput.price,
          lineItemId: null,
          productType: productInput.type,
          manageStock: productInput.manageStock,
          stockQuantity: productInput.stockQuantity
      ));
    }
    _currentOrder = _currentOrder!.copyWith(items: items);
    await recalculateTotals();
  }

  Future<void> duplicateOrderItem(String uniqueItemId) async {
    if (_isDisposed || _currentOrder == null) return;

    final itemToDuplicate = _currentOrder!.items.firstWhereOrNull((item) => _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

    if (itemToDuplicate == null) {
      _setError("No se encontró el ítem para duplicar.", durationSeconds: 4);
      return;
    }

    debugPrint("[OrderProvider] Duplicating item: ${itemToDuplicate.name}");

    _setLoading(true);
    try {
      app_product.Product? productDetails;
      if (itemToDuplicate.isVariation) {
        productDetails = await _productRepository.getVariationById(itemToDuplicate.productId, itemToDuplicate.variationId.toString(), forceApi: true);
      } else {
        productDetails = await _productRepository.getProductById(itemToDuplicate.productId, forceApi: true);
      }

      if (productDetails != null) {
        final items = List<OrderItem>.from(_currentOrder!.items);
        items.add(
            OrderItem(
              productId: productDetails.isVariation ? (productDetails.parentId?.toString() ?? productDetails.id) : productDetails.id,
              name: productDetails.name,
              sku: productDetails.sku,
              quantity: 1,
              price: productDetails.displayPrice,
              subtotal: productDetails.displayPrice * 1,
              variationId: productDetails.isVariation ? int.tryParse(productDetails.id) : null,
              attributes: itemToDuplicate.attributes,
              individualDiscount: null,
              regularPrice: productDetails.regularPrice ?? productDetails.price,
              lineItemId: null,
              productType: productDetails.type,
              manageStock: productDetails.manageStock,
              stockQuantity: productDetails.stockQuantity,
            )
        );
        _currentOrder = _currentOrder!.copyWith(items: items);
        await recalculateTotals();
      } else {
        _setError("No se pudieron obtener los detalles del producto para duplicarlo.", durationSeconds: 5);
      }
    } catch (e) {
      _setError("Error al duplicar el ítem: ${e.toString()}", durationSeconds: 5);
    } finally {
      if (!_isDisposed) _setLoading(false);
    }
  }

  Future<void> updateItemQuantity(String uniqueItemId, int quantity) async {
    if (_isDisposed || _currentOrder == null || isLoading || quantity < 0) return;
    debugPrint("[OrderProvider.updateItemQuantity] Item: $uniqueItemId, New Qty: $quantity");

    final items = List<OrderItem>.from(_currentOrder!.items);
    final index = items.indexWhere((item) =>
    _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

    if (index >= 0) {
      final item = items[index];
      if (quantity == 0) {
        items.removeAt(index);
        debugPrint("... Item $uniqueItemId removed (qty 0).");
      } else {
        if (quantity > item.quantity && item.manageStock) {
          app_product.Product? productDetails;
          try {
            _setError("Verificando stock para '${item.name}'...", durationSeconds: 3);
            if (item.variationId != null && item.variationId! > 0) {
              productDetails = await _productRepository.getVariationById(item.productId, item.variationId!.toString(), forceApi: true);
            } else {
              productDetails = await _productRepository.getProductById(item.productId, forceApi: true);
            }
          } catch (e) {
            _setError("Error al verificar stock: ${e.toString()}", durationSeconds: 4);
            return;
          }
          if (_isDisposed) return;

          final availableStock = productDetails?.stockQuantity;
          if (availableStock == null) {
            _setError("No se pudo verificar el stock de '${item.name}'.", durationSeconds: 5);
            return;
          }
          if (quantity > availableStock) {
            _setError("Stock insuficiente (${availableStock}) para '${item.name}'.", durationSeconds: 5);
            return;
          }
        }
        clearError();
        items[index] = item.copyWith(quantity: quantity, subtotal: item.price * quantity);
        debugPrint("... Item $uniqueItemId quantity updated to $quantity. New subtotal: ${items[index].subtotal}");
      }
      _currentOrder = _currentOrder!.copyWith(items: items);
      await recalculateTotals();
    } else {
      debugPrint("[OrderProvider.updateItemQuantity] Item $uniqueItemId not found in current order.");
    }
  }

  Future<void> removeItem(String uniqueItemId) async {
    if (_isDisposed) return;
    debugPrint("[OrderProvider.removeItem] Removing item $uniqueItemId");
    await updateItemQuantity(uniqueItemId, 0);
  }

  Future<void> setTaxRate(double rate) async {
    if (_isDisposed) return;
    final clampedRate = rate.clamp(0.0, 1.0);
    if ((clampedRate - _taxRate).abs() > 0.001) {
      _taxRate = clampedRate;
      debugPrint("[OrderProvider] Tax rate set to: $_taxRate");
      try {
        await sharedPreferences.setString(defaultTaxRatePrefKey, (clampedRate * 100).toStringAsFixed(1));
      } catch (e) {
        _setError("Error al guardar la tasa de impuestos.", durationSeconds: 4);
      }
      if (_currentOrder != null) {
        await recalculateTotals();
      } else if (_currentOrder == null || _currentOrder!.items.isEmpty) {
        if (!_isDisposed) notifyListeners();
      }
    }
  }

  Future<void> applyItemDiscount({
    required String uniqueItemId,
    required double value,
    required bool isPercentage,
  }) async {
    if (_isDisposed || _currentOrder == null || isLoading || value < 0) return;
    if (!allowIndividualDiscounts && value > 0) {
      _setError("Los descuentos individuales están desactivados.", durationSeconds: 4);
      return;
    }
    debugPrint("[OrderProvider.applyItemDiscount] Item: $uniqueItemId, Value: $value, IsPercentage: $isPercentage");

    final items = List<OrderItem>.from(_currentOrder!.items);
    final index = items.indexWhere((item) =>
    _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

    if (index >= 0) {
      final item = items[index];
      double calculatedDiscountAmount = 0;
      final currentLineSubtotalBeforeManualDiscount = item.price * item.quantity;

      if (currentLineSubtotalBeforeManualDiscount <= 0 && value > 0) {
        _setError("No se puede aplicar descuento a un ítem con subtotal cero o negativo.", durationSeconds: 4);
        return;
      }

      if (isPercentage) {
        calculatedDiscountAmount = currentLineSubtotalBeforeManualDiscount * (value.clamp(0.0, 100.0) / 100.0);
      } else {
        calculatedDiscountAmount = value.clamp(0.0, currentLineSubtotalBeforeManualDiscount);
      }

      if ((item.individualDiscount ?? 0.0 - calculatedDiscountAmount).abs() > 0.001 || (item.individualDiscount == null && calculatedDiscountAmount > 0.001)) {
        items[index] = item.copyWith(
            individualDiscount: () => calculatedDiscountAmount > 0.001 ? calculatedDiscountAmount : null
        );
        _currentOrder = _currentOrder!.copyWith(items: items);
        await recalculateTotals();
        clearError();
        debugPrint("... Discount applied to $uniqueItemId. Amount: $calculatedDiscountAmount");
      } else {
        clearError();
        debugPrint("... No significant change in discount for $uniqueItemId.");
      }
    } else {
      debugPrint("[OrderProvider.applyItemDiscount] Item $uniqueItemId not found.");
    }
  }

  Future<void> recalculateTotals({bool forceSave = false}) async {
    if (_isDisposed || _currentOrder == null) return;
    debugPrint("[OrderProvider] Recalculating totals for order...");

    final Order oldOrderStateSnapshot = _currentOrder!.copyWith();

    double subtotalBase = 0;
    double subtotalAfterWcDiscounts = 0;
    double totalManualDiscountApplied = 0;

    for (OrderItem item in _currentOrder!.items) {
      subtotalBase += (item.regularPrice ?? item.price) * item.quantity;
      subtotalAfterWcDiscounts += item.price * item.quantity;
      totalManualDiscountApplied += item.individualDiscount ?? 0.0;
    }
    double wcItemDiscountsTotal = (subtotalBase - subtotalAfterWcDiscounts).clamp(0.0, double.infinity);

    final subtotalForTaxCalculation = (subtotalAfterWcDiscounts - totalManualDiscountApplied).clamp(0.0, double.infinity);
    final tax = subtotalForTaxCalculation * _taxRate;
    final total = (subtotalForTaxCalculation + tax).clamp(0.0, double.infinity);

    _currentOrder = _currentOrder!.copyWith(
        subtotal: subtotalBase,
        discount: wcItemDiscountsTotal,
        tax: tax,
        total: total
    );

    bool changed = (oldOrderStateSnapshot.subtotal - _currentOrder!.subtotal).abs() > 0.001 ||
        (oldOrderStateSnapshot.tax - _currentOrder!.tax).abs() > 0.001 ||
        (oldOrderStateSnapshot.discount - _currentOrder!.discount).abs() > 0.001 ||
        (oldOrderStateSnapshot.total - _currentOrder!.total).abs() > 0.001 ||
        oldOrderStateSnapshot.customerName != _currentOrder!.customerName ||
        oldOrderStateSnapshot.customerId != _currentOrder!.customerId ||
        !listEquals(oldOrderStateSnapshot.items, _currentOrder!.items);

    if (changed || forceSave) {
      debugPrint("... Totals or items or customer info changed. SubtotalBase: $subtotalBase, WCDiscount: $wcItemDiscountsTotal, ManualDiscount: $totalManualDiscountApplied, Tax: $tax, Total: $total, Customer: ${_currentOrder!.customerName}. Saving with debounce.");

      _saveOrderDebounce?.cancel();

      _saveOrderDebounce = Timer(const Duration(milliseconds: 500), () async {
        if (_isDisposed) return;
        final String keyToSave;
        final Order orderToSave;

        if (_currentOrder!.id == null || _currentOrder!.id == hiveCurrentOrderPendingKey) {
          keyToSave = hiveCurrentOrderPendingKey;
          orderToSave = _currentOrder!.copyWith(id: hiveCurrentOrderPendingKey, isSynced: false);
        } else {
          keyToSave = _currentOrder!.id!;
          orderToSave = _currentOrder!.copyWith(isSynced: keyToSave.startsWith('local_') ? false : false);
        }

        try {
          if (orderToSave.items.isNotEmpty || orderToSave.customerName != 'Cliente General' || orderToSave.id != hiveCurrentOrderPendingKey) {
            await _orderRepository.savePendingOrder(orderToSave, keyToSave);
            debugPrint("... Current order state saved to Hive with key $keyToSave (debounced).");
          } else if (keyToSave == hiveCurrentOrderPendingKey && orderToSave.items.isEmpty && orderToSave.customerName == 'Cliente General') {
            await _orderRepository.removePendingOrder(hiveCurrentOrderPendingKey);
            debugPrint("... Empty current order draft removed from Hive (debounced).");
          }
        } catch (e) {
          debugPrint("... !! CRITICAL ERROR saving/removing current order state to Hive (debounced): $e");
          _setError("Error al guardar el estado del pedido localmente.", durationSeconds: 5);
        }
      });

      if(!_isDisposed) notifyListeners();
    } else {
      debugPrint("... Totals, items, and customer info did not change significantly. No notification needed from recalculateTotals.");
    }
  }

  Future<String?> saveOrder({String? finalStatus}) async {
    if (_isDisposed || _currentOrder == null || _currentOrder!.items.isEmpty || _isLoading) {
      if(_currentOrder != null && _currentOrder!.items.isEmpty) _setError("No hay productos en el pedido.");
      return null;
    }
    _saveOrderDebounce?.cancel();

    if (finalStatus != null) {
      _currentOrder = _currentOrder!.copyWith(orderStatus: finalStatus);
    }
    await recalculateTotals(forceSave: true);

    final orderToProcess = _currentOrder!;
    final localId = 'local_${const Uuid().v4()}';

    final orderForQueue = orderToProcess.copyWith(
        id: localId,
        isSynced: false,
        date: DateTime.now()
    );
    await _orderRepository.savePendingOrder(orderForQueue, localId);

    _syncManager.addOperation(
        SyncOperationType.createOrder,
        {
          'order': orderForQueue.toJson(),
          'localId': localId,
        }
    );

    await clearOrder();
    _setError("Pedido encolado para sincronización.", durationSeconds: 5);
    return localId;
  }

  Future<bool> updateOrderStatus(String orderIdToUpdate, String newStatus) async {
    if (_isDisposed || _isLoading) return false;

    if (orderIdToUpdate.startsWith('local_') || orderIdToUpdate == hiveCurrentOrderPendingKey) {
      debugPrint("[OrderProvider] Updating status for local order ID: $orderIdToUpdate to '$newStatus'");
      Order? orderToModify;
      String keyToSave = orderIdToUpdate;

      if (_currentOrder?.id == orderIdToUpdate) {
        orderToModify = _currentOrder;
      } else {
        final pendingOrders = _orderRepository.getPendingOrders();
        orderToModify = pendingOrders[orderIdToUpdate];
      }

      if (orderToModify != null) {
        Order updatedOrder = orderToModify.copyWith(orderStatus: newStatus, isSynced: false);
        await _orderRepository.savePendingOrder(updatedOrder, keyToSave);
        if (_currentOrder?.id == orderIdToUpdate) {
          _currentOrder = updatedOrder;
        }
        _setError("Estado del pedido local actualizado a '$newStatus'.", durationSeconds: 4);
        if (!_isDisposed) notifyListeners();
        return true;
      } else {
        _setError("No se encontró el pedido local '$orderIdToUpdate' para actualizar estado.", durationSeconds: 5);
        return false;
      }
    }

    debugPrint("[OrderProvider] Enqueuing status update for API Order ID: $orderIdToUpdate to '$newStatus'");
    _syncManager.addOperation(
        SyncOperationType.updateOrderStatus,
        {'orderId': orderIdToUpdate, 'newStatus': newStatus}
    );
    _setError("Actualización de estado encolada para sinc.", durationSeconds: 4);

    Order? cachedOrder = await _orderRepository.getOrderById(orderIdToUpdate);
    if (cachedOrder != null) {
      await _orderRepository.savePendingOrder(cachedOrder.copyWith(orderStatus: newStatus, isSynced: false), orderIdToUpdate);
    }
    notifyListeners();
    return true;
  }

  Future<void> getOrderHistory({String? searchTerm, String? status, bool refresh = false}) async {
    if ((_historyIsLoading || _historyIsLoadingMore) && !refresh) return;

    if (refresh) {
      _historyCurrentPage = 1;
      _historyOrders = [];
      _historyCanLoadMore = true;
    }

    if (!_isDisposed) {
      if (_historyCurrentPage == 1) _historyIsLoading = true; else _historyIsLoadingMore = true;
      _historyError = null;
      notifyListeners();
    }

    try {
      final response = await _orderRepository.getOrderHistory(
        page: _historyCurrentPage, perPage: 20,
      );

      final List<Order> newOrders = response['orders'];
      _historyTotalPages = response['total_pages'];

      if (!_isDisposed) {
        if (refresh) {
          _historyOrders = [];
          final List<Order> pendingOrders = _orderRepository.getPendingOrders().values.where((o) => o.id != hiveCurrentOrderPendingKey).toList();
          _historyOrders.addAll(pendingOrders);
        }

        // Evitar duplicados
        for (var newOrder in newOrders) {
          if (!_historyOrders.any((o) => o.id == newOrder.id)) {
            _historyOrders.add(newOrder);
          }
        }

        _historyOrders.sort((a,b) => b.date.compareTo(a.date));

        _historyCanLoadMore = _historyCurrentPage < _historyTotalPages;
        if (_historyCanLoadMore) _historyCurrentPage++;
      }
    } catch (e) {
      if (!_isDisposed) _historyError = e.toString();
    } finally {
      if (!_isDisposed) {
        _historyIsLoading = false;
        _historyIsLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadOrderForEditing(Order orderToLoad) async {
    if (_isDisposed) return;
    debugPrint("[OrderProvider.loadOrderForEditing] Loading order ID: ${orderToLoad.id ?? 'N/A'} for editing.");
    _setLoading(true);
    _saveOrderDebounce?.cancel();
    await clearOrder();

    List<OrderItem> itemsToAdd = [];
    String errorDetails = "";
    bool errorAddingItems = false;

    for (final item in orderToLoad.items) {
      if (_isDisposed) break;
      try {
        app_product.Product? productDetails;
        if (item.variationId != null && item.variationId! > 0) {
          productDetails = await _productRepository.getVariationById(item.productId, item.variationId!.toString(), forceApi: true);
        } else {
          productDetails = await _productRepository.getProductById(item.productId, forceApi: true);
        }

        if (productDetails == null) {
          debugPrint("... Product/Variation ID ${item.variationId ?? item.productId} not found via API for item '${item.name}'. Using original item data for editing.");
          itemsToAdd.add(item.copyWith());
          errorAddingItems = true;
          errorDetails += "'${item.name}' (Detalles no actualizados desde API) ";
          continue;
        }

        final nonNullProductDetails = productDetails;

        itemsToAdd.add(
            item.copyWith(
                name: nonNullProductDetails.name,
                price: nonNullProductDetails.displayPrice,
                regularPrice: () => nonNullProductDetails.regularPrice ?? nonNullProductDetails.price,
                sku: nonNullProductDetails.sku,
                attributes: item.attributes ?? (nonNullProductDetails.isVariation ? nonNullProductDetails.attributes?.map((a) => Map<String,String>.from(a)).toList() : null),
                productType: nonNullProductDetails.type,
                manageStock: nonNullProductDetails.manageStock,
                stockQuantity: () => nonNullProductDetails.stockQuantity
            )
        );
        debugPrint("... Loaded item for editing: ${nonNullProductDetails.name} (Orig name: ${item.name})");

      } on ProductNotFoundException { errorAddingItems = true; errorDetails += "'${item.name}' (Producto no encontrado en API) "; itemsToAdd.add(item.copyWith());
      } on VariationNotFoundException { errorAddingItems = true; errorDetails += "'${item.name}' (Variante no encontrada en API) "; itemsToAdd.add(item.copyWith());
      } on NetworkException { errorAddingItems = true; errorDetails += "'${item.name}' (Error de Red al cargar detalles) "; itemsToAdd.add(item.copyWith());
      } on ApiException catch(e) { errorAddingItems = true; errorDetails += "'${item.name}' (Error API: ${e.message}) "; itemsToAdd.add(item.copyWith());
      } catch (e) { errorAddingItems = true; errorDetails += "'${item.name}' (Error Inesperado) "; itemsToAdd.add(item.copyWith());
      }
    }
    if (_isDisposed) return;

    _currentOrder = orderToLoad.copyWith(
        items: itemsToAdd,
        date: DateTime.now(),
        isSynced: false,
        id: hiveCurrentOrderPendingKey,
        number: null,
        orderStatus: 'pending'
    );
    await recalculateTotals(forceSave: true);
    _setLoading(false);

    if (errorAddingItems) {
      _setError('Pedido cargado para edición. Algunos detalles de productos no pudieron actualizarse desde el servidor: ${errorDetails.trim()}', durationSeconds: 8);
    } else {
      clearError();
    }
  }

  Future<void> duplicateOrder(Order orderToDuplicate) async {
    if (_isDisposed) return;
    debugPrint("[OrderProvider.duplicateOrder] Duplicating order ID: ${orderToDuplicate.id ?? 'N/A'}");
    _setLoading(true);
    _saveOrderDebounce?.cancel();
    await clearOrder();
    List<OrderItem> duplicatedItems = [];
    bool errorFetchingProducts = false; String errorDetails = "";

    for (final item in orderToDuplicate.items) {
      if (_isDisposed) break;
      try {
        app_product.Product? productDetails;
        if (item.variationId != null && item.variationId! > 0) {
          productDetails = await _productRepository.getVariationById(item.productId, item.variationId!.toString(), forceApi: true);
        } else {
          productDetails = await _productRepository.getProductById(item.productId, forceApi: true);
        }

        if (productDetails == null) {
          errorFetchingProducts = true;
          errorDetails += "'${item.name}' (Prod/Var ya no disponible) ";
          debugPrint("... Item '${item.name}' (ID: ${item.productId}/${item.variationId}) no encontrado en API. Omitiendo de duplicado.");
          continue;
        }

        duplicatedItems.add(OrderItem(
            productId: productDetails.isVariation ? (productDetails.parentId?.toString() ?? productDetails.id) : productDetails.id,
            name: productDetails.name,
            sku: productDetails.sku,
            quantity: item.quantity,
            price: productDetails.displayPrice,
            subtotal: productDetails.displayPrice * item.quantity,
            variationId: productDetails.isVariation ? int.tryParse(productDetails.id) : null,
            attributes: productDetails.isVariation && productDetails.attributes != null
                ? productDetails.attributes!.map((attr) => Map<String, String>.from(attr)).toList()
                : null,
            regularPrice: productDetails.regularPrice ?? productDetails.price,
            individualDiscount: null,
            lineItemId: null,
            productType: productDetails.type,
            manageStock: productDetails.manageStock,
            stockQuantity: productDetails.stockQuantity
        ));
        debugPrint("... Duplicated item: ${productDetails.name}");

      } on ProductNotFoundException { errorFetchingProducts = true; errorDetails += "'${item.name}' (No encontrado) ";
      } on VariationNotFoundException { errorFetchingProducts = true; errorDetails += "'${item.name}' (Variante no encontrada) ";
      } on NetworkException { errorFetchingProducts = true; errorDetails += "'${item.name}' (Error de Red) ";
      } on ApiException catch (e) { errorFetchingProducts = true; errorDetails += "'${item.name}' (Error API: ${e.message}) ";
      } catch (e) { errorFetchingProducts = true; errorDetails += "'${item.name}' (Error Inesperado) ";
      }
    }
    if (_isDisposed) return;

    _currentOrder = Order(
        id: hiveCurrentOrderPendingKey,
        number: null,
        customerId: orderToDuplicate.customerId,
        customerName: orderToDuplicate.customerName,
        items: duplicatedItems,
        subtotal: 0, tax: 0, discount: 0, total: 0,
        date: DateTime.now(),
        orderStatus: 'pending',
        isSynced: false
    );
    await recalculateTotals(forceSave: true);
    _setLoading(false);

    if (errorFetchingProducts) {
      _setError("Orden duplicada. Algunos productos no pudieron ser actualizados desde el servidor y fueron omitidos: ${errorDetails.trim()}", durationSeconds: 8);
    } else {
      clearError();
    }
  }

  void setCurrentOrder(Order order) {
    if (_isDisposed) return;
    debugPrint("[OrderProvider] setCurrentOrder called with Order ID: ${order.id ?? 'null'}");
    if (_currentOrder?.id != order.id || _currentOrder != order) {
      _currentOrder = order;
      if(!_isDisposed) notifyListeners();
      recalculateTotals();
    }
  }

  Future<bool> updateOrderItemWithNewVariant({
    required OrderItem originalOrderItem,
    required app_product.Product selectedVariation,
  }) async {
    if (_isDisposed || _currentOrder == null) return false;
    debugPrint("[OrderProvider.updateOrderItemWithNewVariant] Original: ${originalOrderItem.name} (ID: ${originalOrderItem.productId}/${originalOrderItem.variationId}), New Variation: ${selectedVariation.name} (ID: ${selectedVariation.id})");
    _setLoading(true);

    try {
      final String originalItemUniqueIdInCart = _getUniqueCartItemId(originalOrderItem.productId, originalOrderItem.variationId);

      final items = List<OrderItem>.from(_currentOrder!.items);
      final itemIndex = items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == originalItemUniqueIdInCart);

      if (itemIndex == -1) {
        _setError("No se encontró el ítem original en el pedido para actualizar la variante.", durationSeconds: 5);
        _setLoading(false);
        return false;
      }

      List<Map<String, String>>? newAttributes;
      if (selectedVariation.attributes != null) {
        newAttributes = selectedVariation.attributes!.map((attr) {
          return <String, String>{
            'name': attr['name']?.toString() ?? '',
            'option': attr['option']?.toString() ?? '',
            'slug': attr['slug']?.toString() ?? (attr['name']?.toString() ?? '').toLowerCase().replaceAll(' ', '-')
          };
        }).toList();
        if (newAttributes.every((attr) => (attr['name'] ?? '').isEmpty || (attr['option'] ?? '').isEmpty )) {
          newAttributes = null;
        }
      }

      final newOrderItem = OrderItem(
        productId: selectedVariation.parentId?.toString() ?? selectedVariation.id,
        name: selectedVariation.name,
        sku: selectedVariation.sku,
        quantity: originalOrderItem.quantity,
        price: selectedVariation.displayPrice,
        subtotal: selectedVariation.displayPrice * originalOrderItem.quantity,
        variationId: int.tryParse(selectedVariation.id),
        attributes: newAttributes,
        regularPrice: selectedVariation.regularPrice ?? selectedVariation.price,
        individualDiscount: null,
        lineItemId: null,
        productType: selectedVariation.type,
        manageStock: selectedVariation.manageStock,
        stockQuantity: selectedVariation.stockQuantity,
      );

      items[itemIndex] = newOrderItem;
      _currentOrder = _currentOrder!.copyWith(items: items);

      debugPrint("... OrderItem actualizado con la nueva variante: ${newOrderItem.name}");
      await recalculateTotals();
      clearError();
      _setLoading(false);
      return true;

    } catch (e) {
      debugPrint("Error actualizando variante en OrderProvider: $e");
      _setError("Error al actualizar la variante del producto: ${e.toString()}", durationSeconds: 5);
      _setLoading(false);
      return false;
    }
  }

  @override
  void dispose() {
    debugPrint("[OrderProvider] dispose() called.");
    _isDisposed = true;
    _errorTimer?.cancel();
    _saveOrderDebounce?.cancel();
    super.dispose();
  }
}
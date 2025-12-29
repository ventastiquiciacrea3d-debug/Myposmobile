// lib/providers/order_notifier.dart
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../services/sync_manager.dart';
import '../services/database_service.dart';
import '../services/woocommerce_service.dart';
import '../models/sync_operation.dart';
import '../models/product.dart' as app_product;
import '../models/order.dart';
import '../models/product_optimized.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../config/constants.dart';
import 'order_state.dart';
import 'shared_providers.dart';
import 'dart:math' show max;
import '../objectbox.g.dart' hide Order;

part 'order_notifier.g.dart';

/// Notifier para la orden actual
@riverpod
class CurrentOrder extends _$CurrentOrder {
  late OrderRepository _orderRepository;
  late ProductRepository _productRepository;
  late SyncManager _syncManager;
  late SharedPreferences _sharedPreferences;
  late DatabaseService _databaseService;
  late WooCommerceService _wooCommerceService;

  Timer? _errorTimer;
  Timer? _saveOrderDebounce;

  @override
  Future<CurrentOrderState> build() async {
    debugPrint("[CurrentOrder] build() called - Initializing");

    _orderRepository = ref.read(orderRepositoryProvider);
    _productRepository = ref.read(productRepositoryProvider);
    _syncManager = ref.read(syncManagerProvider);
    _sharedPreferences = ref.read(sharedPreferencesProvider);
    _databaseService = ref.read(databaseServiceProvider);
    _wooCommerceService = ref.read(wooCommerceServiceProvider);

    // Cleanup cuando el provider se dispone
    ref.onDispose(() {
      debugPrint("[CurrentOrder] Disposing");
      _errorTimer?.cancel();
      _saveOrderDebounce?.cancel();
    });

    // Cargar configuración inicial
    final String taxString = _sharedPreferences.getString(defaultTaxRatePrefKey) ?? '13';
    final double taxRate = ((double.tryParse(taxString.replaceAll(',', '.')) ?? 13.0) / 100.0).clamp(0.0, 1.0);
    final bool allowIndividualDiscounts = _sharedPreferences.getBool(individualDiscountsEnabledPrefKey) ?? true;

    try {
      // Intentar cargar orden guardada
      Map<String, Order> pendingOrders = _orderRepository.getPendingOrders();
      final savedCurrentOrder = pendingOrders[hiveCurrentOrderPendingKey];

      if (savedCurrentOrder != null) {
        debugPrint("[CurrentOrder] Found saved current order: ${savedCurrentOrder.id}");

        // Recalcular totales
        final recalculated = _recalculateOrder(savedCurrentOrder, taxRate);

        return CurrentOrderState(
          order: recalculated,
          isLoading: false,
          isSaving: false,
          error: null,
          taxRate: taxRate,
          allowIndividualDiscounts: allowIndividualDiscounts,
        );
      } else {
        debugPrint("[CurrentOrder] No saved current order found. Creating new.");
        final newOrder = _createNewOrder();

        return CurrentOrderState(
          order: newOrder,
          isLoading: false,
          isSaving: false,
          error: null,
          taxRate: taxRate,
          allowIndividualDiscounts: allowIndividualDiscounts,
        );
      }
    } catch (e, s) {
      debugPrint("[CurrentOrder] !! ERROR during initialization: $e\nStack: $s");

      return CurrentOrderState(
        order: _createNewOrder(),
        isLoading: false,
        isSaving: false,
        error: "Error inicializando el pedido: ${e.toString()}",
        taxRate: taxRate,
        allowIndividualDiscounts: allowIndividualDiscounts,
      );
    }
  }

  /// Crea una nueva orden vacía
  Order _createNewOrder() {
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

  /// Genera ID único para items del carrito
  String _getUniqueCartItemId(String productId, int? variationId) {
    return variationId != null && variationId > 0
        ? '${productId}_$variationId'
        : productId;
  }

  /// Recalcular totales de la orden
  Order _recalculateOrder(Order order, double taxRate) {
    double subtotalBase = 0;
    double subtotalAfterWcDiscounts = 0;
    double totalManualDiscountApplied = 0;

    for (OrderItem item in order.items) {
      subtotalBase += (item.regularPrice ?? item.price) * item.quantity;
      subtotalAfterWcDiscounts += item.price * item.quantity;
      totalManualDiscountApplied += item.individualDiscount ?? 0.0;
    }

    final double wcItemDiscountsTotal = (subtotalBase - subtotalAfterWcDiscounts).clamp(0.0, double.infinity);
    final double subtotalForTaxCalculation = (subtotalAfterWcDiscounts - totalManualDiscountApplied).clamp(0.0, double.infinity);
    final double tax = subtotalForTaxCalculation * taxRate;
    final double total = (subtotalForTaxCalculation + tax).clamp(0.0, double.infinity);

    return order.copyWith(
      subtotal: subtotalBase,
      discount: wcItemDiscountsTotal,
      tax: tax,
      total: total,
    );
  }

  /// Guardar orden en Hive con debounce
  Future<void> _saveOrderWithDebounce(Order order, {bool force = false}) async {
    _saveOrderDebounce?.cancel();

    final duration = force ? Duration.zero : const Duration(milliseconds: 500);

    _saveOrderDebounce = Timer(duration, () async {
      final String keyToSave;
      final Order orderToSave;

      if (order.id == null || order.id == hiveCurrentOrderPendingKey) {
        keyToSave = hiveCurrentOrderPendingKey;
        orderToSave = order.copyWith(id: hiveCurrentOrderPendingKey, isSynced: false);
      } else {
        keyToSave = order.id!;
        orderToSave = order.copyWith(isSynced: false);
      }

      try {
        if (orderToSave.items.isNotEmpty ||
            orderToSave.customerName != 'Cliente General' ||
            orderToSave.id != hiveCurrentOrderPendingKey) {

          await _orderRepository.savePendingOrder(orderToSave, keyToSave);
          debugPrint("[CurrentOrder] ✅ Order saved to LOCAL with key $keyToSave");

          if (orderToSave.items.isNotEmpty) {
            _sendDraftToWooCommerce(orderToSave);
          }

        } else if (keyToSave == hiveCurrentOrderPendingKey &&
            orderToSave.items.isEmpty &&
            orderToSave.customerName == 'Cliente General') {
          await _orderRepository.removePendingOrder(hiveCurrentOrderPendingKey);
          debugPrint("[CurrentOrder] Empty current order draft removed from Hive");
          _cancelDraftInWooCommerce();
        }
      } catch (e) {
        debugPrint("[CurrentOrder] !! ERROR saving order to Hive: $e");
        _setError("Error al guardar el estado del pedido localmente.", durationSeconds: 5);
      }
    });
  }

  void _setError(String message, {int durationSeconds = 7}) {
    _errorTimer?.cancel();

    state = state.whenData((currentState) {
      return currentState.copyWith(
        error: message,
        isLoading: false,
        isSaving: false,
      );
    });

    _errorTimer = Timer(Duration(seconds: durationSeconds), () {
      state.whenData((currentState) {
        if (currentState.error == message) {
          state = AsyncValue.data(currentState.copyWith(error: null));
        }
      });
    });
  }

  Future<void> clearOrder() async {
    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      final newOrder = _createNewOrder();
      final recalculated = _recalculateOrder(newOrder, currentState.taxRate);

      await _saveOrderWithDebounce(recalculated, force: true);

      return currentState.copyWith(
        order: recalculated,
        error: null,
        isLoading: false,
        isSaving: false,
      );
    });
  }

  Future<void> updateOrderCustomer(String? customerId, String customerName) async {
    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      final currentOrder = currentState.order;

      if (currentOrder == null) return currentState;

      final effectiveName = customerName.isNotEmpty ? customerName : 'Cliente General';
      final bool customerChanged = currentOrder.customerId != customerId ||
          currentOrder.customerName != effectiveName;

      if (customerChanged) {
        debugPrint("[CurrentOrder] Updating customer to ID: $customerId, Name: $effectiveName");

        final updatedOrder = currentOrder.copyWith(
          customerId: customerId,
          customerName: effectiveName,
        );

        final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
        await _saveOrderWithDebounce(recalculated);

        return currentState.copyWith(order: recalculated);
      }

      return currentState;
    });
  }

  Future<void> addProduct(
      app_product.Product productInput,
      int quantity, {
        List<Map<String, String>>? explicitAttributes,
      }) async {
    if (quantity <= 0) {
      _setError("La cantidad debe ser mayor a 0.", durationSeconds: 3);
      return;
    }

    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      Order currentOrder = currentState.order ?? _createNewOrder();

      debugPrint("[CurrentOrder.addProduct] Adding Product ID: ${productInput.id}, Name: '${productInput.name}', Type: '${productInput.type}', Qty: $quantity");

      // Verificar stock si es necesario
      if (productInput.manageStock) {
        int currentItemQtyInCart = 0;
        final String uniqueItemIdInCart = _getUniqueCartItemId(
          productInput.isVariation ? (productInput.parentId?.toString() ?? productInput.id) : productInput.id,
          productInput.isVariation ? int.tryParse(productInput.id) : null,
        );

        final existingItemIndex = currentOrder.items.indexWhere((item) =>
        _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemIdInCart);

        if (existingItemIndex != -1) {
          currentItemQtyInCart = currentOrder.items[existingItemIndex].quantity;
        }

        int requestedTotalQty = currentItemQtyInCart + quantity;
        int? availableStock = productInput.stockQuantity;

        if (availableStock == null) {
          _setError("Verificando stock de '${productInput.name}'...", durationSeconds: 3);

          app_product.Product? freshProductDetails;
          try {
            if (productInput.isVariation) {
              freshProductDetails = await _productRepository.getVariationById(
                productInput.parentId!.toString(),
                productInput.id,
                forceApi: true,
              );
            } else {
              freshProductDetails = await _productRepository.getProductById(
                productInput.id,
                forceApi: true,
              );
            }
          } catch (e) {
            throw Exception("Error al verificar stock: ${e.toString()}");
          }

          availableStock = freshProductDetails?.stockQuantity;
          if (availableStock == null) {
            throw Exception("No se pudo verificar el stock de '${productInput.name}'.");
          }
        }

        if (requestedTotalQty > availableStock) {
          throw Exception("Stock insuficiente para '${productInput.name}'. Disponible: $availableStock. Solicitado en total: $requestedTotalQty");
        }
      } else if (productInput.stockStatus == 'outofstock') {
        throw Exception("'${productInput.name}' está agotado.");
      }

      // Agregar o actualizar item
      final items = List<OrderItem>.from(currentOrder.items);
      final String orderItemProductId = productInput.isVariation
          ? (productInput.parentId?.toString() ?? productInput.id)
          : productInput.id;
      final int? orderItemVariationId = productInput.isVariation
          ? int.tryParse(productInput.id)
          : null;
      final String uniqueCartLookupId = _getUniqueCartItemId(orderItemProductId, orderItemVariationId);

      final index = items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == uniqueCartLookupId);

      // Preparar atributos
      List<Map<String, String>>? attributesForOrderItem = explicitAttributes;
      if (attributesForOrderItem == null && productInput.isVariation && productInput.attributes != null) {
        attributesForOrderItem = productInput.attributes!.map((attr) {
          return <String, String>{
            'name': attr['name']?.toString() ?? '',
            'option': attr['option']?.toString() ?? '',
            'slug': attr['slug']?.toString() ?? attr['name']?.toString().toLowerCase().replaceAll(' ', '-') ?? '',
          };
        }).toList();

        if (attributesForOrderItem.every((attr) =>
        (attr['name'] ?? '').isEmpty || (attr['option'] ?? '').isEmpty)) {
          attributesForOrderItem = null;
        }
      }

      if (index >= 0) {
        // Actualizar item existente
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
        // Agregar nuevo item
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
          stockQuantity: productInput.stockQuantity,
        ));
      }

      final updatedOrder = currentOrder.copyWith(items: items);
      final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
      await _saveOrderWithDebounce(recalculated);

      return currentState.copyWith(order: recalculated, error: null);
    });
  }

  Future<void> duplicateOrderItem(String uniqueItemId) async {
    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      final currentOrder = currentState.order;

      if (currentOrder == null) {
        throw Exception("No hay orden actual");
      }

      final itemToDuplicate = currentOrder.items.firstWhereOrNull((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

      if (itemToDuplicate == null) {
        throw Exception("No se encontró el ítem para duplicar.");
      }

      debugPrint("[CurrentOrder] Duplicating item: ${itemToDuplicate.name}");

      // Cargar detalles del producto
      app_product.Product? productDetails;
      if (itemToDuplicate.isVariation) {
        productDetails = await _productRepository.getVariationById(
          itemToDuplicate.productId,
          itemToDuplicate.variationId.toString(),
          forceApi: true,
        );
      } else {
        productDetails = await _productRepository.getProductById(
          itemToDuplicate.productId,
          forceApi: true,
        );
      }

      if (productDetails == null) {
        throw Exception("No se pudieron obtener los detalles del producto para duplicarlo.");
      }

      final items = List<OrderItem>.from(currentOrder.items);
      items.add(OrderItem(
        productId: productDetails.isVariation
            ? (productDetails.parentId?.toString() ?? productDetails.id)
            : productDetails.id,
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
      ));

      final updatedOrder = currentOrder.copyWith(items: items);
      final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
      await _saveOrderWithDebounce(recalculated);

      return currentState.copyWith(order: recalculated);
    });
  }

  Future<void> updateItemQuantity(String uniqueItemId, int quantity) async {
    if (quantity < 0) return;

    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      final currentOrder = currentState.order;

      if (currentOrder == null) return currentState;

      debugPrint("[CurrentOrder.updateItemQuantity] Item: $uniqueItemId, New Qty: $quantity");

      final items = List<OrderItem>.from(currentOrder.items);
      final index = items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

      if (index >= 0) {
        final item = items[index];

        if (quantity == 0) {
          items.removeAt(index);
          debugPrint("... Item $uniqueItemId removed (qty 0).");
        } else {
          // Verificar stock si aumenta la cantidad
          if (quantity > item.quantity && item.manageStock) {
            app_product.Product? productDetails;
            try {
              if (item.variationId != null && item.variationId! > 0) {
                productDetails = await _productRepository.getVariationById(
                  item.productId,
                  item.variationId!.toString(),
                  forceApi: true,
                );
              } else {
                productDetails = await _productRepository.getProductById(
                  item.productId,
                  forceApi: true,
                );
              }
            } catch (e) {
              throw Exception("Error al verificar stock: ${e.toString()}");
            }

            final availableStock = productDetails?.stockQuantity;
            if (availableStock == null) {
              throw Exception("No se pudo verificar el stock de '${item.name}'.");
            }
            if (quantity > availableStock) {
              // ✅ FIX: Formato estandarizado para que el diálogo pueda parsearlo
              throw Exception("Stock insuficiente para '${item.name}'. Disponible: $availableStock. Solicitado en total: $quantity");
            }
          }

          items[index] = item.copyWith(
            quantity: quantity,
            subtotal: item.price * quantity,
          );
          debugPrint("... Item $uniqueItemId quantity updated to $quantity. New subtotal: ${items[index].subtotal}");
        }

        final updatedOrder = currentOrder.copyWith(items: items);
        final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
        await _saveOrderWithDebounce(recalculated);

        return currentState.copyWith(order: recalculated, error: null);
      } else {
        debugPrint("[CurrentOrder.updateItemQuantity] Item $uniqueItemId not found in current order.");
        return currentState;
      }
    });
  }

  Future<void> removeItem(String uniqueItemId) async {
    debugPrint("[CurrentOrder.removeItem] Removing item $uniqueItemId");
    await updateItemQuantity(uniqueItemId, 0);
  }

  Future<void> setTaxRate(double rate) async {
    final clampedRate = rate.clamp(0.0, 1.0);

    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;

      if ((clampedRate - currentState.taxRate).abs() > 0.001) {
        debugPrint("[CurrentOrder] Tax rate set to: $clampedRate");

        try {
          await _sharedPreferences.setString(
            defaultTaxRatePrefKey,
            (clampedRate * 100).toStringAsFixed(1),
          );
        } catch (e) {
          throw Exception("Error al guardar la tasa de impuestos.");
        }

        if (currentState.order != null) {
          final recalculated = _recalculateOrder(currentState.order!, clampedRate);
          await _saveOrderWithDebounce(recalculated);

          return currentState.copyWith(
            taxRate: clampedRate,
            order: recalculated,
          );
        } else {
          return currentState.copyWith(taxRate: clampedRate);
        }
      }

      return currentState;
    });
  }

  Future<void> applyItemDiscount({
    required String uniqueItemId,
    required double value,
    required bool isPercentage,
  }) async {
    if (value < 0) return;

    state = await AsyncValue.guard(() async {
      final currentState = state.requireValue;
      final currentOrder = currentState.order;

      if (currentOrder == null) return currentState;

      if (!currentState.allowIndividualDiscounts && value > 0) {
        throw Exception("Los descuentos individuales están desactivados.");
      }

      debugPrint("[CurrentOrder.applyItemDiscount] Item: $uniqueItemId, Value: $value, IsPercentage: $isPercentage");

      final items = List<OrderItem>.from(currentOrder.items);
      final index = items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == uniqueItemId);

      if (index >= 0) {
        final item = items[index];
        double calculatedDiscountAmount = 0;
        final currentLineSubtotalBeforeManualDiscount = item.price * item.quantity;

        if (currentLineSubtotalBeforeManualDiscount <= 0 && value > 0) {
          throw Exception("No se puede aplicar descuento a un ítem con subtotal cero o negativo.");
        }

        if (isPercentage) {
          calculatedDiscountAmount = currentLineSubtotalBeforeManualDiscount * (value.clamp(0.0, 100.0) / 100.0);
        } else {
          calculatedDiscountAmount = value.clamp(0.0, currentLineSubtotalBeforeManualDiscount);
        }

        if ((item.individualDiscount ?? 0.0 - calculatedDiscountAmount).abs() > 0.001 ||
            (item.individualDiscount == null && calculatedDiscountAmount > 0.001)) {
          items[index] = item.copyWith(
            individualDiscount: () => calculatedDiscountAmount > 0.001 ? calculatedDiscountAmount : null,
          );

          final updatedOrder = currentOrder.copyWith(items: items);
          final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
          await _saveOrderWithDebounce(recalculated);

          debugPrint("... Discount applied to $uniqueItemId. Amount: $calculatedDiscountAmount");

          return currentState.copyWith(order: recalculated, error: null);
        } else {
          debugPrint("... No significant change in discount for $uniqueItemId.");
          return currentState;
        }
      } else {
        debugPrint("[CurrentOrder.applyItemDiscount] Item $uniqueItemId not found.");
        return currentState;
      }
    });
  }

  /// 🔴 ACTUALIZACIÓN INMEDIATA DE STOCK LOCAL
  /// Este método es CRÍTICO para que la UI refleje el cambio de stock
  /// instantáneamente, incluso si la sincronización falla o tarda.
  Future<void> _updateLocalStockImmediately(Order order) async {
    debugPrint("[CurrentOrder.updateLocalStock] 📦 Updating local stock for ${order.items.length} items");

    try {
      final box = _databaseService.store.box<ProductOptimized>();

      for (final item in order.items) {
        // Obtener ID del producto (variación o producto simple)
        final int productId;
        if (item.variationId != null && item.variationId! > 0) {
          productId = item.variationId!;
        } else {
          productId = int.tryParse(item.productId) ?? 0;
        }

        if (productId == 0) {
          debugPrint("... ⚠️ Invalid product ID for item: ${item.name}");
          continue;
        }

        // Buscar producto en ObjectBox
        final query = box.query(ProductOptimized_.id.equals(productId)).build();
        final product = query.findFirst();
        query.close();

        if (product != null) {
          final int oldStock = product.stockQuantity;

          // 🔴 CRÍTICO: Reducir stock (no puede ser negativo)
          product.stockQuantity = max(0, product.stockQuantity - item.quantity.toInt());
          product.lastUpdated = DateTime.now();

          // Guardar cambio en ObjectBox
          box.put(product);

          debugPrint("... ✅ ${product.name}: $oldStock → ${product.stockQuantity} (-${item.quantity})");
        } else {
          debugPrint("... ⚠️ Product ID $productId not found in local database for item: ${item.name}");
        }
      }

      debugPrint("[CurrentOrder.updateLocalStock] ✅ Local stock updated successfully");
    } catch (e, stackTrace) {
      debugPrint("[CurrentOrder.updateLocalStock] ❌ ERROR updating local stock: $e\n$stackTrace");
      // No rethrow - continuar con el pedido aunque falle la actualización de stock local
    }
  }

  /// ✓ FASE 3: Guardar orden (encolar para sincronización)
  Future<String?> saveOrder({String? finalStatus}) async {
    final currentState = state.requireValue;
    final currentOrder = currentState.order;

    if (currentOrder == null || currentOrder.items.isEmpty) {
      if (currentOrder != null && currentOrder.items.isEmpty) {
        _setError("No hay productos en el pedido.");
      }
      return null;
    }

    _saveOrderDebounce?.cancel();

    Order orderToProcess = currentOrder;
    if (finalStatus != null) {
      orderToProcess = orderToProcess.copyWith(orderStatus: finalStatus);
    }

    final recalculated = _recalculateOrder(orderToProcess, currentState.taxRate);
    final localId = 'local_${const Uuid().v4()}';

    final orderForQueue = recalculated.copyWith(
      id: localId,
      isSynced: false,
      date: DateTime.now(),
    );

    // 🔴 PASO 1: Actualizar stock local ANTES de encolar
    await _updateLocalStockImmediately(orderForQueue);

    await _orderRepository.savePendingOrder(orderForQueue, localId);

    // 🔴 PASO 2: Encolar sincronización (aquí es donde fallaba Hive si había conflictos)
    _syncManager.addOperation(
      SyncOperationType.createOrder,
      {
        'order': orderForQueue.toJson(),
        'localId': localId,
      },
      priority: SyncPriority.critical,
      idempotencyKey: 'createOrder_$localId',
    );

    await clearOrder();
    _setError("Pedido encolado para sincronización.", durationSeconds: 5);

    return localId;
  }

  /// Actualizar estado de orden
  Future<bool> updateOrderStatus(String orderIdToUpdate, String newStatus) async {
    try {
      if (orderIdToUpdate.startsWith('local_') || orderIdToUpdate == hiveCurrentOrderPendingKey) {
        debugPrint("[CurrentOrder] Updating status for local order ID: $orderIdToUpdate to '$newStatus'");

        Order? orderToModify;
        String keyToSave = orderIdToUpdate;

        final currentState = state.requireValue;
        if (currentState.order?.id == orderIdToUpdate) {
          orderToModify = currentState.order;
        } else {
          final pendingOrders = _orderRepository.getPendingOrders();
          orderToModify = pendingOrders[orderIdToUpdate];
        }

        if (orderToModify != null) {
          Order updatedOrder = orderToModify.copyWith(orderStatus: newStatus, isSynced: false);
          await _orderRepository.savePendingOrder(updatedOrder, keyToSave);

          if (currentState.order?.id == orderIdToUpdate) {
            state = AsyncValue.data(currentState.copyWith(order: updatedOrder));
          }

          _setError("Estado del pedido local actualizado a '$newStatus'.", durationSeconds: 4);
          return true;
        } else {
          _setError("No se encontró el pedido local '$orderIdToUpdate' para actualizar estado.", durationSeconds: 5);
          return false;
        }
      }

      debugPrint("[CurrentOrder] Enqueuing status update for API Order ID: $orderIdToUpdate to '$newStatus'");

      _syncManager.addOperation(
        SyncOperationType.updateOrderStatus,
        {'orderId': orderIdToUpdate, 'newStatus': newStatus},
      );
      _setError("Actualización de estado encolada para sinc.", durationSeconds: 4);

      Order? cachedOrder = await _orderRepository.getOrderById(orderIdToUpdate);
      if (cachedOrder != null) {
        await _orderRepository.savePendingOrder(
          cachedOrder.copyWith(orderStatus: newStatus, isSynced: false),
          orderIdToUpdate,
        );
      }

      state.whenData((currentState) {
        state = AsyncValue.data(currentState);
      });

      return true;
    } catch (e) {
      _setError("Error al actualizar estado: ${e.toString()}", durationSeconds: 5);
      return false;
    }
  }

  /// Cargar orden para edición
  Future<void> loadOrderForEditing(Order orderToLoad) async {
    debugPrint("[CurrentOrder.loadOrderForEditing] Loading order ID: ${orderToLoad.id ?? 'N/A'} for editing.");

    state = const AsyncValue.loading();
    _saveOrderDebounce?.cancel();

    try {
      await clearOrder();
      final currentState = state.requireValue;

      List<OrderItem> itemsToAdd = [];
      String errorDetails = "";
      bool errorAddingItems = false;

      final List<String> productIds = [];
      for (final item in orderToLoad.items) {
        if (item.variationId != null && item.variationId! > 0) {
          productIds.add(item.variationId.toString());
        } else {
          productIds.add(item.productId);
        }
      }

      Map<String, app_product.Product> productsMap = {};
      try {
        productsMap = await _productRepository.getProductsByIds(productIds, forceApi: true);
        debugPrint("[CurrentOrder.loadOrderForEditing] Batch loaded ${productsMap.length}/${productIds.length} products");
      } catch (e) {
        debugPrint("[CurrentOrder.loadOrderForEditing] Batch load error: $e. Falling back to individual loads.");
        errorAddingItems = true;
        errorDetails = "Error al cargar productos en batch. ";
      }

      for (final item in orderToLoad.items) {
        final productId = (item.variationId != null && item.variationId! > 0)
            ? item.variationId.toString()
            : item.productId;

        final productDetails = productsMap[productId];

        if (productDetails == null) {
          debugPrint("... Product/Variation ID $productId not found for item '${item.name}'. Using original item data.");
          itemsToAdd.add(item.copyWith());
          errorAddingItems = true;
          errorDetails += "'${item.name}' (No encontrado) ";
          continue;
        }

        itemsToAdd.add(item.copyWith(
          name: productDetails.name,
          price: productDetails.displayPrice,
          regularPrice: () => productDetails.regularPrice ?? productDetails.price,
          sku: productDetails.sku,
          attributes: item.attributes ??
              (productDetails.isVariation
                  ? productDetails.attributes?.map((a) => Map<String, String>.from(a)).toList()
                  : null),
          productType: productDetails.type,
          manageStock: productDetails.manageStock,
          stockQuantity: () => productDetails.stockQuantity,
        ));

        debugPrint("... Loaded item for editing: ${productDetails.name}");
      }

      final loadedOrder = orderToLoad.copyWith(
        items: itemsToAdd,
        date: DateTime.now(),
        isSynced: false,
        id: hiveCurrentOrderPendingKey,
        number: null,
        orderStatus: 'pending',
      );

      final recalculated = _recalculateOrder(loadedOrder, currentState.taxRate);
      await _saveOrderWithDebounce(recalculated, force: true);

      state = AsyncValue.data(currentState.copyWith(
        order: recalculated,
        isLoading: false,
        error: errorAddingItems
            ? 'Pedido cargado para edición. Algunos detalles de productos no pudieron actualizarse desde el servidor: ${errorDetails.trim()}'
            : null,
      ));
    } catch (e, stack) {
      debugPrint("[CurrentOrder.loadOrderForEditing] ERROR: $e\n$stack");
      state = AsyncValue.error(e, stack);
    }
  }

  /// Duplicar orden
  Future<void> duplicateOrder(Order orderToDuplicate) async {
    debugPrint("[CurrentOrder.duplicateOrder] Duplicating order ID: ${orderToDuplicate.id ?? 'N/A'}");

    state = const AsyncValue.loading();
    _saveOrderDebounce?.cancel();

    try {
      await clearOrder();
      final currentState = state.requireValue;

      List<OrderItem> duplicatedItems = [];
      bool errorFetchingProducts = false;
      String errorDetails = "";

      final List<String> productIds = [];
      for (final item in orderToDuplicate.items) {
        if (item.variationId != null && item.variationId! > 0) {
          productIds.add(item.variationId.toString());
        } else {
          productIds.add(item.productId);
        }
      }

      Map<String, app_product.Product> productsMap = {};
      try {
        productsMap = await _productRepository.getProductsByIds(productIds, forceApi: true);
        debugPrint("[CurrentOrder.duplicateOrder] Batch loaded ${productsMap.length}/${productIds.length} products");
      } catch (e) {
        debugPrint("[CurrentOrder.duplicateOrder] Batch load error: $e");
        errorFetchingProducts = true;
        errorDetails = "Error al cargar productos en batch. ";
      }

      for (final item in orderToDuplicate.items) {
        final productId = (item.variationId != null && item.variationId! > 0)
            ? item.variationId.toString()
            : item.productId;

        final productDetails = productsMap[productId];

        if (productDetails == null) {
          errorFetchingProducts = true;
          errorDetails += "'${item.name}' (Ya no disponible) ";
          debugPrint("... Item '${item.name}' (ID: $productId) not found. Omitting from duplicate.");
          continue;
        }

        duplicatedItems.add(OrderItem(
          productId: productDetails.isVariation
              ? (productDetails.parentId?.toString() ?? productDetails.id)
              : productDetails.id,
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
          stockQuantity: productDetails.stockQuantity,
        ));

        debugPrint("... Duplicated item: ${productDetails.name}");
      }

      final duplicatedOrder = Order(
        id: hiveCurrentOrderPendingKey,
        number: null,
        customerId: orderToDuplicate.customerId,
        customerName: orderToDuplicate.customerName,
        items: duplicatedItems,
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        date: DateTime.now(),
        orderStatus: 'pending',
        isSynced: false,
      );

      final recalculated = _recalculateOrder(duplicatedOrder, currentState.taxRate);
      await _saveOrderWithDebounce(recalculated, force: true);

      state = AsyncValue.data(currentState.copyWith(
        order: recalculated,
        isLoading: false,
        error: errorFetchingProducts
            ? "Orden duplicada. Algunos productos no pudieron ser actualizados desde el servidor y fueron omitidos: ${errorDetails.trim()}"
            : null,
      ));
    } catch (e, stack) {
      debugPrint("[CurrentOrder.duplicateOrder] ERROR: $e\n$stack");
      state = AsyncValue.error(e, stack);
    }
  }

  /// Actualizar item con nueva variante
  Future<bool> updateOrderItemWithNewVariant({
    required OrderItem originalOrderItem,
    required app_product.Product selectedVariation,
  }) async {
    try {
      final currentState = state.requireValue;
      final currentOrder = currentState.order;

      if (currentOrder == null) return false;

      debugPrint("[CurrentOrder.updateOrderItemWithNewVariant] Original: ${originalOrderItem.name} (ID: ${originalOrderItem.productId}/${originalOrderItem.variationId}), New Variation: ${selectedVariation.name} (ID: ${selectedVariation.id})");

      final String originalItemUniqueIdInCart = _getUniqueCartItemId(
        originalOrderItem.productId,
        originalOrderItem.variationId,
      );

      final items = List<OrderItem>.from(currentOrder.items);
      final itemIndex = items.indexWhere((item) =>
      _getUniqueCartItemId(item.productId, item.variationId) == originalItemUniqueIdInCart);

      if (itemIndex == -1) {
        _setError("No se encontró el ítem original en el pedido para actualizar la variante.", durationSeconds: 5);
        return false;
      }

      List<Map<String, String>>? newAttributes;
      if (selectedVariation.attributes != null) {
        newAttributes = selectedVariation.attributes!.map((attr) {
          return <String, String>{
            'name': attr['name']?.toString() ?? '',
            'option': attr['option']?.toString() ?? '',
            'slug': attr['slug']?.toString() ?? (attr['name']?.toString() ?? '').toLowerCase().replaceAll(' ', '-'),
          };
        }).toList();

        if (newAttributes.every((attr) => (attr['name'] ?? '').isEmpty || (attr['option'] ?? '').isEmpty)) {
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
      final updatedOrder = currentOrder.copyWith(items: items);

      debugPrint("... OrderItem actualizado con la nueva variante: ${newOrderItem.name}");

      final recalculated = _recalculateOrder(updatedOrder, currentState.taxRate);
      await _saveOrderWithDebounce(recalculated);

      state = AsyncValue.data(currentState.copyWith(
        order: recalculated,
        error: null,
      ));

      return true;
    } catch (e) {
      debugPrint("Error actualizando variante en CurrentOrder: $e");
      _setError("Error al actualizar la variante del producto: ${e.toString()}", durationSeconds: 5);
      return false;
    }
  }

  String? _currentDraftWooCommerceId;

  Future<void> _sendDraftToWooCommerce(Order draft) async {
    try {
      debugPrint("[CurrentOrder] 🔄 Enviando borrador a WooCommerce como 'pending'...");

      final draftForWC = draft.copyWith(
        orderStatus: 'pending',
      );

      final wooCommerceId = await _wooCommerceService.createOrderAPI(draftForWC);

      if (wooCommerceId != null) {
        _currentDraftWooCommerceId = wooCommerceId;

        debugPrint(
            "[CurrentOrder] ✅ Borrador enviado a WC como 'pending' (ID: $wooCommerceId)\n"
                "    Stock reservado por 5 minutos en WooCommerce"
        );

        final updatedDraft = draft.copyWith(id: wooCommerceId);
        await _orderRepository.savePendingOrder(updatedDraft, hiveCurrentOrderPendingKey);

      } else {
        debugPrint("[CurrentOrder] ⚠️ WooCommerce no retornó ID para el borrador");
      }

    } catch (e) {
      debugPrint("[CurrentOrder] ⚠️ Error enviando borrador a WC (no crítico): $e");
    }
  }

  Future<void> _cancelDraftInWooCommerce() async {
    if (_currentDraftWooCommerceId == null) {
      return;
    }

    try {
      debugPrint(
          "[CurrentOrder] 🔄 Cancelando borrador en WooCommerce "
              "(ID: $_currentDraftWooCommerceId)..."
      );

      await _wooCommerceService.updateOrderStatus(
        _currentDraftWooCommerceId!,
        'cancelled',
      );

      debugPrint(
          "[CurrentOrder] ✅ Borrador cancelado en WC\n"
              "    Stock liberado automáticamente"
      );

      _currentDraftWooCommerceId = null;

    } catch (e) {
      debugPrint("[CurrentOrder] ⚠️ Error cancelando borrador en WC: $e");
    }
  }
}

@riverpod
OrderSummary orderSummary(OrderSummaryRef ref) {
  final currentOrderAsync = ref.watch(currentOrderProvider);

  return currentOrderAsync.when(
    data: (state) {
      if (state.order == null) {
        return OrderSummary.empty(state.taxRate);
      }
      return OrderSummary.fromOrder(state.order!, state.taxRate);
    },
    loading: () => OrderSummary.empty(0.13),
    error: (_, __) => OrderSummary.empty(0.13),
  );
}
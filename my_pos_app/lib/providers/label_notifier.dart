// lib/providers/label_notifier.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/label_print_item.dart';
import '../models/label_print_item_compact.dart';
import '../models/inventory_movement.dart';
import '../models/product.dart' as app_product;
import '../config/constants.dart';
import '../repositories/product_repository.dart';
import '../services/database_service.dart';
import '../services/label_converter_service.dart';
import 'label_state.dart';
import 'shared_providers.dart';

part 'label_notifier.g.dart';

/// ✅ OBJECTBOX ONLY: Label Notifier (migrado de Hive)
@riverpod
class Label extends _$Label {
  late SharedPreferences _prefs;
  late ProductRepository _productRepository;

  // ✅ OBJECTBOX - Base de datos principal
  DatabaseService? _db;
  LabelConverterService? _converter;

  @override
  LabelState build() {
    debugPrint("[Label] build() called - Initializing");

    _prefs = ref.read(sharedPreferencesProvider);
    _productRepository = ref.read(productRepositoryProvider);

    // ✅ OBJECTBOX: Inicializar
    _initObjectBox();

    final initialState = LabelState.initial();

    // ✓ CORRECCIÓN RACE CONDITION: Diferir la carga de settings y queue después de build()
    // para prevenir el error "Tried to read the state of an uninitialized provider"
    Future.microtask(() {
      _loadSettingsAndQueue();
    });

    return initialState;
  }

  Future<void> _initObjectBox() async {
    try {
      _db = await DatabaseService.getInstance();
      _converter = LabelConverterService();
      debugPrint("[Label] ✅ ObjectBox initialized");
    } catch (e) {
      debugPrint("[Label] ⚠️ ObjectBox initialization failed: $e");
    }
  }

  Future<void> _loadSettingsAndQueue() async {
    // Load settings
    final settingsJson = _prefs.getString(labelSettingsPrefKey);
    LabelSettings settings = const LabelSettings();

    if (settingsJson != null) {
      try {
        settings = LabelSettings.fromJson(jsonDecode(settingsJson));
      } catch (e) {
        debugPrint("Error loading label settings, using defaults. Error: $e");
      }
    }

    // ✅ OBJECTBOX ONLY: Cargar cola desde ObjectBox
    List<LabelPrintItem> loadedItems = [];

    if (_db == null || _converter == null) {
      debugPrint("[Label] ❌ ERROR: ObjectBox not initialized");
      // Return empty list, no fallback
    } else {
      try {
        final box = _db!.store.box<LabelPrintItemCompact>();
        final compactItems = box.getAll();

        // Convertir a LabelPrintItem
        loadedItems = compactItems.map((compact) => _converter!.compactToLabel(compact)).toList();
        debugPrint("[Label] ✅ Loaded ${loadedItems.length} items from ObjectBox (products will load on-demand)");
      } catch (e) {
        debugPrint("[Label] ❌ Error loading from ObjectBox: $e");
        // Return empty list, no fallback
      }
    }

    // ⚡ OPTIMIZACIÓN EXTREMA: Ya NO cargamos los productos aquí.
    // Se cargarán bajo demanda cuando se necesiten para imprimir o editar.
    // Esto hace que la pantalla cargue instantáneamente incluso con 100+ items.

    state = state.copyWith(
      settings: settings,
      printQueue: loadedItems,
      isQueueLoaded: true,
    );
  }

  Future<void> _saveSettings() async {
    await _prefs.setString(
        labelSettingsPrefKey, jsonEncode(state.settings.toJson()));
  }

  /// ✅ OBJECTBOX ONLY: Guardar cola de labels
  Future<void> saveQueue() async {
    if (_db == null || _converter == null) {
      debugPrint("[Label] ❌ ERROR: ObjectBox not initialized, cannot save queue");
      return;
    }

    try {
      final box = _db!.store.box<LabelPrintItemCompact>();

      // ⚡ FIX: Obtener todos los items existentes para preservar localIds
      final existingQuery = box.query().build();
      final existingItems = existingQuery.find();
      existingQuery.close();

      // Crear mapa de itemId -> ObjectBox localId
      final existingLocalIds = <String, int>{};
      for (final existing in existingItems) {
        existingLocalIds[existing.itemId] = existing.localId;
      }

      // Convertir items y asignar localId si ya existen
      final compactItems = state.printQueue.map((item) {
        final compact = _converter!.labelToCompact(item);

        // ⚡ FIX: Si ya existe, copiar el localId para actualizar
        if (existingLocalIds.containsKey(compact.itemId)) {
          compact.localId = existingLocalIds[compact.itemId]!;
        }

        return compact;
      }).toList();

      // ⚡ FIX: Guardar todos sin removeAll() para evitar race conditions
      // putMany() actualizará existentes y creará nuevos
      box.putMany(compactItems);

      // ⚡ FIX: Eliminar items que ya no están en la cola
      final currentItemIds = state.printQueue.map((i) => i.id).toSet();
      final toRemove = existingItems
          .where((e) => !currentItemIds.contains(e.itemId))
          .map((e) => e.localId)
          .toList();

      if (toRemove.isNotEmpty) {
        box.removeMany(toRemove);
        debugPrint("[Label] 🗑️ Removed ${toRemove.length} stale items from ObjectBox");
      }

      debugPrint("[Label] ✅ Saved ${compactItems.length} items to ObjectBox (${existingLocalIds.length} updated, ${compactItems.length - existingLocalIds.length} new)");
    } catch (e) {
      debugPrint("[Label] ❌ Error saving to ObjectBox: $e");
    }
  }

  void addOrUpdateItem(LabelPrintItem item) {
    final indexInQueue = state.printQueue.indexWhere((i) => i.id == item.id);
    final List<LabelPrintItem> updatedQueue = List.from(state.printQueue);

    if (indexInQueue != -1) {
      updatedQueue[indexInQueue] = item;
    } else {
      updatedQueue.add(item);
    }

    state = state.copyWith(
      printQueue: updatedQueue,
      itemBeingEdited: null,
    );

    saveQueue();
  }

  void addMultipleItems(List<LabelPrintItem> items) {
    if (items.isEmpty) return;

    final updatedQueue = [...state.printQueue, ...items];
    state = state.copyWith(printQueue: updatedQueue);

    saveQueue();
  }

  Future<int> addMovementItemsToQueue(InventoryMovement movement) async {
    final itemsToAdd = <LabelPrintItem>[];
    final itemsWithPositiveStock =
    movement.items.where((item) => item.quantityChanged > 0);

    for (final item in itemsWithPositiveStock) {
      app_product.Product? productDetails;
      app_product.Product? parentDetails;

      try {
        // 📌 CORRECCIÓN CLAVE: Cambiar forceApi a false para usar ObjectBox/Hive
        if (item.variationId != null && item.variationId!.isNotEmpty) {
          productDetails = await _productRepository.getVariationById(
              item.productId, item.variationId!,
              forceApi: false);
          if (productDetails?.parentId != null) {
            parentDetails = await _productRepository.getProductById(
                productDetails!.parentId.toString(),
                forceApi: false);
          }
        } else {
          productDetails = await _productRepository.getProductById(
              item.productId,
              forceApi: false);
        }

        if (productDetails != null) {
          final labelItem = LabelPrintItem(
            id: const Uuid().v4(),
            productId: item.productId,
            resolvedVariantId: item.variationId,
            quantity: item.quantityChanged,
            selectedVariants:
            productDetails.attributes?.fold<Map<String, String>>({},
                    (prev, attr) {
                  prev[attr['name'] ?? ''] = attr['option'] ?? '';
                  return prev;
                }) ??
                {},
            barcode: productDetails.barcode ?? productDetails.sku,
            // ⚡ Almacenar en caché para carga rápida
            cachedProductName: productDetails.name,
            cachedSku: productDetails.sku,
            product: parentDetails ?? productDetails,
            resolvedVariant:
            item.variationId != null ? productDetails : null,
          );
          itemsToAdd.add(labelItem);
        }
      } catch (e) {
        debugPrint(
            "Error fetching product details for label queue from history: $e");
      }
    }

    if (itemsToAdd.isNotEmpty) {
      addMultipleItems(itemsToAdd);
    }
    return itemsToAdd.length;
  }

  void removeItem(String itemId) {
    final updatedQueue =
    state.printQueue.where((item) => item.id != itemId).toList();

    state = state.copyWith(
      printQueue: updatedQueue,
      itemBeingEdited: state.itemBeingEdited?.id == itemId
          ? null
          : state.itemBeingEdited,
    );

    saveQueue();
  }

  void startEditing(String itemId) {
    final item = state.printQueue.firstWhereOrNull((item) => item.id == itemId);
    state = state.copyWith(itemBeingEdited: item);
  }

  void cancelEditing() {
    state = state.copyWith(itemBeingEdited: null);
  }

  void duplicateAndPrepareForEditing(String originalItemId) {
    final originalItem =
    state.printQueue.firstWhereOrNull((item) => item.id == originalItemId);
    if (originalItem == null) return;

    final newItem = LabelPrintItem(
      id: const Uuid().v4(),
      productId: originalItem.productId,
      resolvedVariantId: originalItem.resolvedVariantId,
      quantity: originalItem.quantity,
      selectedVariants: Map.from(originalItem.selectedVariants),
      barcode: originalItem.barcode,
      // ✅ FIX: Copiar campos cacheados para evitar errores al editar
      cachedProductName: originalItem.cachedProductName,
      cachedSku: originalItem.cachedSku,
      product: originalItem.product,
      resolvedVariant: originalItem.resolvedVariant,
    );

    state = state.copyWith(itemBeingEdited: newItem);
  }

  void clearQueue() {
    state = state.copyWith(
      printQueue: [],
      itemBeingEdited: null,
    );
    saveQueue();
  }

  void updateSettings(LabelSettings newSettings) {
    state = state.copyWith(settings: newSettings);
    _saveSettings();
  }

  void updateLabelLayout(double width, double height) {
    final newLayout = {'width': width, 'height': height};
    final currentSettings = state.settings;

    if (currentSettings.labelLayout['width'] != width ||
        currentSettings.labelLayout['height'] != height) {
      state = state.copyWith(
        settings: currentSettings.copyWith(labelLayout: newLayout),
      );
      _saveSettings();
    }
  }

  void updateVisibleAttribute(String key, bool isVisible) {
    final newAttributes =
    Map<String, bool>.from(state.settings.visibleAttributes);

    if (newAttributes[key] != isVisible) {
      newAttributes[key] = isVisible;
      state = state.copyWith(
        settings: state.settings.copyWith(visibleAttributes: newAttributes),
      );
      _saveSettings();
    }
  }

  void updateFieldOrder(List<String> newOrder) {
    state = state.copyWith(
      settings: state.settings.copyWith(fieldOrder: newOrder),
    );
    _saveSettings();
  }

  void updateFieldLayout(String fieldKey, Map<String, dynamic> newLayoutData) {
    final newLayouts =
    Map<String, Map<String, dynamic>>.from(state.settings.fieldLayouts);
    newLayouts[fieldKey] = {
      ...newLayouts[fieldKey] ?? {},
      ...newLayoutData,
    };

    state = state.copyWith(
      settings: state.settings.copyWith(fieldLayouts: newLayouts),
    );
    _saveSettings();
  }
}
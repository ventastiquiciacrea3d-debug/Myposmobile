// lib/providers/label_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/label_print_item.dart';
import '../models/inventory_movement.dart';
import '../models/product.dart' as app_product;
import '../config/constants.dart';
import '../locator.dart';
import '../repositories/product_repository.dart';

class LabelProvider extends ChangeNotifier {
  List<LabelPrintItem> _printQueue = [];
  LabelSettings _settings = const LabelSettings();

  LabelPrintItem? _itemBeingEdited;

  bool _isPrinting = false;
  final SharedPreferences _prefs = getIt<SharedPreferences>();
  final Box<LabelPrintItem> _labelQueueBox = Hive.box<LabelPrintItem>(hiveLabelQueueBoxName);
  final ProductRepository _productRepository = getIt<ProductRepository>();
  bool _isQueueLoaded = false;

  LabelProvider() {
    _loadSettings();
    _loadQueue();
  }

  List<LabelPrintItem> get printQueue => _printQueue;
  LabelSettings get settings => _settings;
  bool get isPrinting => _isPrinting;
  bool get isQueueLoaded => _isQueueLoaded;

  LabelPrintItem? get itemBeingEdited => _itemBeingEdited;
  String? get editingItemId => _itemBeingEdited?.id;

  Future<void> _loadSettings() async {
    final settingsJson = _prefs.getString(labelSettingsPrefKey);
    if (settingsJson != null) {
      try {
        _settings = LabelSettings.fromJson(jsonDecode(settingsJson));
      } catch (e) {
        debugPrint("Error loading label settings, using defaults. Error: $e");
        _settings = const LabelSettings();
      }
    } else {
      _settings = const LabelSettings();
    }
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _prefs.setString(labelSettingsPrefKey, jsonEncode(_settings.toJson()));
  }

  Future<void> _loadQueue() async {
    if (_isQueueLoaded) return;
    final loadedItems = _labelQueueBox.values.toList();
    await Future.wait(loadedItems.map((item) async {
      item.product ??= await _productRepository.getProductById(item.productId);
      if (item.resolvedVariantId != null && item.resolvedVariantId!.isNotEmpty) {
        item.resolvedVariant ??= await _productRepository.getVariationById(item.productId, item.resolvedVariantId!);
      }
      return item;
    }));
    _printQueue = loadedItems;
    _isQueueLoaded = true;
    notifyListeners();
  }

  Future<void> saveQueue() async {
    await _labelQueueBox.clear();
    await _labelQueueBox.putAll({for (var item in _printQueue) item.id!: item});
  }

  void addOrUpdateItem(LabelPrintItem item) {
    final indexInQueue = _printQueue.indexWhere((i) => i.id == item.id);

    if (indexInQueue != -1) {
      _printQueue[indexInQueue] = item;
    } else {
      _printQueue.add(item);
    }

    _itemBeingEdited = null;
    saveQueue();
    notifyListeners();
  }

  void addMultipleItems(List<LabelPrintItem> items) {
    if (items.isEmpty) return;
    _printQueue.addAll(items);
    saveQueue();
    notifyListeners();
  }

  Future<int> addMovementItemsToQueue(InventoryMovement movement) async {
    final itemsToAdd = <LabelPrintItem>[];
    final productRepo = getIt<ProductRepository>();
    final itemsWithPositiveStock = movement.items.where((item) => item.quantityChanged > 0);

    for (final item in itemsWithPositiveStock) {
      app_product.Product? productDetails;
      app_product.Product? parentDetails;

      try {
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
          itemsToAdd.add(labelItem);
        }
      } catch (e) {
        debugPrint("Error fetching product details for label queue from history: $e");
      }
    }

    if (itemsToAdd.isNotEmpty) {
      addMultipleItems(itemsToAdd);
    }
    return itemsToAdd.length;
  }

  void removeItem(String itemId) {
    _printQueue.removeWhere((item) => item.id == itemId);
    if (_itemBeingEdited?.id == itemId) _itemBeingEdited = null;
    saveQueue();
    notifyListeners();
  }

  void startEditing(String itemId) {
    _itemBeingEdited = _printQueue.firstWhereOrNull((item) => item.id == itemId);
    notifyListeners();
  }

  void cancelEditing() {
    _itemBeingEdited = null;
    notifyListeners();
  }

  void duplicateAndPrepareForEditing(String originalItemId) {
    final originalItem = _printQueue.firstWhereOrNull((item) => item.id == originalItemId);
    if (originalItem == null) return;

    final newItem = LabelPrintItem(
      id: const Uuid().v4(),
      productId: originalItem.productId,
      resolvedVariantId: originalItem.resolvedVariantId,
      quantity: originalItem.quantity,
      selectedVariants: Map.from(originalItem.selectedVariants),
      barcode: originalItem.barcode,
      product: originalItem.product,
      resolvedVariant: originalItem.resolvedVariant,
    );

    _itemBeingEdited = newItem;
    notifyListeners();
  }

  void clearQueue() {
    _printQueue.clear();
    _itemBeingEdited = null;
    saveQueue();
    notifyListeners();
  }

  void updateSettings(LabelSettings newSettings) {
    _settings = newSettings;
    _saveSettings();
    notifyListeners();
  }

  void updateLabelLayout(double width, double height) {
    final newLayout = {'width': width, 'height': height};
    if (settings.labelLayout['width'] != width || settings.labelLayout['height'] != height) {
      _settings = _settings.copyWith(labelLayout: newLayout);
      _saveSettings();
      notifyListeners();
    }
  }

  void updateVisibleAttribute(String key, bool isVisible) {
    final newAttributes = Map<String, bool>.from(settings.visibleAttributes);
    if (newAttributes[key] != isVisible) {
      newAttributes[key] = isVisible;
      _settings = _settings.copyWith(visibleAttributes: newAttributes);
      _saveSettings();
      notifyListeners();
    }
  }

  void updateFieldOrder(List<String> newOrder) {
    _settings = _settings.copyWith(fieldOrder: newOrder);
    _saveSettings();
    notifyListeners();
  }

  void updateFieldLayout(String fieldKey, Map<String, dynamic> newLayoutData) {
    final newLayouts = Map<String, Map<String, dynamic>>.from(settings.fieldLayouts);
    newLayouts[fieldKey] = {
      ...newLayouts[fieldKey] ?? {},
      ...newLayoutData,
    };
    _settings = _settings.copyWith(fieldLayouts: newLayouts);
    _saveSettings();
    notifyListeners();
  }
}
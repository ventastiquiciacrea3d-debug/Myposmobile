// lib/models/inventory_movement.dart
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

part 'inventory_movement.g.dart';

@HiveType(typeId: 4)
enum InventoryMovementType {
  @HiveField(0)
  manualAdjustment,
  @HiveField(1)
  initialStock,
  @HiveField(2)
  sale,
  @HiveField(3)
  refund,
  @HiveField(4)
  stockReceipt,
  @HiveField(5)
  stockCorrection,
  @HiveField(6)
  damageOrLoss,
  @HiveField(7)
  transferOut,
  @HiveField(8)
  transferIn,
  @HiveField(9)
  massEntry,
  @HiveField(10)
  massExit,
  @HiveField(11)
  massManualAdjustment,
  @HiveField(12)
  supplierReceipt,
  @HiveField(13)
  customerReturnMass,
  @HiveField(14)
  toTrash,
  @HiveField(15)
  unknown,
}

@HiveType(typeId: 5)
class InventoryMovementLine extends HiveObject {
  @HiveField(0)
  final String productId;
  @HiveField(1)
  final String? variationId;
  @HiveField(2)
  final String productName;
  @HiveField(3)
  final String sku;
  @HiveField(4)
  final int quantityChanged;
  @HiveField(5)
  final int? stockBefore;
  @HiveField(6)
  final int? stockAfter;

  InventoryMovementLine({
    required this.productId,
    this.variationId,
    required this.productName,
    required this.sku,
    required this.quantityChanged,
    this.stockBefore,
    this.stockAfter,
  });

  factory InventoryMovementLine.fromJson(Map<String, dynamic> json) {
    return InventoryMovementLine(
      productId: json['productId']?.toString() ?? '',
      variationId: json['variationId']?.toString(),
      productName: json['productName'] as String? ?? 'N/A',
      sku: json['sku'] as String? ?? '',
      quantityChanged: (json['quantityChanged'] as num?)?.toInt() ?? 0,
      stockBefore: (json['stockBefore'] as num?)?.toInt(),
      stockAfter: (json['stockAfter'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variationId': variationId,
    'productName': productName,
    'sku': sku,
    'quantityChanged': quantityChanged,
    'stockBefore': stockBefore,
    'stockAfter': stockAfter,
  };

  InventoryMovementLine copyWith({
    String? productId,
    ValueGetter<String?>? getVariationId,
    String? productName,
    String? sku,
    int? quantityChanged,
    ValueGetter<int?>? getStockBefore,
    ValueGetter<int?>? getStockAfter,
  }) {
    return InventoryMovementLine(
      productId: productId ?? this.productId,
      variationId: getVariationId != null ? getVariationId() : this.variationId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      quantityChanged: quantityChanged ?? this.quantityChanged,
      stockBefore: getStockBefore != null ? getStockBefore() : this.stockBefore,
      stockAfter: getStockAfter != null ? getStockAfter() : this.stockAfter,
    );
  }
}

@HiveType(typeId: 6)
class InventoryMovement extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final DateTime date;
  @HiveField(2)
  final InventoryMovementType type;
  @HiveField(3)
  final String description;
  @HiveField(4)
  final List<InventoryMovementLine> items;
  @HiveField(5)
  final String? referenceId;
  @HiveField(6)
  final String? userId;
  @HiveField(7)
  final bool isSynced;

  // Campo no persistido, solo para UI
  final String? userName;

  InventoryMovement({
    required this.id,
    required this.date,
    required this.type,
    required this.description,
    required this.items,
    this.referenceId,
    this.userId,
    this.isSynced = false,
    this.userName,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    var itemsList = (json['items'] as List<dynamic>?)
        ?.map((item) => InventoryMovementLine.fromJson(item as Map<String, dynamic>))
        .toList() ?? [];

    String typeString = json['type'] as String? ?? 'unknown';
    InventoryMovementType movementType = InventoryMovementType.values.firstWhere(
          (e) => e.name.toLowerCase() == typeString.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), ''),
      orElse: () => InventoryMovementType.unknown,
    );

    return InventoryMovement(
      id: json['id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      type: movementType,
      description: json['description'] as String? ?? '',
      items: itemsList,
      referenceId: json['referenceId'] as String?,
      userId: json['userId']?.toString(),
      userName: json['userName'] as String?,
      isSynced: json['isSynced'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'type': type.name,
    'description': description,
    'items': items.map((item) => item.toJson()).toList(),
    'referenceId': referenceId,
    'userId': userId,
  };

  InventoryMovement copyWith({
    String? id,
    DateTime? date,
    InventoryMovementType? type,
    String? description,
    List<InventoryMovementLine>? items,
    ValueGetter<String?>? getReferenceId,
    ValueGetter<String?>? getUserId,
    bool? isSynced,
    String? userName,
  }) {
    return InventoryMovement(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      description: description ?? this.description,
      items: items ?? List<InventoryMovementLine>.from(this.items.map((item) => item.copyWith())),
      referenceId: getReferenceId != null ? getReferenceId() : this.referenceId,
      userId: getUserId != null ? getUserId() : this.userId,
      isSynced: isSynced ?? this.isSynced,
      userName: userName ?? this.userName,
    );
  }
}
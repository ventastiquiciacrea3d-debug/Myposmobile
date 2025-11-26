// lib/models/inventory_movement_compact.dart
import 'package:objectbox/objectbox.dart';
import 'dart:convert';

/// InventoryMovement Compacto para ObjectBox: ~100 bytes
///
/// Reducción de ~600 bytes (Hive) → 100 bytes (ObjectBox)
@Entity()
class InventoryMovementCompact {
  // ObjectBox ID (auto-increment)
  @Id()
  int localId = 0;

  // ==================== IDs (8 bytes) ====================

  /// UUID del movimiento
  @Index()
  @Unique()
  String movementId;

  /// User ID que realizó el movimiento
  int? userId;

  // ==================== STRINGS (50 bytes) ====================

  /// Descripción del movimiento (max 100 chars)
  String description;

  /// Nombre del usuario
  String userName;

  // ==================== LINE ITEMS (JSON comprimido) ====================

  /// Items del movimiento en formato JSON comprimido
  /// [{"pid":123,"vid":456,"n":"Producto","s":"SKU","qc":10,"sb":50,"sa":60}]
  String itemsJson;

  // ==================== METADATA (16 bytes) ====================

  /// Fecha del movimiento
  @Property(type: PropertyType.date)
  DateTime date;

  /// Tipo de movimiento: 0=manualAdjustment, 1=initialStock, 2=sale, 3=refund,
  /// 4=stockReceipt, 5=stockCorrection, 6=damageOrLoss, 7=transferOut,
  /// 8=transferIn, 9=massEntry, 10=massExit, 11=massManualAdjustment,
  /// 12=supplierReceipt, 13=customerReturnMass, 14=toTrash, 15=unknown
  int movementTypeCode;

  /// Flags (8 bits)
  /// Bit 0: isSynced
  /// Bit 1-7: Reservados
  int flags;

  // ==================== CONSTRUCTOR ====================

  InventoryMovementCompact({
    required this.movementId,
    this.userId,
    required this.description,
    required this.userName,
    required this.itemsJson,
    required this.date,
    required this.movementTypeCode,
    required this.flags,
  });

  // ==================== GETTERS HELPERS ====================

  bool get isSynced => (flags & 0x01) != 0;

  String get movementType {
    switch (movementTypeCode) {
      case 0:
        return 'manualAdjustment';
      case 1:
        return 'initialStock';
      case 2:
        return 'sale';
      case 3:
        return 'refund';
      case 4:
        return 'stockReceipt';
      case 5:
        return 'stockCorrection';
      case 6:
        return 'damageOrLoss';
      case 7:
        return 'transferOut';
      case 8:
        return 'transferIn';
      case 9:
        return 'massEntry';
      case 10:
        return 'massExit';
      case 11:
        return 'massManualAdjustment';
      case 12:
        return 'supplierReceipt';
      case 13:
        return 'customerReturnMass';
      case 14:
        return 'toTrash';
      default:
        return 'unknown';
    }
  }

  List<InventoryMovementLineCompact> get items {
    try {
      final List<dynamic> jsonList = json.decode(itemsJson);
      return jsonList.map((j) => InventoryMovementLineCompact.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  // ==================== SETTERS HELPERS ====================

  set isSynced(bool value) {
    if (value) {
      flags |= 0x01;
    } else {
      flags &= ~0x01;
    }
  }

  static int parseMovementType(String type) {
    switch (type.toLowerCase()) {
      case 'manualadjustment':
        return 0;
      case 'initialstock':
        return 1;
      case 'sale':
        return 2;
      case 'refund':
        return 3;
      case 'stockreceipt':
        return 4;
      case 'stockcorrection':
        return 5;
      case 'damageorloss':
        return 6;
      case 'transferout':
        return 7;
      case 'transferin':
        return 8;
      case 'massentry':
        return 9;
      case 'massexit':
        return 10;
      case 'massmanualadjustment':
        return 11;
      case 'supplierreceipt':
        return 12;
      case 'customerreturnmass':
        return 13;
      case 'totrash':
        return 14;
      default:
        return 15;
    }
  }

  // ==================== TO STRING ====================

  @override
  String toString() {
    return 'InventoryMovementCompact(id: $movementId, type: $movementType, date: $date, items: ${items.length})';
  }
}

/// InventoryMovementLine Compacto (solo en JSON, no es entidad separada)
class InventoryMovementLineCompact {
  final int productId;
  final int? variationId;
  final String productName;
  final String sku;
  final int quantityChanged;
  final int? stockBefore;
  final int? stockAfter;

  InventoryMovementLineCompact({
    required this.productId,
    this.variationId,
    required this.productName,
    required this.sku,
    required this.quantityChanged,
    this.stockBefore,
    this.stockAfter,
  });

  // Formato JSON comprimido: {"pid":123,"vid":456,"n":"Producto","s":"SKU","qc":10,"sb":50,"sa":60}
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'pid': productId,
      'n': productName,
      's': sku,
      'qc': quantityChanged,
    };

    if (variationId != null) json['vid'] = variationId;
    if (stockBefore != null) json['sb'] = stockBefore;
    if (stockAfter != null) json['sa'] = stockAfter;

    return json;
  }

  factory InventoryMovementLineCompact.fromJson(Map<String, dynamic> json) {
    return InventoryMovementLineCompact(
      productId: json['pid'] as int,
      variationId: json['vid'] as int?,
      productName: json['n'] as String,
      sku: json['s'] as String,
      quantityChanged: json['qc'] as int,
      stockBefore: json['sb'] as int?,
      stockAfter: json['sa'] as int?,
    );
  }

  @override
  String toString() {
    return 'InventoryMovementLineCompact(name: $productName, sku: $sku, qty: $quantityChanged)';
  }
}

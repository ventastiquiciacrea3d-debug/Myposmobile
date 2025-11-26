// lib/services/inventory_converter_service.dart
import 'dart:convert';
import '../models/inventory_movement.dart';
import '../models/inventory_movement_compact.dart';

/// Servicio para convertir entre InventoryMovement (legacy Hive) y InventoryMovementCompact (ObjectBox)
class InventoryConverterService {
  /// Convertir InventoryMovement (Hive) a InventoryMovementCompact (ObjectBox)
  InventoryMovementCompact movementToCompact(InventoryMovement movement) {
    // Convertir line items a JSON comprimido
    final List<Map<String, dynamic>> itemsJsonList = movement.items.map((item) {
      return InventoryMovementLineCompact(
        productId: int.tryParse(item.productId) ?? 0,
        variationId: item.variationId != null ? int.tryParse(item.variationId!) : null,
        productName: _truncate(item.productName, 50),
        sku: _truncate(item.sku, 20),
        quantityChanged: item.quantityChanged,
        stockBefore: item.stockBefore,
        stockAfter: item.stockAfter,
      ).toJson();
    }).toList();

    final String itemsJson = json.encode(itemsJsonList);

    // Parse user ID
    final int? userId = movement.userId != null ? int.tryParse(movement.userId!) : null;

    // Parse movement type from enum
    final int movementTypeCode = InventoryMovementCompact.parseMovementType(movement.type.toString().split('.').last);

    // Flags
    int flags = 0;
    if (movement.isSynced) flags |= 0x01;

    return InventoryMovementCompact(
      movementId: movement.id,
      userId: userId,
      description: _truncate(movement.description, 100),
      userName: 'Sistema', // No disponible en InventoryMovement original
      itemsJson: itemsJson,
      date: movement.date,
      movementTypeCode: movementTypeCode,
      flags: flags,
    );
  }

  /// Convertir InventoryMovementCompact (ObjectBox) a InventoryMovement (Hive)
  InventoryMovement compactToMovement(InventoryMovementCompact compact) {
    // Convertir items de JSON
    final List<InventoryMovementLine> items = compact.items.map((compactItem) {
      return InventoryMovementLine(
        productId: compactItem.productId.toString(),
        variationId: compactItem.variationId?.toString(),
        productName: compactItem.productName,
        sku: compactItem.sku,
        quantityChanged: compactItem.quantityChanged,
        stockBefore: compactItem.stockBefore,
        stockAfter: compactItem.stockAfter,
      );
    }).toList();

    // Parse movement type string to enum
    final InventoryMovementType type = _parseMovementTypeToEnum(compact.movementType);

    return InventoryMovement(
      id: compact.movementId,
      date: compact.date,
      type: type,
      description: compact.description,
      items: items,
      userId: compact.userId?.toString(),
      isSynced: compact.isSynced,
    );
  }

  static InventoryMovementType _parseMovementTypeToEnum(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'manualadjustment':
        return InventoryMovementType.manualAdjustment;
      case 'initialstock':
        return InventoryMovementType.initialStock;
      case 'sale':
        return InventoryMovementType.sale;
      case 'refund':
        return InventoryMovementType.refund;
      case 'stockreceipt':
        return InventoryMovementType.stockReceipt;
      case 'stockcorrection':
        return InventoryMovementType.stockCorrection;
      case 'damageorloss':
        return InventoryMovementType.damageOrLoss;
      case 'transferout':
        return InventoryMovementType.transferOut;
      case 'transferin':
        return InventoryMovementType.transferIn;
      case 'massentry':
        return InventoryMovementType.massEntry;
      case 'massexit':
        return InventoryMovementType.massExit;
      case 'massmanualadjustment':
        return InventoryMovementType.massManualAdjustment;
      case 'supplierreceipt':
        return InventoryMovementType.supplierReceipt;
      case 'customerreturnmass':
        return InventoryMovementType.customerReturnMass;
      case 'totrash':
        return InventoryMovementType.toTrash;
      default:
        return InventoryMovementType.unknown;
    }
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength);
  }
}

// lib/models/inventory_movement_extensions.dart
import 'inventory_movement.dart'; // Asegúrate que InventoryMovementType esté aquí

extension InventoryMovementTypeDisplayExtension on InventoryMovementType {
  String get displayName {
    switch (this) {
      case InventoryMovementType.manualAdjustment:
        return "Ajuste Manual";
      case InventoryMovementType.initialStock:
        return "Stock Inicial";
      case InventoryMovementType.sale:
        return "Venta";
      case InventoryMovementType.refund:
        return "Devolución";
      case InventoryMovementType.stockReceipt:
        return "Recepción de Stock";
      case InventoryMovementType.stockCorrection:
        return "Corrección de Stock";
      case InventoryMovementType.damageOrLoss:
        return "Daño o Pérdida";
      case InventoryMovementType.transferOut:
        return "Transferencia (Salida)";
      case InventoryMovementType.transferIn:
        return "Transferencia (Entrada)";
      case InventoryMovementType.massEntry:
        return "Entrada por Lote";
      case InventoryMovementType.massExit:
        return "Salida por Lote";
      case InventoryMovementType.massManualAdjustment:
        return "Ajuste Manual Masivo";
      case InventoryMovementType.supplierReceipt:
        return "Recepción de Proveedor";
      case InventoryMovementType.customerReturnMass:
        return "Devolución Masiva Clientes";
      case InventoryMovementType.toTrash:
        return "Envío a Papelera";
      case InventoryMovementType.unknown:
      default:
        return "Desconocido";
    }
  }
}

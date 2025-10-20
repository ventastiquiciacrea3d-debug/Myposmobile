// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_movement.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryMovementLineAdapter extends TypeAdapter<InventoryMovementLine> {
  @override
  final int typeId = 5;

  @override
  InventoryMovementLine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryMovementLine(
      productId: fields[0] as String,
      variationId: fields[1] as String?,
      productName: fields[2] as String,
      sku: fields[3] as String,
      quantityChanged: fields[4] as int,
      stockBefore: fields[5] as int?,
      stockAfter: fields[6] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryMovementLine obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.variationId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.sku)
      ..writeByte(4)
      ..write(obj.quantityChanged)
      ..writeByte(5)
      ..write(obj.stockBefore)
      ..writeByte(6)
      ..write(obj.stockAfter);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementLineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InventoryMovementAdapter extends TypeAdapter<InventoryMovement> {
  @override
  final int typeId = 6;

  @override
  InventoryMovement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryMovement(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      type: fields[2] as InventoryMovementType,
      description: fields[3] as String,
      items: (fields[4] as List).cast<InventoryMovementLine>(),
      referenceId: fields[5] as String?,
      userId: fields[6] as String?,
      isSynced: fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryMovement obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.items)
      ..writeByte(5)
      ..write(obj.referenceId)
      ..writeByte(6)
      ..write(obj.userId)
      ..writeByte(7)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InventoryMovementTypeAdapter extends TypeAdapter<InventoryMovementType> {
  @override
  final int typeId = 4;

  @override
  InventoryMovementType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return InventoryMovementType.manualAdjustment;
      case 1:
        return InventoryMovementType.initialStock;
      case 2:
        return InventoryMovementType.sale;
      case 3:
        return InventoryMovementType.refund;
      case 4:
        return InventoryMovementType.stockReceipt;
      case 5:
        return InventoryMovementType.stockCorrection;
      case 6:
        return InventoryMovementType.damageOrLoss;
      case 7:
        return InventoryMovementType.transferOut;
      case 8:
        return InventoryMovementType.transferIn;
      case 9:
        return InventoryMovementType.massEntry;
      case 10:
        return InventoryMovementType.massExit;
      case 11:
        return InventoryMovementType.massManualAdjustment;
      case 12:
        return InventoryMovementType.supplierReceipt;
      case 13:
        return InventoryMovementType.customerReturnMass;
      case 14:
        return InventoryMovementType.toTrash;
      case 15:
        return InventoryMovementType.unknown;
      default:
        return InventoryMovementType.manualAdjustment;
    }
  }

  @override
  void write(BinaryWriter writer, InventoryMovementType obj) {
    switch (obj) {
      case InventoryMovementType.manualAdjustment:
        writer.writeByte(0);
        break;
      case InventoryMovementType.initialStock:
        writer.writeByte(1);
        break;
      case InventoryMovementType.sale:
        writer.writeByte(2);
        break;
      case InventoryMovementType.refund:
        writer.writeByte(3);
        break;
      case InventoryMovementType.stockReceipt:
        writer.writeByte(4);
        break;
      case InventoryMovementType.stockCorrection:
        writer.writeByte(5);
        break;
      case InventoryMovementType.damageOrLoss:
        writer.writeByte(6);
        break;
      case InventoryMovementType.transferOut:
        writer.writeByte(7);
        break;
      case InventoryMovementType.transferIn:
        writer.writeByte(8);
        break;
      case InventoryMovementType.massEntry:
        writer.writeByte(9);
        break;
      case InventoryMovementType.massExit:
        writer.writeByte(10);
        break;
      case InventoryMovementType.massManualAdjustment:
        writer.writeByte(11);
        break;
      case InventoryMovementType.supplierReceipt:
        writer.writeByte(12);
        break;
      case InventoryMovementType.customerReturnMass:
        writer.writeByte(13);
        break;
      case InventoryMovementType.toTrash:
        writer.writeByte(14);
        break;
      case InventoryMovementType.unknown:
        writer.writeByte(15);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

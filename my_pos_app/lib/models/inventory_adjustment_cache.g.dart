// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_adjustment_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryAdjustmentCacheAdapter
    extends TypeAdapter<InventoryAdjustmentCache> {
  @override
  final int typeId = 8;

  @override
  InventoryAdjustmentCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryAdjustmentCache(
      description: fields[0] as String,
      items: (fields[1] as List).cast<InventoryMovementLine>(),
      lastModified: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryAdjustmentCache obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.description)
      ..writeByte(1)
      ..write(obj.items)
      ..writeByte(2)
      ..write(obj.lastModified);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryAdjustmentCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

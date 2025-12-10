// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderItemAdapter extends TypeAdapter<OrderItem> {
  @override
  final int typeId = 13;

  @override
  OrderItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderItem(
      productId: fields[0] as String,
      variationId: fields[1] as String?,
      productName: fields[2] as String,
      sku: fields[3] as String,
      quantity: fields[4] as int,
      price: fields[5] as double,
      discount: fields[6] as double,
      discountType: fields[7] as String,
      subtotal: fields[8] as double,
      attributes: (fields[9] as Map).cast<String, String>(),
      availableAttributes: (fields[10] as Map?)?.cast<String, dynamic>(),
      availableVariations: (fields[11] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
    );
  }

  @override
  void write(BinaryWriter writer, OrderItem obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.variationId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.sku)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.price)
      ..writeByte(6)
      ..write(obj.discount)
      ..writeByte(7)
      ..write(obj.discountType)
      ..writeByte(8)
      ..write(obj.subtotal)
      ..writeByte(9)
      ..write(obj.attributes)
      ..writeByte(10)
      ..write(obj.availableAttributes)
      ..writeByte(11)
      ..write(obj.availableVariations);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

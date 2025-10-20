// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderAdapter extends TypeAdapter<Order> {
  @override
  final int typeId = 1;

  @override
  Order read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Order(
      items: (fields[4] as List).cast<OrderItem>(),
      subtotal: fields[5] as double,
      tax: fields[6] as double,
      discount: fields[7] as double,
      total: fields[8] as double,
      date: fields[9] as DateTime,
      orderStatus: fields[10] as String,
      isSynced: fields[11] as bool,
      id: fields[0] as String?,
      number: fields[1] as String?,
      customerId: fields[2] as String?,
      customerName: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Order obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.number)
      ..writeByte(2)
      ..write(obj.customerId)
      ..writeByte(3)
      ..write(obj.customerName)
      ..writeByte(4)
      ..write(obj.items)
      ..writeByte(5)
      ..write(obj.subtotal)
      ..writeByte(6)
      ..write(obj.tax)
      ..writeByte(7)
      ..write(obj.discount)
      ..writeByte(8)
      ..write(obj.total)
      ..writeByte(9)
      ..write(obj.date)
      ..writeByte(10)
      ..write(obj.orderStatus)
      ..writeByte(11)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OrderItemAdapter extends TypeAdapter<OrderItem> {
  @override
  final int typeId = 2;

  @override
  OrderItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderItem(
      productId: fields[0] as String,
      name: fields[1] as String,
      sku: fields[2] as String,
      quantity: fields[3] as int,
      price: fields[4] as double,
      subtotal: fields[5] as double,
      variationId: fields[6] as int?,
      attributes: (fields[7] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, String>())
          ?.toList(),
      individualDiscount: fields[8] as double?,
      regularPrice: fields[9] as double?,
      lineItemId: fields[10] as int?,
      productType: fields[11] as String,
    );
  }

  @override
  void write(BinaryWriter writer, OrderItem obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.sku)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.price)
      ..writeByte(5)
      ..write(obj.subtotal)
      ..writeByte(6)
      ..write(obj.variationId)
      ..writeByte(7)
      ..write(obj.attributes)
      ..writeByte(8)
      ..write(obj.individualDiscount)
      ..writeByte(9)
      ..write(obj.regularPrice)
      ..writeByte(10)
      ..write(obj.lineItemId)
      ..writeByte(11)
      ..write(obj.productType);
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

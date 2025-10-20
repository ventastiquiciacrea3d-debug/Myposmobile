// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      name: fields[1] as String,
      sku: fields[2] as String,
      type: fields[3] as String,
      price: fields[4] as double,
      thumbnailUrl: fields[5] as String?,
      parentId: fields[6] as int?,
      barcode: fields[7] as String?,
      regularPrice: fields[8] as double?,
      salePrice: fields[9] as double?,
      onSale: fields[10] as bool,
      manageStock: fields[11] as bool,
      stockQuantity: fields[12] as int?,
      stockStatus: fields[13] as String?,
      categoryNames: (fields[14] as List?)?.cast<String>(),
      attributes: (fields[15] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
      fullAttributesWithOptions: (fields[16] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
      imageUrls: (fields[17] as List).cast<String>(),
      dateModified: fields[18] as DateTime?,
      description: fields[19] as String?,
      shortDescription: fields[20] as String?,
      variations: (fields[21] as List?)?.cast<int>(),
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.sku)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.price)
      ..writeByte(5)
      ..write(obj.thumbnailUrl)
      ..writeByte(6)
      ..write(obj.parentId)
      ..writeByte(7)
      ..write(obj.barcode)
      ..writeByte(8)
      ..write(obj.regularPrice)
      ..writeByte(9)
      ..write(obj.salePrice)
      ..writeByte(10)
      ..write(obj.onSale)
      ..writeByte(11)
      ..write(obj.manageStock)
      ..writeByte(12)
      ..write(obj.stockQuantity)
      ..writeByte(13)
      ..write(obj.stockStatus)
      ..writeByte(14)
      ..write(obj.categoryNames)
      ..writeByte(15)
      ..write(obj.attributes)
      ..writeByte(16)
      ..write(obj.fullAttributesWithOptions)
      ..writeByte(17)
      ..write(obj.imageUrls)
      ..writeByte(18)
      ..write(obj.dateModified)
      ..writeByte(19)
      ..write(obj.description)
      ..writeByte(20)
      ..write(obj.shortDescription)
      ..writeByte(21)
      ..write(obj.variations);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

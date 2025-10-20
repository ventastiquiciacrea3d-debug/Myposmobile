// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'label_print_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LabelPrintItemAdapter extends TypeAdapter<LabelPrintItem> {
  @override
  final int typeId = 7;

  @override
  LabelPrintItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LabelPrintItem(
      id: fields[0] as String?,
      productId: fields[1] as String,
      resolvedVariantId: fields[2] as String?,
      quantity: fields[3] as int,
      selectedVariants: (fields[4] as Map).cast<String, String>(),
      barcode: fields[5] as String?,
      lotNumber: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LabelPrintItem obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.resolvedVariantId)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.selectedVariants)
      ..writeByte(5)
      ..write(obj.barcode)
      ..writeByte(6)
      ..write(obj.lotNumber);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabelPrintItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

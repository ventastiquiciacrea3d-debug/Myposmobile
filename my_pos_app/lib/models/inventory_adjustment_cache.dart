// lib/models/inventory_adjustment_cache.dart
import 'package:hive/hive.dart';
import 'inventory_movement.dart';

part 'inventory_adjustment_cache.g.dart';

@HiveType(typeId: 8)
class InventoryAdjustmentCache extends HiveObject {
  @HiveField(0)
  final String description;

  @HiveField(1)
  final List<InventoryMovementLine> items;

  @HiveField(2)
  final DateTime lastModified;

  InventoryAdjustmentCache({
    required this.description,
    required this.items,
    required this.lastModified,
  });
}
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

  /// ✅ JSON serialization for SharedPreferences migration
  factory InventoryAdjustmentCache.fromJson(Map<String, dynamic> json) {
    return InventoryAdjustmentCache(
      description: json['description'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => InventoryMovementLine.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
      lastModified: DateTime.tryParse(json['lastModified'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'items': items.map((item) => item.toJson()).toList(),
    'lastModified': lastModified.toIso8601String(),
  };
}
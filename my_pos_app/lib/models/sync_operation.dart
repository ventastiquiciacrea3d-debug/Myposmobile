// lib/models/sync_operation.dart
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'sync_operation.g.dart';

@HiveType(typeId: 9)
enum SyncOperationType {
  @HiveField(0)
  createOrder,
  @HiveField(1)
  updateOrderStatus,
  @HiveField(2)
  inventoryAdjustment,
}

@HiveType(typeId: 10)
class SyncOperation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final SyncOperationType type;

  @HiveField(2)
  final Map<String, dynamic> data;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  int retryCount;

  SyncOperation({
    required this.type,
    required this.data,
  }) : id = const Uuid().v4(),
        timestamp = DateTime.now(),
        retryCount = 0;
}
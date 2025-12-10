// lib/models/customer.dart
import 'package:hive/hive.dart';

part 'customer.g.dart';

@HiveType(typeId: 12)
class Customer extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String email;

  @HiveField(2)
  final String firstName;

  @HiveField(3)
  final String lastName;

  @HiveField(4)
  final String? phone;

  @HiveField(5)
  final Map<String, dynamic>? billing;

  @HiveField(6)
  final Map<String, dynamic>? shipping;

  Customer({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.billing,
    this.shipping,
  });

  String get name => '$firstName $lastName'.trim();

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] ?? 0,
    email: json['email'] ?? '',
    firstName: json['first_name'] ?? '',
    lastName: json['last_name'] ?? '',
    phone: json['phone'],
    billing: json['billing'] != null ? Map<String, dynamic>.from(json['billing']) : null,
    shipping: json['shipping'] != null ? Map<String, dynamic>.from(json['shipping']) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'phone': phone,
    'billing': billing,
    'shipping': shipping,
  };
}

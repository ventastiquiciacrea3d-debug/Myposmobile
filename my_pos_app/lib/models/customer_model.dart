// lib/models/customer_model.dart
/// Modelo mejorado de cliente con soporte para WooCommerce, SQLite y Contactos
class CustomerModel {
  final int? id; // ID de WooCommerce (null si es local)
  final String? localId; // ID local UUID
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? company;
  final String? address;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  final CustomerSource source; // De dónde viene el cliente
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isSyncedWithWoo; // Si está sincronizado con WooCommerce
  final Map<String, dynamic>? metadata; // Datos adicionales

  CustomerModel({
    this.id,
    this.localId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.company,
    this.address,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.source = CustomerSource.manual,
    this.createdAt,
    this.updatedAt,
    this.isSyncedWithWoo = false,
    this.metadata,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (email.isNotEmpty) return email;
    if (company != null && company!.isNotEmpty) return company!;
    return 'Cliente sin nombre';
  }

  String get fullAddress {
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (state != null && state!.isNotEmpty) parts.add(state!);
    if (postcode != null && postcode!.isNotEmpty) parts.add(postcode!);
    if (country != null && country!.isNotEmpty) parts.add(country!);
    return parts.join(', ');
  }

  /// Crear desde respuesta de WooCommerce
  factory CustomerModel.fromWooCommerce(Map<String, dynamic> json) {
    final billing = json['billing'] as Map<String, dynamic>?;

    return CustomerModel(
      id: json['id'] as int?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: billing?['phone'] as String?,
      company: billing?['company'] as String?,
      address: billing?['address_1'] as String?,
      city: billing?['city'] as String?,
      state: billing?['state'] as String?,
      postcode: billing?['postcode'] as String?,
      country: billing?['country'] as String?,
      source: CustomerSource.woocommerce,
      createdAt: json['date_created'] != null
          ? DateTime.tryParse(json['date_created'] as String)
          : null,
      updatedAt: json['date_modified'] != null
          ? DateTime.tryParse(json['date_modified'] as String)
          : null,
      isSyncedWithWoo: true,
      metadata: json['meta_data'] as Map<String, dynamic>?,
    );
  }

  /// Crear desde base de datos SQLite
  factory CustomerModel.fromSQLite(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'] as int?,
      localId: map['local_id'] as String?,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String?,
      company: map['company'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      state: map['state'] as String?,
      postcode: map['postcode'] as String?,
      country: map['country'] as String?,
      source: CustomerSource.values.firstWhere(
        (e) => e.toString() == map['source'],
        orElse: () => CustomerSource.manual,
      ),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      isSyncedWithWoo: (map['is_synced_with_woo'] as int?) == 1,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
    );
  }

  /// Crear desde contacto del dispositivo
  factory CustomerModel.fromContact({
    required String displayName,
    String? phone,
    String? email,
  }) {
    final nameParts = displayName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    return CustomerModel(
      firstName: firstName,
      lastName: lastName,
      email: email ?? '',
      phone: phone,
      source: CustomerSource.deviceContacts,
      createdAt: DateTime.now(),
      isSyncedWithWoo: false,
    );
  }

  /// Convertir a Map para SQLite
  Map<String, dynamic> toSQLiteMap() {
    return {
      'id': id,
      'local_id': localId,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'company': company,
      'address': address,
      'city': city,
      'state': state,
      'postcode': postcode,
      'country': country,
      'source': source.toString(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_synced_with_woo': isSyncedWithWoo ? 1 : 0,
      'metadata': metadata,
    };
  }

  /// Convertir a formato WooCommerce para crear/actualizar
  Map<String, dynamic> toWooCommerceJson() {
    return {
      if (id != null) 'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'billing': {
        if (phone != null) 'phone': phone,
        if (company != null) 'company': company,
        if (address != null) 'address_1': address,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (postcode != null) 'postcode': postcode,
        if (country != null) 'country': country,
      },
    };
  }

  /// Crear copia con modificaciones
  CustomerModel copyWith({
    int? id,
    String? localId,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? company,
    String? address,
    String? city,
    String? state,
    String? postcode,
    String? country,
    CustomerSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSyncedWithWoo,
    Map<String, dynamic>? metadata,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      postcode: postcode ?? this.postcode,
      country: country ?? this.country,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSyncedWithWoo: isSyncedWithWoo ?? this.isSyncedWithWoo,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() => 'CustomerModel(id: $id, name: $fullName, email: $email)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerModel &&
        other.id == id &&
        other.localId == localId &&
        other.email == email;
  }

  @override
  int get hashCode => Object.hash(id, localId, email);
}

/// Origen del cliente
enum CustomerSource {
  woocommerce,      // Descargado de WooCommerce
  manual,           // Creado manualmente en la app
  deviceContacts,   // Importado desde contactos del dispositivo
  imported,         // Importado de archivo (CSV, etc.)
}

extension CustomerSourceExtension on CustomerSource {
  String get displayName {
    switch (this) {
      case CustomerSource.woocommerce:
        return 'WooCommerce';
      case CustomerSource.manual:
        return 'Manual';
      case CustomerSource.deviceContacts:
        return 'Contactos';
      case CustomerSource.imported:
        return 'Importado';
    }
  }

  String get icon {
    switch (this) {
      case CustomerSource.woocommerce:
        return '🛒';
      case CustomerSource.manual:
        return '✏️';
      case CustomerSource.deviceContacts:
        return '📱';
      case CustomerSource.imported:
        return '📂';
    }
  }
}

// lib/utils/special_price_storage.dart
import 'package:flutter/foundation.dart';

/// Almacenamiento Inteligente de Precios Especiales
///
/// Solo guarda precios especiales ACTIVOS, ahorrando espacio.
///
/// Codificación:
/// - 24 bits para precio (hasta $167,772.15)
/// - 8 bits para días restantes (hasta 255 días)
/// Total: 32 bits (4 bytes)
///
/// Ejemplo:
/// - Precio: $29.99, válido por 30 días
/// - Centavos: 2999
/// - Codificado: (2999 << 8) | 30 = 767774
class SpecialPriceStorage {
  /// Codificar precio especial + fecha de expiración
  ///
  /// Retorna 0 si:
  /// - No hay precio especial (null)
  /// - Ya expiró
  /// - validUntil es null
  static int encodePrice(double price, DateTime? validUntil) {
    // Sin precio especial o ya expiró
    if (validUntil == null || validUntil.isBefore(DateTime.now())) {
      return 0;
    }

    // Convertir precio a centavos
    final priceCents = (price * 100).round();

    // Validar rango (máx 24 bits = 16,777,215 centavos = $167,772.15)
    if (priceCents > 0xFFFFFF) {
      debugPrint('[SpecialPrice] ⚠️ Price too large: \$${price.toStringAsFixed(2)} (max: \$167,772.15)');
      return 0;
    }

    // Calcular días restantes
    final daysRemaining = validUntil.difference(DateTime.now()).inDays;

    // Validar rango (máx 8 bits = 255 días)
    if (daysRemaining > 255) {
      debugPrint('[SpecialPrice] ⚠️ Too many days: $daysRemaining (max: 255). Using 255.');
      return (priceCents << 8) | 0xFF;
    }

    if (daysRemaining < 0) {
      return 0; // Ya expiró
    }

    // Codificar: 24 bits precio + 8 bits días
    final encoded = (priceCents << 8) | (daysRemaining & 0xFF);

    debugPrint('[SpecialPrice] Encoded: \$${price.toStringAsFixed(2)} valid for $daysRemaining days → $encoded');

    return encoded;
  }

  /// Decodificar precio especial
  ///
  /// Retorna null si el valor es 0 o ha expirado
  static DecodedSpecialPrice? decodePrice(int encoded) {
    if (encoded == 0) {
      return null;
    }

    // Extraer precio (24 bits superiores)
    final priceCents = (encoded >> 8) & 0xFFFFFF;
    final price = priceCents / 100.0;

    // Extraer días restantes (8 bits inferiores)
    final daysRemaining = encoded & 0xFF;

    // Calcular fecha de expiración
    final validUntil = DateTime.now().add(Duration(days: daysRemaining));

    // Verificar si ya expiró
    if (daysRemaining == 0 || validUntil.isBefore(DateTime.now())) {
      return null;
    }

    return DecodedSpecialPrice(
      price: price,
      validUntil: validUntil,
      daysRemaining: daysRemaining,
    );
  }

  /// Verificar si precio especial sigue activo
  static bool isActive(int encoded) {
    if (encoded == 0) return false;

    final daysRemaining = encoded & 0xFF;
    return daysRemaining > 0;
  }

  /// Obtener precio en formato decimal (sin validar expiración)
  static double? getPrice(int encoded) {
    if (encoded == 0) return null;

    final priceCents = (encoded >> 8) & 0xFFFFFF;
    return priceCents / 100.0;
  }

  /// Obtener días restantes (sin validar expiración)
  static int? getDaysRemaining(int encoded) {
    if (encoded == 0) return null;
    return encoded & 0xFF;
  }

  /// Actualizar días restantes de un precio ya codificado
  static int updateDaysRemaining(int encoded, int newDaysRemaining) {
    if (encoded == 0) return 0;
    if (newDaysRemaining < 0 || newDaysRemaining > 255) return 0;

    final priceCents = (encoded >> 8) & 0xFFFFFF;
    return (priceCents << 8) | (newDaysRemaining & 0xFF);
  }

  /// Renovar precio especial por X días más
  static int extendPrice(int encoded, int additionalDays) {
    if (encoded == 0) return 0;

    final currentDays = encoded & 0xFF;
    final newDays = (currentDays + additionalDays).clamp(0, 255);

    final priceCents = (encoded >> 8) & 0xFFFFFF;
    return (priceCents << 8) | (newDays & 0xFF);
  }

  /// Calcular ahorro con precio especial
  static double? calculateSavings(double regularPrice, int encodedSpecialPrice) {
    final decoded = decodePrice(encodedSpecialPrice);
    if (decoded == null) return null;

    final savings = regularPrice - decoded.price;
    return savings > 0 ? savings : null;
  }

  /// Calcular porcentaje de descuento
  static double? calculateDiscountPercentage(double regularPrice, int encodedSpecialPrice) {
    final savings = calculateSavings(regularPrice, encodedSpecialPrice);
    if (savings == null || savings <= 0 || regularPrice <= 0) return null;

    return (savings / regularPrice) * 100;
  }

  /// Convertir a formato legible para debugging
  static String debugFormat(int encoded) {
    if (encoded == 0) return 'No special price';

    final decoded = decodePrice(encoded);
    if (decoded == null) return 'Expired special price';

    return '\$${decoded.price.toStringAsFixed(2)} (${decoded.daysRemaining} days left)';
  }
}

/// Precio especial decodificado
class DecodedSpecialPrice {
  final double price;
  final DateTime validUntil;
  final int daysRemaining;

  DecodedSpecialPrice({
    required this.price,
    required this.validUntil,
    required this.daysRemaining,
  });

  bool get isExpired => DateTime.now().isAfter(validUntil);
  bool get isActive => !isExpired && daysRemaining > 0;

  @override
  String toString() {
    return 'SpecialPrice(\$${price.toStringAsFixed(2)}, ${daysRemaining}d left)';
  }
}

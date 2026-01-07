// lib/utils/string_helpers.dart

/// Utilidades para manipulación de cadenas de texto
library string_helpers;

/// Trunca un nombre si excede el límite de caracteres
///
/// Ejemplo:
/// ```dart
/// truncateName('Juan Carlos Pérez', maxLength: 10)
/// // Retorna: 'Juan Ca...'
/// ```
String truncateName(String? name, {int maxLength = 20}) {
  if (name == null || name.isEmpty) return 'Cliente General';
  if (name.length <= maxLength) return name;
  return '${name.substring(0, maxLength - 3)}...';
}

/// Obtiene un nombre corto para mostrar en UI
///
/// Estrategias:
/// - 1 palabra: truncar si es necesario
/// - 2+ palabras: Primera inicial + Apellido (ej: "J. Pérez")
/// - Si aún es largo: truncar
///
/// Ejemplos:
/// ```dart
/// getDisplayName('Juan')                        // 'Juan'
/// getDisplayName('Juan Pérez')                  // 'J. Pérez'
/// getDisplayName('Juan Carlos Pérez García')    // 'J. Pérez'
/// getDisplayName('Supercalifragilisticoespialidoso') // 'Supercalifra...'
/// ```
String getDisplayName(String? fullName, {int maxLength = 18}) {
  if (fullName == null || fullName.isEmpty) return 'Cliente General';

  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'Cliente General';

  final parts = trimmed.split(' ');

  // Si es una sola palabra, truncar directamente
  if (parts.length == 1) {
    return truncateName(parts[0], maxLength: maxLength);
  }

  // Si hay 2+ palabras, mostrar primera inicial + apellido
  // "Juan Carlos Pérez García" → "J. Pérez"
  final firstName = parts[0];
  final lastName = parts.length > 1 ? parts[1] : '';

  // Verificar que firstName tenga al menos un carácter
  if (firstName.isEmpty) {
    return truncateName(trimmed, maxLength: maxLength);
  }

  final shortName = '${firstName[0]}. $lastName'.trim();

  // Si el nombre corto aún excede el límite, truncar
  if (shortName.length <= maxLength) return shortName;
  return truncateName(shortName, maxLength: maxLength);
}

/// Obtiene iniciales de un nombre completo
///
/// Ejemplos:
/// ```dart
/// getInitials('Juan Pérez')                  // 'JP'
/// getInitials('María José García López')     // 'MG'
/// getInitials('Ana')                         // 'A'
/// ```
String getInitials(String? fullName, {int maxInitials = 2}) {
  if (fullName == null || fullName.isEmpty) return 'CG'; // Cliente General

  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'CG';

  final parts = trimmed.split(' ').where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) return 'CG';
  if (parts.length == 1) return parts[0][0].toUpperCase();

  // Tomar primera letra de cada palabra, hasta maxInitials
  final initials = parts
      .take(maxInitials)
      .map((word) => word[0].toUpperCase())
      .join();

  return initials;
}

/// Capitaliza la primera letra de cada palabra
///
/// Ejemplo:
/// ```dart
/// capitalize('juan pérez')  // 'Juan Pérez'
/// ```
String capitalize(String? text) {
  if (text == null || text.isEmpty) return '';

  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

/// Formatea un número de teléfono para mostrar
///
/// Ejemplos:
/// ```dart
/// formatPhone('88887777')       // '8888-7777'
/// formatPhone('50688887777')    // '+506 8888-7777'
/// formatPhone('12345')          // '12345' (sin formato)
/// ```
String formatPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';

  // Remover espacios y caracteres especiales
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');

  // Formato Costa Rica: +506 8888-7777
  if (cleaned.startsWith('+506') && cleaned.length == 11) {
    return '${cleaned.substring(0, 4)} ${cleaned.substring(4, 8)}-${cleaned.substring(8)}';
  }

  // Formato local: 8888-7777
  if (cleaned.length == 8) {
    return '${cleaned.substring(0, 4)}-${cleaned.substring(4)}';
  }

  // Si no coincide con formatos conocidos, retornar limpio
  return cleaned;
}

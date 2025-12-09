// lib/services/label_settings_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LabelSettingsService {
  static const String _settingsKey = 'label_settings';

  // Estructura de settings guardados (debe coincidir con label_settings_screen.dart)
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_settingsKey);

    if (settingsJson != null) {
      return json.decode(settingsJson);
    }

    // Settings por defecto si no hay guardados
    return getDefaultSettings();
  }

  static Map<String, dynamic> getDefaultSettings() {
    return {
      // Dimensiones de etiqueta
      'labelWidth': 50,  // mm
      'labelHeight': 30, // mm

      // Configuración de impresión
      'printDensity': 12,
      'printSpeed': 4,
      'printDirection': 0,
      'printCopies': 1,

      // Campos visibles
      'showProductName': true,
      'showVariants': true,
      'showQuantity': true,
      'showDate': true,
      'showBrand': true,
      'showSku': true,
      'showBarcode': true,
      'showLot': false,

      // Configuración por campo
      'fields': {
        'productName': {
          'enabled': true,
          'fontSize': 3,      // TSPL font size (1-9)
          'fontBold': true,
          'xPosition': 10,    // dots
          'yPosition': 10,    // dots
          'alignment': 'left',
          'maxWidth': 380,    // dots
        },
        'variants': {
          'enabled': true,
          'fontSize': 2,
          'fontBold': false,
          'xPosition': 10,
          'yPosition': 50,
          'alignment': 'left',
          'prefix': '',
          'separator': ' / ',
        },
        'quantity': {
          'enabled': true,
          'fontSize': 2,
          'fontBold': true,
          'xPosition': 10,
          'yPosition': 80,
          'alignment': 'left',
          'prefix': 'Cant: ',
        },
        'date': {
          'enabled': true,
          'fontSize': 1,
          'fontBold': false,
          'xPosition': 250,
          'yPosition': 80,
          'alignment': 'right',
          'format': 'dd/MM/yy',
        },
        'brand': {
          'enabled': true,
          'fontSize': 2,
          'fontBold': false,
          'xPosition': 10,
          'yPosition': 110,
          'alignment': 'left',
        },
        'sku': {
          'enabled': true,
          'fontSize': 2,
          'fontBold': false,
          'xPosition': 10,
          'yPosition': 140,
          'alignment': 'center',
          'prefix': 'SKU: ',
        },
        'barcode': {
          'enabled': true,
          'type': '128',      // Code 128
          'xPosition': 50,
          'yPosition': 170,
          'height': 70,       // dots
          'narrow': 2,        // narrow bar width
          'wide': 5,          // wide bar width
          'showText': true,
          'textSize': 1,
          'alignment': 'center',
        },
        'lot': {
          'enabled': false,
          'fontSize': 1,
          'fontBold': false,
          'xPosition': 10,
          'yPosition': 260,
          'alignment': 'left',
          'prefix': 'Lote: ',
        },
      },
    };
  }

  // Guardar settings
  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, json.encode(settings));
  }

  // Obtener valor específico de un campo
  static dynamic getFieldValue(Map<String, dynamic> settings, String field, String property) {
    if (settings['fields'] != null &&
        settings['fields'][field] != null) {
      return settings['fields'][field][property];
    }
    return null;
  }

  // Verificar si un campo está habilitado
  static bool isFieldEnabled(Map<String, dynamic> settings, String field) {
    return getFieldValue(settings, field, 'enabled') ?? false;
  }
}
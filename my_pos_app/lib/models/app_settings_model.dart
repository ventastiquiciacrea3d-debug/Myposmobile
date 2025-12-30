// lib/models/app_settings_model.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo de configuración de la aplicación
class AppSettingsModel {
  // Configuración de Cotizaciones
  final bool shareQuoteEnabled;
  final QuoteFormat quoteFormat;
  final bool includeLogoInQuote;
  final bool includeProductImages;
  final bool includeTermsAndConditions;

  // Configuración del Escáner
  final bool scannerVibrationEnabled;
  final bool scannerSoundEnabled;
  final bool scannerAutoAddEnabled;
  final int scannerDebounceMs;

  // Configuración de Clientes
  final bool autoLoadCustomersFromWoo;
  final bool allowDeviceContactsSearch;
  final bool autoSaveToDeviceContacts;

  // Configuración de Sincronización
  final bool autoSyncEnabled;
  final int autoSyncIntervalMinutes;

  // Información de Empresa (para cotizaciones)
  final String companyName;
  final String companyPhone;
  final String companyEmail;
  final String companyAddress;

  const AppSettingsModel({
    this.shareQuoteEnabled = true,
    this.quoteFormat = QuoteFormat.both,
    this.includeLogoInQuote = true,
    this.includeProductImages = true,
    this.includeTermsAndConditions = true,
    this.scannerVibrationEnabled = true,
    this.scannerSoundEnabled = true,
    this.scannerAutoAddEnabled = false,
    this.scannerDebounceMs = 1500,
    this.autoLoadCustomersFromWoo = true,
    this.allowDeviceContactsSearch = true,
    this.autoSaveToDeviceContacts = false,
    this.autoSyncEnabled = true,
    this.autoSyncIntervalMinutes = 30,
    this.companyName = '',
    this.companyPhone = '',
    this.companyEmail = '',
    this.companyAddress = '',
  });

  /// Cargar configuración desde SharedPreferences
  static Future<AppSettingsModel> load() async {
    final prefs = await SharedPreferences.getInstance();

    return AppSettingsModel(
      // Cotizaciones
      shareQuoteEnabled: prefs.getBool('share_quote_enabled') ?? true,
      quoteFormat: QuoteFormat.values[prefs.getInt('quote_format') ?? QuoteFormat.both.index],
      includeLogoInQuote: prefs.getBool('include_logo_in_quote') ?? true,
      includeProductImages: prefs.getBool('include_product_images') ?? true,
      includeTermsAndConditions: prefs.getBool('include_terms_and_conditions') ?? true,

      // Escáner
      scannerVibrationEnabled: prefs.getBool('scanner_vibration_enabled') ?? true,
      scannerSoundEnabled: prefs.getBool('scanner_sound_enabled') ?? true,
      scannerAutoAddEnabled: prefs.getBool('scanner_auto_add_enabled') ?? false,
      scannerDebounceMs: prefs.getInt('scanner_debounce_ms') ?? 1500,

      // Clientes
      autoLoadCustomersFromWoo: prefs.getBool('auto_load_customers_from_woo') ?? true,
      allowDeviceContactsSearch: prefs.getBool('allow_device_contacts_search') ?? true,
      autoSaveToDeviceContacts: prefs.getBool('auto_save_to_device_contacts') ?? false,

      // Sincronización
      autoSyncEnabled: prefs.getBool('auto_sync_enabled') ?? true,
      autoSyncIntervalMinutes: prefs.getInt('auto_sync_interval_minutes') ?? 30,

      // Información de empresa
      companyName: prefs.getString('company_name') ?? '',
      companyPhone: prefs.getString('company_phone') ?? '',
      companyEmail: prefs.getString('company_email') ?? '',
      companyAddress: prefs.getString('company_address') ?? '',
    );
  }

  /// Guardar configuración en SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    // Cotizaciones
    await prefs.setBool('share_quote_enabled', shareQuoteEnabled);
    await prefs.setInt('quote_format', quoteFormat.index);
    await prefs.setBool('include_logo_in_quote', includeLogoInQuote);
    await prefs.setBool('include_product_images', includeProductImages);
    await prefs.setBool('include_terms_and_conditions', includeTermsAndConditions);

    // Escáner
    await prefs.setBool('scanner_vibration_enabled', scannerVibrationEnabled);
    await prefs.setBool('scanner_sound_enabled', scannerSoundEnabled);
    await prefs.setBool('scanner_auto_add_enabled', scannerAutoAddEnabled);
    await prefs.setInt('scanner_debounce_ms', scannerDebounceMs);

    // Clientes
    await prefs.setBool('auto_load_customers_from_woo', autoLoadCustomersFromWoo);
    await prefs.setBool('allow_device_contacts_search', allowDeviceContactsSearch);
    await prefs.setBool('auto_save_to_device_contacts', autoSaveToDeviceContacts);

    // Sincronización
    await prefs.setBool('auto_sync_enabled', autoSyncEnabled);
    await prefs.setInt('auto_sync_interval_minutes', autoSyncIntervalMinutes);

    // Información de empresa
    await prefs.setString('company_name', companyName);
    await prefs.setString('company_phone', companyPhone);
    await prefs.setString('company_email', companyEmail);
    await prefs.setString('company_address', companyAddress);
  }

  /// Crear copia con modificaciones
  AppSettingsModel copyWith({
    bool? shareQuoteEnabled,
    QuoteFormat? quoteFormat,
    bool? includeLogoInQuote,
    bool? includeProductImages,
    bool? includeTermsAndConditions,
    bool? scannerVibrationEnabled,
    bool? scannerSoundEnabled,
    bool? scannerAutoAddEnabled,
    int? scannerDebounceMs,
    bool? autoLoadCustomersFromWoo,
    bool? allowDeviceContactsSearch,
    bool? autoSaveToDeviceContacts,
    bool? autoSyncEnabled,
    int? autoSyncIntervalMinutes,
    String? companyName,
    String? companyPhone,
    String? companyEmail,
    String? companyAddress,
  }) {
    return AppSettingsModel(
      shareQuoteEnabled: shareQuoteEnabled ?? this.shareQuoteEnabled,
      quoteFormat: quoteFormat ?? this.quoteFormat,
      includeLogoInQuote: includeLogoInQuote ?? this.includeLogoInQuote,
      includeProductImages: includeProductImages ?? this.includeProductImages,
      includeTermsAndConditions: includeTermsAndConditions ?? this.includeTermsAndConditions,
      scannerVibrationEnabled: scannerVibrationEnabled ?? this.scannerVibrationEnabled,
      scannerSoundEnabled: scannerSoundEnabled ?? this.scannerSoundEnabled,
      scannerAutoAddEnabled: scannerAutoAddEnabled ?? this.scannerAutoAddEnabled,
      scannerDebounceMs: scannerDebounceMs ?? this.scannerDebounceMs,
      autoLoadCustomersFromWoo: autoLoadCustomersFromWoo ?? this.autoLoadCustomersFromWoo,
      allowDeviceContactsSearch: allowDeviceContactsSearch ?? this.allowDeviceContactsSearch,
      autoSaveToDeviceContacts: autoSaveToDeviceContacts ?? this.autoSaveToDeviceContacts,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      autoSyncIntervalMinutes: autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
      companyName: companyName ?? this.companyName,
      companyPhone: companyPhone ?? this.companyPhone,
      companyEmail: companyEmail ?? this.companyEmail,
      companyAddress: companyAddress ?? this.companyAddress,
    );
  }

  /// Restaurar valores por defecto
  static AppSettingsModel defaults() => const AppSettingsModel();
}

/// Formato de cotización
enum QuoteFormat {
  pdf,    // Solo PDF
  text,   // Solo texto
  both,   // PDF + Texto
}

extension QuoteFormatExtension on QuoteFormat {
  String get displayName {
    switch (this) {
      case QuoteFormat.pdf:
        return 'Solo PDF';
      case QuoteFormat.text:
        return 'Solo Texto';
      case QuoteFormat.both:
        return 'PDF + Texto';
    }
  }
}

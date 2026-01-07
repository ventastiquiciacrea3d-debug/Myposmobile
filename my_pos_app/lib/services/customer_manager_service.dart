// lib/services/customer_manager_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/customer_model.dart';
import 'local_database_service.dart';
import 'woocommerce_service.dart';

/// Servicio integrado para gestionar clientes desde múltiples fuentes
class CustomerManagerService extends ChangeNotifier {
  final LocalDatabaseService _localDb;
  final WooCommerceService _wooService;

  // Estado
  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;

  CustomerManagerService({
    required LocalDatabaseService localDb,
    required WooCommerceService wooService,
  })  : _localDb = localDb,
        _wooService = wooService;

  // Getters
  List<CustomerModel> get customers => _customers;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;

  /// Cargar todos los clientes (local + WooCommerce)
  Future<void> loadAllCustomers({bool forceSync = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Cargar desde base de datos local
      final localCustomers = await _localDb.getAllCustomers();

      // 2. Si hace más de 1 hora o forceSync, sincronizar con WooCommerce
      final shouldSync = forceSync ||
          _lastSync == null ||
          DateTime.now().difference(_lastSync!) > const Duration(hours: 1);

      if (shouldSync) {
        try {
          // Obtener clientes desde el endpoint personalizado /mypos/v1/customers
          final wooCustomersRaw = await _wooService.getCustomers(
            perPage: 100,
            orderBy: 'registered_date',
            order: 'desc',
          );

          // Convertir de Map a CustomerModel
          final wooCustomers = wooCustomersRaw
              .map((json) => CustomerModel.fromWooCommerce(json))
              .toList();

          // Sincronizar con base de datos local
          await _localDb.syncCustomersFromWooCommerce(wooCustomers);

          // Recargar desde local después de sincronizar
          _customers = await _localDb.getAllCustomers();
          _lastSync = DateTime.now();

          debugPrint('[CustomerManager] ✅ Sincronizados ${wooCustomers.length} clientes desde WooCommerce');
        } catch (e) {
          debugPrint('[CustomerManager] Error sincronizando con WooCommerce: $e');
          // Si falla WooCommerce, usar datos locales
          _customers = localCustomers;
        }
      } else {
        _customers = localCustomers;
      }

      _error = null;
    } catch (e) {
      _error = 'Error cargando clientes: $e';
      debugPrint('[CustomerManager] $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Buscar clientes (local + WooCommerce)
  Future<List<CustomerModel>> searchCustomers(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      // Buscar en local primero (más rápido)
      final localResults = await _localDb.searchCustomers(query);

      // Si hay suficientes resultados locales, retornarlos
      if (localResults.length >= 10) {
        return localResults;
      }

      // Buscar también en WooCommerce
      try {
        final wooResultsRaw = await _wooService.searchCustomersAPI(query);

        // Convertir de Map a CustomerModel
        final wooResults = wooResultsRaw
            .map((json) => CustomerModel.fromWooCommerce(json))
            .toList();

        // Combinar resultados, evitando duplicados por email
        final combined = <String, CustomerModel>{};

        for (final customer in localResults) {
          combined[customer.email] = customer;
        }

        for (final customer in wooResults) {
          if (!combined.containsKey(customer.email)) {
            combined[customer.email] = customer;
          }
        }

        return combined.values.toList();
      } catch (e) {
        debugPrint('[CustomerManager] Error buscando en WooCommerce: $e');
        return localResults;
      }
    } catch (e) {
      debugPrint('[CustomerManager] Error en búsqueda: $e');
      return [];
    }
  }

  /// Obtener clientes recientes
  Future<List<CustomerModel>> getRecentCustomers({int limit = 10}) async {
    try {
      // 🔧 FIX: SIEMPRE intentar cargar desde WooCommerce primero para obtener datos actualizados
      try {
        debugPrint('[CustomerManager] Cargando últimos $limit clientes desde WooCommerce...');
        final wooCustomersRaw = await _wooService.getRecentCustomers(limit: limit);

        // Convertir de Map a CustomerModel
        final wooCustomers = wooCustomersRaw
            .map((json) => CustomerModel.fromWooCommerce(json))
            .toList();

        // Guardar en base de datos local para futuras consultas
        for (final customer in wooCustomers) {
          await _localDb.saveCustomer(customer);
        }

        debugPrint('[CustomerManager] ✅ Cargados ${wooCustomers.length} clientes desde WooCommerce');
        return wooCustomers;
      } catch (e) {
        // Si falla WooCommerce (sin conexión, etc), usar datos locales como fallback
        debugPrint('[CustomerManager] Error cargando desde WooCommerce: $e. Usando datos locales...');
        final localRecents = await _localDb.getRecentCustomers(limit: limit);

        if (localRecents.isNotEmpty) {
          debugPrint('[CustomerManager] ⚠️ Usando ${localRecents.length} clientes locales (offline)');
          return localRecents;
        }

        debugPrint('[CustomerManager] ❌ No hay clientes disponibles (ni online ni offline)');
        return [];
      }
    } catch (e) {
      debugPrint('[CustomerManager] Error crítico obteniendo recientes: $e');
      return [];
    }
  }

  /// Crear nuevo cliente
  Future<CustomerModel?> createCustomer(CustomerModel customer) async {
    try {
      // Guardar localmente primero
      await _localDb.saveCustomer(customer);

      // Intentar subir a WooCommerce si tiene email válido
      if (customer.email.isNotEmpty && customer.email.contains('@')) {
        try {
          final customerData = customer.toWooCommerceJson();
          final wooCustomerRaw = await _wooService.createCustomer(customerData);

          // Convertir respuesta a CustomerModel
          final wooCustomer = CustomerModel.fromWooCommerce(wooCustomerRaw);

          // Actualizar con ID de WooCommerce
          await _localDb.markCustomerAsSynced(
            customer.id ?? 0,
            wooCustomer.id!,
          );

          // Recargar clientes
          await loadAllCustomers();

          debugPrint('[CustomerManager] ✅ Cliente creado y sincronizado con WooCommerce: ${wooCustomer.email}');
          return wooCustomer;
        } catch (e) {
          debugPrint('[CustomerManager] Error subiendo a WooCommerce: $e');
          // Cliente guardado localmente, pero no sincronizado
          return customer;
        }
      }

      // Recargar clientes
      await loadAllCustomers();
      return customer;
    } catch (e) {
      _error = 'Error creando cliente: $e';
      debugPrint('[CustomerManager] $_error');
      notifyListeners();
      return null;
    }
  }

  /// Actualizar cliente
  Future<bool> updateCustomer(CustomerModel customer) async {
    try {
      // Actualizar localmente
      await _localDb.saveCustomer(customer);

      // TODO: Implementar actualización en WooCommerce cuando el endpoint esté disponible
      if (customer.id != null && customer.isSyncedWithWoo) {
        debugPrint('[CustomerManager] ⚠️ Actualización de clientes solo local (endpoint de WooCommerce no disponible)');
      }

      // Recargar clientes
      await loadAllCustomers();
      return true;
    } catch (e) {
      _error = 'Error actualizando cliente: $e';
      debugPrint('[CustomerManager] $_error');
      notifyListeners();
      return false;
    }
  }

  /// Eliminar cliente
  Future<bool> deleteCustomer(CustomerModel customer) async {
    try {
      // TODO: Implementar eliminación en WooCommerce cuando el endpoint esté disponible
      if (customer.id != null && customer.isSyncedWithWoo) {
        debugPrint('[CustomerManager] ⚠️ Eliminación de clientes solo local (endpoint de WooCommerce no disponible)');
      }

      // Eliminar localmente
      if (customer.id != null) {
        await _localDb.deleteCustomer(customer.id!);
      }

      // Recargar clientes
      await loadAllCustomers();
      return true;
    } catch (e) {
      _error = 'Error eliminando cliente: $e';
      debugPrint('[CustomerManager] $_error');
      notifyListeners();
      return false;
    }
  }

  /// Buscar en contactos del dispositivo
  Future<List<CustomerModel>> searchDeviceContacts(String query) async {
    try {
      // Verificar permiso
      if (!await FlutterContacts.requestPermission()) {
        debugPrint('[CustomerManager] Permiso de contactos denegado');
        return [];
      }

      // Buscar contactos
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      // Filtrar por query
      final filtered = contacts.where((contact) {
        final name = contact.displayName.toLowerCase();
        final q = query.toLowerCase();
        return name.contains(q);
      }).toList();

      // Convertir a CustomerModel
      final customers = <CustomerModel>[];

      for (final contact in filtered.take(20)) {
        final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
        final email = contact.emails.isNotEmpty ? contact.emails.first.address : null;

        customers.add(CustomerModel.fromContact(
          displayName: contact.displayName,
          phone: phone,
          email: email,
        ));
      }

      return customers;
    } catch (e) {
      debugPrint('[CustomerManager] Error buscando contactos: $e');
      return [];
    }
  }

  /// Importar contacto del dispositivo como cliente
  Future<CustomerModel?> importFromDeviceContact(CustomerModel customer) async {
    try {
      debugPrint('[CustomerManager] 📥 Iniciando importación de contacto: ${customer.fullName}');
      debugPrint('[CustomerManager] Email: ${customer.email}, Teléfono: ${customer.phone}');

      // Guardar en base de datos local
      debugPrint('[CustomerManager] Guardando en base de datos local...');
      await _localDb.saveCustomer(customer);
      debugPrint('[CustomerManager] ✅ Guardado en BD local exitoso');

      // Intentar sincronizar con WooCommerce si tiene email
      if (customer.email.isNotEmpty && customer.email.contains('@')) {
        debugPrint('[CustomerManager] Intentando sincronizar con WooCommerce...');
        try {
          final customerData = customer.toWooCommerceJson();
          final wooCustomerRaw = await _wooService.createCustomer(customerData);
          final wooCustomer = CustomerModel.fromWooCommerce(wooCustomerRaw);

          await _localDb.markCustomerAsSynced(
            customer.id ?? 0,
            wooCustomer.id!,
          );

          debugPrint('[CustomerManager] ✅ Contacto importado y sincronizado: ${wooCustomer.email}');
        } catch (e) {
          debugPrint('[CustomerManager] ⚠️ No se pudo sincronizar con WooCommerce: $e');
        }
      } else {
        debugPrint('[CustomerManager] ℹ️ Contacto sin email válido, no se sincroniza con WooCommerce');
      }

      // Recargar
      debugPrint('[CustomerManager] Recargando lista de clientes...');
      await loadAllCustomers();
      debugPrint('[CustomerManager] ✅ Importación de contacto completada exitosamente');
      return customer;
    } catch (e, stackTrace) {
      _error = 'Error importando contacto: $e';
      debugPrint('[CustomerManager] ❌ $_error');
      debugPrint('[CustomerManager] Stack trace: $stackTrace');
      notifyListeners();
      rethrow; // ✅ FIX: Re-lanzar para que el UI pueda mostrar el error
    }
  }

  /// Guardar cliente en contactos del dispositivo
  Future<bool> saveToDeviceContacts(CustomerModel customer) async {
    try {
      // Verificar permiso
      if (!await FlutterContacts.requestPermission()) {
        debugPrint('[CustomerManager] Permiso de contactos denegado');
        return false;
      }

      // Crear contacto
      final contact = Contact()
        ..name = Name(
          first: customer.firstName,
          last: customer.lastName,
        );

      // Agregar email
      if (customer.email.isNotEmpty) {
        contact.emails = [Email(customer.email)];
      }

      // Agregar teléfono
      if (customer.phone != null && customer.phone!.isNotEmpty) {
        contact.phones = [Phone(customer.phone!)];
      }

      // Agregar empresa
      if (customer.company != null && customer.company!.isNotEmpty) {
        contact.organizations = [
          Organization(company: customer.company!),
        ];
      }

      // Agregar dirección
      if (customer.address != null && customer.address!.isNotEmpty) {
        contact.addresses = [
          Address(
            customer.address!,
            label: AddressLabel.work,
            city: customer.city ?? '',
            state: customer.state ?? '',
            postalCode: customer.postcode ?? '',
            country: customer.country ?? '',
          ),
        ];
      }

      // Guardar contacto
      await contact.insert();

      return true;
    } catch (e) {
      debugPrint('[CustomerManager] Error guardando en contactos: $e');
      return false;
    }
  }

  /// Sincronizar clientes no sincronizados con WooCommerce
  Future<int> syncUnsyncedCustomers() async {
    try {
      final unsynced = await _localDb.getUnsyncedCustomers();
      int synced = 0;

      for (final customer in unsynced) {
        try {
          final customerData = customer.toWooCommerceJson();
          final wooCustomerRaw = await _wooService.createCustomer(customerData);
          final wooCustomer = CustomerModel.fromWooCommerce(wooCustomerRaw);

          await _localDb.markCustomerAsSynced(
            customer.id ?? 0,
            wooCustomer.id!,
          );

          synced++;
        } catch (e) {
          debugPrint('[CustomerManager] Error sincronizando cliente ${customer.email}: $e');
        }
      }

      if (synced > 0) {
        await loadAllCustomers();
        debugPrint('[CustomerManager] ✅ Sincronizados $synced clientes no sincronizados');
      }

      return synced;
    } catch (e) {
      debugPrint('[CustomerManager] Error en sincronización masiva: $e');
      return 0;
    }
  }

  /// Limpiar cache de WooCommerce (no aplicable con nuevo servicio)
  void clearWooCommerceCache() {
    // Cache ahora manejado por WooCommerceService
    debugPrint('[CustomerManager] Cache manejado por WooCommerceService');
  }

  /// Obtener estadísticas
  Future<Map<String, int>> getStatistics() async {
    try {
      final total = await _localDb.getCustomerCount();
      final unsynced = await _localDb.getUnsyncedCustomers();

      return {
        'total': total,
        'unsynced': unsynced.length,
        'synced': total - unsynced.length,
      };
    } catch (e) {
      debugPrint('[CustomerManager] Error obteniendo estadísticas: $e');
      return {'total': 0, 'unsynced': 0, 'synced': 0};
    }
  }
}

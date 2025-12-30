// lib/services/customer_manager_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/customer_model.dart';
import 'local_database_service.dart';
import 'woocommerce_customer_service.dart';

/// Servicio integrado para gestionar clientes desde múltiples fuentes
class CustomerManagerService extends ChangeNotifier {
  final LocalDatabaseService _localDb;
  final WooCommerceCustomerService _wooService;

  // Estado
  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;

  CustomerManagerService({
    required LocalDatabaseService localDb,
    required WooCommerceCustomerService wooService,
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
          final wooCustomers = await _wooService.getAllCustomers(
            forceRefresh: true,
          );

          // Sincronizar con base de datos local
          await _localDb.syncCustomersFromWooCommerce(wooCustomers);

          // Recargar desde local después de sincronizar
          _customers = await _localDb.getAllCustomers();
          _lastSync = DateTime.now();
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
        final wooResults = await _wooService.searchCustomers(query);

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
      return await _localDb.getRecentCustomers(limit: limit);
    } catch (e) {
      debugPrint('[CustomerManager] Error obteniendo recientes: $e');
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
          final wooCustomer = await _wooService.createCustomer(customer);

          // Actualizar con ID de WooCommerce
          await _localDb.markCustomerAsSynced(
            customer.id ?? 0,
            wooCustomer.id!,
          );

          // Recargar clientes
          await loadAllCustomers();

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

      // Si tiene ID de WooCommerce, actualizar allá también
      if (customer.id != null && customer.isSyncedWithWoo) {
        try {
          await _wooService.updateCustomer(customer);
        } catch (e) {
          debugPrint('[CustomerManager] Error actualizando en WooCommerce: $e');
        }
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
      // Eliminar de WooCommerce si está sincronizado
      if (customer.id != null && customer.isSyncedWithWoo) {
        try {
          await _wooService.deleteCustomer(customer.id!, force: true);
        } catch (e) {
          debugPrint('[CustomerManager] Error eliminando de WooCommerce: $e');
        }
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
      // Guardar en base de datos local
      await _localDb.saveCustomer(customer);

      // Intentar sincronizar con WooCommerce si tiene email
      if (customer.email.isNotEmpty && customer.email.contains('@')) {
        try {
          final wooCustomer = await _wooService.createCustomer(customer);
          await _localDb.markCustomerAsSynced(
            customer.id ?? 0,
            wooCustomer.id!,
          );
        } catch (e) {
          debugPrint('[CustomerManager] No se pudo sincronizar con WooCommerce: $e');
        }
      }

      // Recargar
      await loadAllCustomers();
      return customer;
    } catch (e) {
      _error = 'Error importando contacto: $e';
      debugPrint('[CustomerManager] $_error');
      notifyListeners();
      return null;
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
            address: customer.address!,
            city: customer.city,
            state: customer.state,
            postalCode: customer.postcode,
            country: customer.country,
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
          final wooCustomer = await _wooService.createCustomer(customer);

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
      }

      return synced;
    } catch (e) {
      debugPrint('[CustomerManager] Error en sincronización masiva: $e');
      return 0;
    }
  }

  /// Limpiar cache de WooCommerce
  void clearWooCommerceCache() {
    _wooService.clearCache();
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

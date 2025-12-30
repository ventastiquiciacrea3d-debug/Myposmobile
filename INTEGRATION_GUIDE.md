# 📋 GUÍA DE INTEGRACIÓN - MyPOS Mobile Improvements

## Resumen de Mejoras Implementadas

Esta guía documenta las mejoras implementadas en MyPOS Mobile, incluyendo:

1. **Sistema de Compartir Cotizaciones** - PDF y texto formateado para WhatsApp/Email
2. **Escáner Mejorado** - Control de duplicados con debounce de 1500ms
3. **Sistema Completo de Clientes** - Multi-fuente (WooCommerce + Local + Contactos)
4. **Configuración Centralizada** - Modelo de settings expandido

---

## 📦 1. DEPENDENCIAS NUEVAS

### Instalación Requerida

```bash
cd my_pos_app
flutter pub get
```

### Dependencia Agregada en pubspec.yaml

```yaml
dependencies:
  sqflite: ^2.3.3  # Base de datos local para clientes
```

**IMPORTANTE:** La dependencia `sqflite` es esencial para el sistema de clientes. Asegúrate de ejecutar `flutter pub get` antes de compilar.

---

## 🎯 2. SISTEMA DE COMPARTIR COTIZACIONES

### Archivos Creados

```
lib/services/quote_share_service.dart          (700+ líneas)
lib/widgets/share_quote_dialog.dart            (360+ líneas)
lib/widgets/quote_settings_section.dart        (310+ líneas)
```

### Archivos Modificados

```
lib/locator.dart                               (+ QuoteShareService registration)
lib/screens/settings_screen.dart               (+ QuoteSettingsSection widget)
lib/screens/order_screen.dart                  (+ Share button + _shareQuote method)
```

### Características Implementadas

✅ **Generación de PDF Profesional**
- Header con logo de empresa
- Información del cliente
- Tabla de productos con subtotal
- Cálculo de impuestos (IVA 13%)
- Total destacado
- Términos y condiciones personalizables

✅ **Texto Formateado para WhatsApp**
- Emojis temáticos
- Formato optimizado para mensajería
- Resumen de productos
- Totales calculados

✅ **4 Métodos de Compartir**
- WhatsApp directo (si número de cliente disponible)
- Email (si email de cliente disponible)
- Compartir genérico (cualquier app)
- Solo texto (copiar al portapapeles)

✅ **Configuración Personalizable**
- Información de empresa (nombre, teléfono, email, dirección)
- Mensajes personalizados (WhatsApp, footer)
- Términos de pago y validez
- Logo e imágenes opcionales

### Uso en Pantallas

#### En order_screen.dart

El botón de compartir se agregó en la sección de resumen de orden:

```dart
ElevatedButton.icon(
  onPressed: order.items.isEmpty ? null : () => _shareQuote(context, order),
  icon: const Icon(Icons.share, size: 18),
  label: const Text('Compartir Cotización'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade700,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
)
```

El método `_shareQuote` convierte los items de la orden en QuoteItems y muestra el diálogo:

```dart
Future<void> _shareQuote(BuildContext context, Order order) async {
  final quoteService = getIt<QuoteShareService>();
  final quoteItems = order.items.map((item) => QuoteItem(
    name: item.name,
    quantity: item.quantity,
    price: item.price,
    sku: item.sku,
  )).toList();

  await showShareQuoteDialog(
    context: context,
    items: quoteItems,
    subtotal: order.subtotal,
    taxAmount: order.tax,
    total: order.total,
    quoteShareService: quoteService,
    customerName: customerName,
    customerPhone: null,  // TODO: Integrar con sistema de clientes
    customerEmail: null,  // TODO: Integrar con sistema de clientes
  );
}
```

**NOTA:** Los campos `customerPhone` y `customerEmail` están como null porque el CustomerState actual solo tiene `selectedCustomerId` y `selectedCustomerName`. Para habilitar WhatsApp y Email directos, necesitas integrar con el nuevo sistema de clientes.

#### En settings_screen.dart

La sección de configuración de cotizaciones se agregó en `_buildSettingsListView`:

```dart
(ctx, sm) => QuoteSettingsSection(
  prefs: prefs,
  inactiveTrackColor: _inactiveTrackColor,
  inactiveThumbColor: _inactiveThumbColor,
),
```

### Configuración de Quote Share

Los usuarios pueden personalizar:

1. **Información de Empresa**
   - Nombre del negocio
   - Teléfono de contacto
   - Email corporativo
   - Dirección física

2. **Mensajes Personalizados**
   - Mensaje de WhatsApp (aparece al compartir)
   - Mensaje de footer (aparece en PDF)

3. **Términos Comerciales**
   - Términos de pago (ej: "50% anticipo, 50% contra entrega")
   - Validez de cotización (ej: "7 días")

### Datos Persistidos

Todos los settings se guardan en **SharedPreferences** con el prefijo `quote_`:

```
quote_business_name
quote_business_phone
quote_business_email
quote_business_address
quote_whatsapp_message
quote_footer_message
quote_payment_terms
quote_validity_days
```

---

## 📱 3. ESCÁNER MEJORADO

### Archivos Creados

```
lib/screens/improved_scanner_screen.dart       (500+ líneas)
```

### Mejoras Implementadas

✅ **Debounce de 1500ms**
- Previene escaneos duplicados
- Timer reiniciable en cada detección
- Variable `_lastScannedCode` para comparación

✅ **Control de Diálogo Único**
- Flag `_isShowingDialog` previene múltiples diálogos
- Solo un diálogo activo a la vez
- Estado limpio al cerrar diálogo

✅ **Gestión Completa del Ciclo de Vida de Cámara**
- Listener de `AppLifecycleState`
- Pausa automática cuando app va a background
- Reanudación cuando app vuelve a foreground
- Limpieza en `dispose()`

✅ **Botón de Cerrar Siempre Funcional**
- No depende del estado de la cámara
- Método `_closeCamera()` independiente
- Navegación segura con `Navigator.pop()`

✅ **Overlay Visual con Área de Escaneo**
- Rectángulo verde semi-transparente
- Indicadores de esquinas
- Mensaje de ayuda contextual

✅ **Controles Adicionales**
- Toggle de flash (linterna)
- Cambio de cámara (frontal/trasera)
- Entrada manual de código
- Indicador de estado de procesamiento

### Arquitectura del Escáner

```dart
class _ImprovedScannerScreenState extends State<ImprovedScannerScreen>
    with WidgetsBindingObserver {

  // Control de estado
  bool _isProcessing = false;
  bool _isShowingDialog = false;
  String? _lastScannedCode;

  // Debounce
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 1500);

  // Cámara
  bool _isCameraActive = true;
  bool _flashEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCameraActive) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _scannerController.stop();
        break;
      case AppLifecycleState.resumed:
        _scannerController.start();
        break;
      default:
        break;
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing || _isShowingDialog) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code == _lastScannedCode) return;

    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted && !_isShowingDialog) {
        _processBarcode(code);
      }
    });
  }
}
```

### Integración con App Existente

**OPCIÓN 1: Reemplazo Completo**

Reemplaza `scanner_screen.dart` con `improved_scanner_screen.dart`:

```dart
// En routes.dart o donde navegas al escáner
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ImprovedScannerScreen(
      onBarcodeScanned: (String barcode) {
        // Lógica de manejo de código escaneado
      },
    ),
  ),
);
```

**OPCIÓN 2: Uso Paralelo (Testing)**

Mantén ambos escáneres y permite al usuario elegir en settings:

```dart
// En app_settings_model.dart
final bool useImprovedScanner;

// En tu lógica de navegación
final settings = await AppSettingsModel.load();
if (settings.useImprovedScanner) {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ImprovedScannerScreen(onBarcodeScanned: callback),
  ));
} else {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ScannerScreen(onBarcodeScanned: callback),
  ));
}
```

---

## 👥 4. SISTEMA COMPLETO DE CLIENTES

### Archivos Creados

```
lib/models/customer_model.dart                        (280+ líneas)
lib/services/local_database_service.dart              (280+ líneas)
lib/services/woocommerce_customer_service.dart        (170+ líneas)
lib/services/customer_manager_service.dart            (370+ líneas)
lib/models/app_settings_model.dart                    (200+ líneas)
lib/screens/improved_customer_selection_screen.dart   (480+ líneas)
```

### Arquitectura Multi-Fuente

```
┌─────────────────────────────────────────────┐
│    ImprovedCustomerSelectionScreen          │
│    (UI con 3 tabs: Clientes, Recientes,    │
│     Contactos)                              │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│      CustomerManagerService                 │
│      (Servicio maestro coordinador)         │
└─────┬──────────────────┬────────────────────┘
      │                  │
      ▼                  ▼
┌─────────────────┐  ┌──────────────────────┐
│ LocalDatabase   │  │ WooCommerceCustomer  │
│ Service         │  │ Service              │
│ (SQLite)        │  │ (API REST)           │
└─────────────────┘  └──────────────────────┘
      │                  │
      ▼                  ▼
┌─────────────────┐  ┌──────────────────────┐
│ SQLite DB       │  │ WooCommerce API      │
│ (customers)     │  │ /wp-json/wc/v3/      │
└─────────────────┘  └──────────────────────┘

      ┌──────────────────────┐
      │ flutter_contacts     │
      │ (Device Contacts)    │
      └──────────────────────┘
```

### CustomerModel - Modelo Multi-Fuente

El modelo soporta 4 fuentes de datos:

```dart
enum CustomerSource {
  woocommerce,    // Sincronizado desde WooCommerce
  manual,         // Creado manualmente en la app
  deviceContacts, // Importado de contactos del dispositivo
  imported        // Importado de otra fuente
}

class CustomerModel {
  final int? id;              // WooCommerce ID
  final String? localId;      // UUID local
  final CustomerSource source;
  final bool isSyncedWithWoo;

  // Factory constructors para cada fuente
  factory CustomerModel.fromWooCommerce(Map<String, dynamic> json);
  factory CustomerModel.fromSQLite(Map<String, dynamic> map);
  factory CustomerModel.fromContact({String displayName, String? phone, String? email});

  // Métodos de conversión
  Map<String, dynamic> toSQLiteMap();
  Map<String, dynamic> toWooCommerceJson();
}
```

### LocalDatabaseService - SQLite Local

Base de datos local con búsqueda optimizada:

```dart
class LocalDatabaseService {
  // Tabla: customers con índices en email, name, phone

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY,
        local_id TEXT UNIQUE,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT,
        company TEXT,
        address TEXT,
        city TEXT,
        state TEXT,
        postcode TEXT,
        country TEXT,
        source TEXT NOT NULL,
        woocommerce_id INTEGER,
        is_synced_with_woo INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // Índices para búsqueda rápida
    await db.execute('CREATE INDEX idx_customers_email ON customers(email)');
    await db.execute('CREATE INDEX idx_customers_name ON customers(first_name, last_name)');
    await db.execute('CREATE INDEX idx_customers_phone ON customers(phone)');
  }

  // Búsqueda multi-campo
  Future<List<CustomerModel>> searchCustomers(String query) async {
    final searchQuery = '%${query.toLowerCase()}%';
    final maps = await db.query(
      'customers',
      where: '''
        LOWER(first_name) LIKE ? OR
        LOWER(last_name) LIKE ? OR
        LOWER(email) LIKE ? OR
        LOWER(phone) LIKE ? OR
        LOWER(company) LIKE ?
      ''',
      whereArgs: [searchQuery, searchQuery, searchQuery, searchQuery, searchQuery],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => CustomerModel.fromSQLite(map)).toList();
  }
}
```

**Métodos Disponibles:**

- `getAllCustomers()` - Obtener todos los clientes locales
- `getCustomerById(int id)` - Buscar por ID
- `getCustomerByEmail(String email)` - Buscar por email
- `searchCustomers(String query)` - Búsqueda multi-campo
- `getRecentCustomers({int limit = 10})` - Clientes recientes
- `saveCustomer(CustomerModel)` - Guardar/actualizar
- `deleteCustomer(int id)` - Eliminar
- `syncCustomersFromWooCommerce(List<CustomerModel>)` - Sincronización masiva
- `markCustomerAsSynced(int localId, int wooId)` - Marcar como sincronizado
- `getUnsyncedCustomers()` - Clientes pendientes de sync
- `getCustomerCount()` - Contador total

### WooCommerceCustomerService - API Integration

Servicio de API con cache de 5 minutos:

```dart
class WooCommerceCustomerService {
  static const Duration _cacheDuration = Duration(minutes: 5);
  DateTime? _lastFetchTime;
  List<CustomerModel>? _cachedCustomers;

  // Autenticación
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
  };

  // Obtener todos con paginación
  Future<List<CustomerModel>> getAllCustomers({
    bool forceRefresh = false,
    int perPage = 100,
  }) async {
    // Verificar cache
    if (!forceRefresh && _cachedCustomers != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedCustomers!;
    }

    // Fetch paginado
    final customers = <CustomerModel>[];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final response = await http.get(Uri.parse(
        _buildUrl('customers', {'per_page': perPage.toString(), 'page': page.toString()})
      ), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isEmpty) {
          hasMore = false;
        } else {
          customers.addAll(data.map((json) => CustomerModel.fromWooCommerce(json)));
          page++;
        }
      }
    }

    _cachedCustomers = customers;
    _lastFetchTime = DateTime.now();
    return customers;
  }
}
```

**Métodos Disponibles:**

- `getAllCustomers({bool forceRefresh, int perPage})` - Obtener todos (con cache)
- `searchCustomers(String query)` - Buscar en WooCommerce
- `getCustomerById(int id)` - Obtener por ID
- `createCustomer(CustomerModel)` - Crear nuevo
- `updateCustomer(CustomerModel)` - Actualizar existente
- `deleteCustomer(int id, {bool force})` - Eliminar
- `clearCache()` - Limpiar cache manualmente

### CustomerManagerService - Coordinador Maestro

Servicio principal que integra todas las fuentes:

```dart
class CustomerManagerService extends ChangeNotifier {
  final LocalDatabaseService _localDb;
  final WooCommerceCustomerService _wooService;

  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;

  // Cargar todos los clientes (local + sync con WooCommerce cada 1 hora)
  Future<void> loadAllCustomers({bool forceSync = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Cargar desde local
      final localCustomers = await _localDb.getAllCustomers();

      // 2. Sincronizar con WooCommerce si necesario
      final shouldSync = forceSync ||
          _lastSync == null ||
          DateTime.now().difference(_lastSync!) > const Duration(hours: 1);

      if (shouldSync) {
        try {
          final wooCustomers = await _wooService.getAllCustomers(forceRefresh: true);
          await _localDb.syncCustomersFromWooCommerce(wooCustomers);
          _customers = await _localDb.getAllCustomers();
          _lastSync = DateTime.now();
        } catch (e) {
          // Si falla WooCommerce, usar datos locales
          _customers = localCustomers;
        }
      } else {
        _customers = localCustomers;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Búsqueda combinada (local + WooCommerce)
  Future<List<CustomerModel>> searchCustomers(String query) async {
    // Buscar en local (rápido)
    final localResults = await _localDb.searchCustomers(query);

    if (localResults.length >= 10) {
      return localResults;
    }

    // Buscar también en WooCommerce
    try {
      final wooResults = await _wooService.searchCustomers(query);

      // Combinar sin duplicados (por email)
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
      return localResults;
    }
  }

  // Buscar en contactos del dispositivo
  Future<List<CustomerModel>> searchDeviceContacts(String query) async {
    if (!await FlutterContacts.requestPermission()) return [];

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    final filtered = contacts.where((contact) {
      return contact.displayName.toLowerCase().contains(query.toLowerCase());
    }).toList();

    return filtered.take(20).map((contact) {
      return CustomerModel.fromContact(
        displayName: contact.displayName,
        phone: contact.phones.isNotEmpty ? contact.phones.first.number : null,
        email: contact.emails.isNotEmpty ? contact.emails.first.address : null,
      );
    }).toList();
  }

  // Importar contacto del dispositivo
  Future<CustomerModel?> importFromDeviceContact(CustomerModel customer) async {
    await _localDb.saveCustomer(customer);

    // Intentar sincronizar con WooCommerce
    if (customer.email.isNotEmpty && customer.email.contains('@')) {
      try {
        final wooCustomer = await _wooService.createCustomer(customer);
        await _localDb.markCustomerAsSynced(customer.id ?? 0, wooCustomer.id!);
      } catch (e) {
        // No crítico, cliente guardado localmente
      }
    }

    await loadAllCustomers();
    return customer;
  }
}
```

**Métodos Disponibles:**

- `loadAllCustomers({bool forceSync})` - Cargar y sincronizar
- `searchCustomers(String query)` - Búsqueda combinada
- `getRecentCustomers({int limit})` - Clientes recientes
- `createCustomer(CustomerModel)` - Crear nuevo (local + WooCommerce)
- `updateCustomer(CustomerModel)` - Actualizar (local + WooCommerce)
- `deleteCustomer(CustomerModel)` - Eliminar (local + WooCommerce)
- `searchDeviceContacts(String query)` - Buscar en contactos
- `importFromDeviceContact(CustomerModel)` - Importar contacto
- `saveToDeviceContacts(CustomerModel)` - Exportar a contactos
- `syncUnsyncedCustomers()` - Sincronizar pendientes
- `clearWooCommerceCache()` - Limpiar cache
- `getStatistics()` - Estadísticas (total, sincronizados, pendientes)

### ImprovedCustomerSelectionScreen - UI Completa

Pantalla con 3 tabs y búsqueda en tiempo real:

```dart
class ImprovedCustomerSelectionScreen extends StatefulWidget {
  final CustomerManagerService customerService;

  const ImprovedCustomerSelectionScreen({
    required this.customerService,
  });
}

class _ImprovedCustomerSelectionScreenState extends State
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<CustomerModel> _searchResults = [];
  List<CustomerModel> _recentCustomers = [];
  List<CustomerModel> _contactResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecentCustomers();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _contactResults = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      // Buscar en clientes (WooCommerce + Local)
      final results = await widget.customerService.searchCustomers(query);

      // Buscar en contactos si está en esa tab
      if (_tabController.index == 2) {
        final contacts = await widget.customerService.searchDeviceContacts(query);
        setState(() => _contactResults = contacts);
      }

      setState(() => _searchResults = results);
    });
  }
}
```

**Características:**

- **Tab 1: Clientes** - Búsqueda en WooCommerce + Local
- **Tab 2: Recientes** - Últimos 10 clientes usados
- **Tab 3: Contactos** - Búsqueda en contactos del dispositivo

**Funcionalidades:**

- Búsqueda en tiempo real con debounce de 500ms
- Crear nuevo cliente (formulario de validación)
- Importar desde contactos con un tap
- Indicadores visuales:
  - Avatar azul = WooCommerce
  - Avatar verde = Local/Manual
  - Avatar naranja = Contacto del dispositivo
  - Icono de nube = Estado de sincronización

### Integración con Orden Screen

Para usar el nuevo sistema de clientes en la pantalla de órdenes:

```dart
// En order_screen.dart o donde necesites seleccionar cliente

Future<void> _selectCustomer(BuildContext context) async {
  final customerService = getIt<CustomerManagerService>();

  final selectedCustomer = await Navigator.push<CustomerModel>(
    context,
    MaterialPageRoute(
      builder: (context) => ImprovedCustomerSelectionScreen(
        customerService: customerService,
      ),
    ),
  );

  if (selectedCustomer != null) {
    // Actualizar el estado de la orden con el cliente seleccionado
    setState(() {
      _currentCustomer = selectedCustomer;
    });

    // Ahora tienes acceso completo al cliente:
    print('Cliente: ${selectedCustomer.fullName}');
    print('Email: ${selectedCustomer.email}');
    print('Teléfono: ${selectedCustomer.phone}');
    print('Sincronizado: ${selectedCustomer.isSyncedWithWoo}');
  }
}
```

### Registro en Dependency Injection

**IMPORTANTE:** Debes registrar los nuevos servicios en `locator.dart`:

```dart
import 'services/local_database_service.dart';
import 'services/woocommerce_customer_service.dart';
import 'services/customer_manager_service.dart';

void setupLocator() {
  // ... otros servicios existentes

  // Local Database Service
  getIt.registerSingletonAsync<LocalDatabaseService>(() async {
    final service = LocalDatabaseService();
    await service.initialize();
    return service;
  });

  // WooCommerce Customer Service
  getIt.registerSingletonAsync<WooCommerceCustomerService>(
    () async {
      // Obtener credenciales desde StorageService
      final storageService = getIt<StorageService>();
      final baseUrl = await storageService.getApiUrl() ?? '';
      final consumerKey = await storageService.getConsumerKey() ?? '';
      final consumerSecret = await storageService.getConsumerSecret() ?? '';

      return WooCommerceCustomerService(
        baseUrl: baseUrl,
        consumerKey: consumerKey,
        consumerSecret: consumerSecret,
      );
    },
    dependsOn: [StorageService],
  );

  // Customer Manager Service (maestro)
  getIt.registerSingletonAsync<CustomerManagerService>(
    () async {
      final localDb = getIt<LocalDatabaseService>();
      final wooService = getIt<WooCommerceCustomerService>();

      final manager = CustomerManagerService(
        localDb: localDb,
        wooService: wooService,
      );

      // Cargar clientes iniciales
      await manager.loadAllCustomers();

      return manager;
    },
    dependsOn: [LocalDatabaseService, WooCommerceCustomerService],
  );
}
```

---

## ⚙️ 5. MODELO DE CONFIGURACIÓN CENTRALIZADO

### Archivo Creado

```
lib/models/app_settings_model.dart                (200+ líneas)
```

### Configuraciones Soportadas

```dart
class AppSettingsModel {
  // ===== COTIZACIONES =====
  final bool shareQuoteEnabled;
  final QuoteFormat quoteFormat;        // pdf, text, both
  final bool includeLogoInQuote;
  final bool includeProductImages;
  final bool includeTermsAndConditions;

  // ===== ESCÁNER =====
  final bool scannerVibrationEnabled;
  final bool scannerSoundEnabled;
  final bool scannerAutoAddEnabled;
  final int scannerDebounceMs;          // Default: 1500ms

  // ===== CLIENTES =====
  final bool autoLoadCustomersFromWoo;
  final bool allowDeviceContactsSearch;
  final bool autoSaveToDeviceContacts;

  // ===== SINCRONIZACIÓN =====
  final bool autoSyncEnabled;
  final int autoSyncIntervalMinutes;    // Default: 30 minutos

  // ===== INFORMACIÓN DE EMPRESA =====
  final String companyName;
  final String companyPhone;
  final String companyEmail;
  final String companyAddress;
}
```

### Uso del Modelo

```dart
// Cargar configuración
final settings = await AppSettingsModel.load();

// Acceder a valores
if (settings.scannerVibrationEnabled) {
  HapticFeedback.vibrate();
}

final debounceMs = settings.scannerDebounceMs;

// Modificar y guardar
final newSettings = settings.copyWith(
  scannerDebounceMs: 2000,
  autoSyncIntervalMinutes: 15,
);

await newSettings.save();
```

### Claves de SharedPreferences

Todas las configuraciones se guardan con claves específicas:

**Cotizaciones:**
- `share_quote_enabled`
- `quote_format`
- `include_logo_in_quote`
- `include_product_images`
- `include_terms_and_conditions`

**Escáner:**
- `scanner_vibration_enabled`
- `scanner_sound_enabled`
- `scanner_auto_add_enabled`
- `scanner_debounce_ms`

**Clientes:**
- `auto_load_customers_from_woo`
- `allow_device_contacts_search`
- `auto_save_to_device_contacts`

**Sincronización:**
- `auto_sync_enabled`
- `auto_sync_interval_minutes`

**Empresa:**
- `company_name`
- `company_phone`
- `company_email`
- `company_address`

---

## 🔧 6. PASOS DE INTEGRACIÓN COMPLETA

### Paso 1: Instalar Dependencias

```bash
cd my_pos_app
flutter pub get
```

Verifica que `sqflite: ^2.3.3` esté instalado.

### Paso 2: Registrar Servicios en GetIt

Edita `lib/locator.dart` y agrega los nuevos servicios (ver sección anterior).

### Paso 3: Inicializar Base de Datos

En `main.dart`, antes de `runApp()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Hive
  await Hive.initFlutter();

  // Configurar GetIt
  setupLocator();
  await getIt.allReady();

  // Inicializar base de datos de clientes
  final localDb = getIt<LocalDatabaseService>();
  await localDb.initialize();

  runApp(const MyApp());
}
```

### Paso 4: Integrar Escáner Mejorado

**Opción A: Reemplazo Directo**

Elimina o renombra `scanner_screen.dart` y usa `improved_scanner_screen.dart`:

```dart
// En tu navegación
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ImprovedScannerScreen(
      onBarcodeScanned: (String code) {
        // Tu lógica aquí
      },
    ),
  ),
);
```

**Opción B: Toggle en Settings**

Agrega una opción en settings para elegir:

```dart
final settings = await AppSettingsModel.load();
if (settings.useImprovedScanner) {
  // Navegar a ImprovedScannerScreen
} else {
  // Navegar a ScannerScreen (legacy)
}
```

### Paso 5: Integrar Sistema de Clientes

En la pantalla de órdenes o donde necesites seleccionar clientes:

```dart
// Botón de seleccionar cliente
ElevatedButton(
  onPressed: () async {
    final customerService = getIt<CustomerManagerService>();

    final customer = await Navigator.push<CustomerModel>(
      context,
      MaterialPageRoute(
        builder: (_) => ImprovedCustomerSelectionScreen(
          customerService: customerService,
        ),
      ),
    );

    if (customer != null) {
      setState(() => _selectedCustomer = customer);
    }
  },
  child: Text(_selectedCustomer?.fullName ?? 'Seleccionar Cliente'),
)
```

### Paso 6: Usar Quote Sharing con Customer Info

Ahora que tienes el customer completo, actualiza `_shareQuote` en `order_screen.dart`:

```dart
Future<void> _shareQuote(BuildContext context, Order order) async {
  final quoteService = getIt<QuoteShareService>();
  final quoteItems = order.items.map((item) => QuoteItem(
    name: item.name,
    quantity: item.quantity,
    price: item.price,
    sku: item.sku,
  )).toList();

  await showShareQuoteDialog(
    context: context,
    items: quoteItems,
    subtotal: order.subtotal,
    taxAmount: order.tax,
    total: order.total,
    quoteShareService: quoteService,
    customerName: _selectedCustomer?.fullName,           // ✅ Ahora disponible
    customerPhone: _selectedCustomer?.phone,             // ✅ Ahora disponible
    customerEmail: _selectedCustomer?.email,             // ✅ Ahora disponible
  );
}
```

### Paso 7: Configurar Sincronización Automática

En `AppStateProvider` o donde inicialices la app:

```dart
class AppStateProvider extends ChangeNotifier {
  Future<void> initialize() async {
    final customerManager = getIt<CustomerManagerService>();

    // Sincronización inicial
    await customerManager.loadAllCustomers();

    // Programar sincronización periódica (opcional)
    Timer.periodic(const Duration(hours: 1), (timer) async {
      await customerManager.loadAllCustomers(forceSync: true);
    });
  }
}
```

---

## 🧪 7. TESTING Y VALIDACIÓN

### Pruebas Funcionales Recomendadas

#### Quote Sharing
- [ ] Generar PDF con productos y verificar formato
- [ ] Compartir vía WhatsApp con cliente que tiene teléfono
- [ ] Enviar email a cliente que tiene email
- [ ] Compartir genérico (cualquier app)
- [ ] Copiar texto de cotización al portapapeles
- [ ] Configurar información de empresa en settings
- [ ] Verificar que configuración se persiste (reiniciar app)

#### Escáner Mejorado
- [ ] Escanear código de barras y verificar que no hay duplicados
- [ ] Cerrar cámara con botón X
- [ ] Enviar app a background y verificar que cámara se pausa
- [ ] Regresar app y verificar que cámara se reanuda
- [ ] Activar/desactivar flash
- [ ] Cambiar cámara (frontal/trasera)
- [ ] Ingresar código manualmente
- [ ] Escanear código repetidamente y verificar debounce de 1500ms

#### Sistema de Clientes
- [ ] Buscar cliente en tab "Clientes" (WooCommerce + Local)
- [ ] Ver clientes recientes en tab "Recientes"
- [ ] Buscar contacto en tab "Contactos"
- [ ] Crear nuevo cliente manualmente
- [ ] Importar contacto del dispositivo
- [ ] Seleccionar cliente y verificar que datos se pasen correctamente
- [ ] Verificar sincronización con WooCommerce (icono de nube)
- [ ] Crear cliente offline y verificar que se sincroniza cuando hay conexión
- [ ] Editar cliente y verificar actualización en WooCommerce
- [ ] Eliminar cliente y verificar eliminación en WooCommerce

### Comandos de Diagnóstico

```bash
# Verificar que no hay errores de compilación
flutter analyze

# Limpiar build cache
flutter clean

# Rebuild completo
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --debug

# Ver logs en tiempo real
flutter run -v
```

---

## 📊 8. ESTADÍSTICAS Y MONITOREO

### Customer Manager Statistics

```dart
final customerService = getIt<CustomerManagerService>();
final stats = await customerService.getStatistics();

print('Total clientes: ${stats['total']}');
print('Sincronizados: ${stats['synced']}');
print('Pendientes de sync: ${stats['unsynced']}');

// Sincronizar manualmente clientes pendientes
final synced = await customerService.syncUnsyncedCustomers();
print('Sincronizados: $synced clientes');
```

### Última Sincronización

```dart
final lastSync = customerService.lastSync;
if (lastSync != null) {
  final elapsed = DateTime.now().difference(lastSync);
  print('Última sincronización hace ${elapsed.inMinutes} minutos');
}
```

---

## 🚨 9. TROUBLESHOOTING

### Error: "MissingPluginException (MissingPluginException(No implementation found for method...))"

**Causa:** Plugin de `sqflite` no instalado correctamente.

**Solución:**
```bash
flutter clean
flutter pub get
cd android && ./gradlew clean && cd ..
flutter run
```

### Error: "Unhandled Exception: DatabaseException(no such table: customers)"

**Causa:** Base de datos no inicializada.

**Solución:**
```dart
// En main.dart, antes de runApp
final localDb = getIt<LocalDatabaseService>();
await localDb.initialize();
```

### Error: "Bad state: No element" al buscar clientes

**Causa:** Búsqueda retorna lista vacía pero código asume hay resultados.

**Solución:**
```dart
final results = await customerService.searchCustomers(query);
if (results.isEmpty) {
  // Manejar caso vacío
  return;
}
final customer = results.first;
```

### Performance: Búsqueda lenta en clientes

**Causa:** Falta índice en SQLite.

**Solución:** Los índices ya están creados en `local_database_service.dart` líneas 30-32. Si tienes base de datos vieja, elimínala:

```dart
// Aumentar versión de base de datos para forzar recreación
static const int _databaseVersion = 2;  // Cambiar de 1 a 2
```

### Sincronización: Clientes no se sincronizan con WooCommerce

**Verificar:**

1. **Credenciales correctas:**
```dart
final wooService = getIt<WooCommerceCustomerService>();
// Verificar que baseUrl, consumerKey, consumerSecret estén configurados
```

2. **Conectividad:**
```dart
final connectivity = await Connectivity().checkConnectivity();
if (connectivity == ConnectivityResult.none) {
  print('Sin conexión a internet');
}
```

3. **Permisos en WooCommerce:**
- Verificar que Consumer Key/Secret tengan permisos de lectura/escritura
- Endpoint: `/wp-json/wc/v3/customers` debe estar accesible

### Contactos: No se puede acceder a contactos del dispositivo

**Causa:** Permisos no concedidos.

**Solución en Android:**
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.WRITE_CONTACTS" />
```

**Solicitar en código:**
```dart
final granted = await FlutterContacts.requestPermission();
if (!granted) {
  // Mostrar mensaje al usuario
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Permiso Requerido'),
      content: Text('La app necesita acceso a contactos para importar clientes.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK'),
        ),
      ],
    ),
  );
}
```

---

## 📝 10. COMMITS REALIZADOS

### Commit 1: 8afad95
**Mensaje:** `fix: Corregir duplicación de diálogos en escáner y mostrar stock en pantalla actual`

**Archivos modificados:**
- `scanner_screen.dart` - Corregido diálogos duplicados
- `order_screen.dart` - Mostrar stock en pantalla actual

### Commit 2: 63654e6
**Mensaje:** `feat: Implementar sistema completo de compartir cotizaciones (PDF + Texto)`

**Archivos creados:**
- `quote_share_service.dart`
- `share_quote_dialog.dart`
- `quote_settings_section.dart`

**Archivos modificados:**
- `locator.dart`
- `settings_screen.dart`
- `order_screen.dart`

### Commit 3: f53bd43
**Mensaje:** `feat: Implementar escáner mejorado y base del sistema de clientes (Fase 1)`

**Archivos creados:**
- `improved_scanner_screen.dart`
- `customer_model.dart`
- `local_database_service.dart`
- `woocommerce_customer_service.dart`

### Commit 4: 9f6fb0c
**Mensaje:** `feat: Completar sistema de clientes y configuración (Fase 2)`

**Archivos creados:**
- `customer_manager_service.dart`
- `app_settings_model.dart`
- `improved_customer_selection_screen.dart`

**Archivos modificados:**
- `pubspec.yaml` - Agregado `sqflite: ^2.3.3`

---

## ✅ 11. CHECKLIST DE INTEGRACIÓN

Usa este checklist para verificar que todo está integrado correctamente:

### Instalación Base
- [ ] Ejecutado `flutter pub get`
- [ ] Dependencia `sqflite: ^2.3.3` instalada
- [ ] Sin errores en `flutter analyze`
- [ ] App compila sin errores

### Configuración GetIt
- [ ] `QuoteShareService` registrado en `locator.dart`
- [ ] `LocalDatabaseService` registrado en `locator.dart`
- [ ] `WooCommerceCustomerService` registrado en `locator.dart`
- [ ] `CustomerManagerService` registrado en `locator.dart`
- [ ] Dependencias correctamente ordenadas

### Quote Sharing
- [ ] Botón de compartir visible en order screen
- [ ] QuoteSettingsSection agregada en settings screen
- [ ] PDF se genera correctamente
- [ ] Texto de cotización se formatea bien
- [ ] Métodos de compartir funcionan (WhatsApp, Email, etc.)

### Escáner Mejorado
- [ ] ImprovedScannerScreen navegable
- [ ] Debounce de 1500ms funciona
- [ ] No hay diálogos duplicados
- [ ] Cámara se pausa en background
- [ ] Botón de cerrar siempre funcional

### Sistema de Clientes
- [ ] Base de datos SQLite se crea correctamente
- [ ] Búsqueda en clientes funciona
- [ ] Búsqueda en contactos funciona
- [ ] Crear nuevo cliente funciona
- [ ] Importar desde contactos funciona
- [ ] Sincronización con WooCommerce funciona
- [ ] Indicadores visuales correctos

### Integración Final
- [ ] Clientes se pueden seleccionar desde order screen
- [ ] Info de cliente se pasa a quote sharing
- [ ] WhatsApp y Email directos funcionan con info de cliente
- [ ] Settings se persisten correctamente
- [ ] Sincronización automática configurada

---

## 🎓 12. MEJORES PRÁCTICAS

### Para Desarrolladores

1. **Siempre usar CustomerManagerService**
   - No accedas directamente a LocalDatabaseService o WooCommerceCustomerService
   - CustomerManagerService coordina todo automáticamente

2. **Debouncing en Búsquedas**
   - Usa Timer con 500ms para búsquedas en UI
   - Cancela timers anteriores antes de crear nuevos

3. **Manejo de Errores**
   - Siempre captura excepciones en llamadas a servicios
   - Muestra mensajes amigables al usuario
   - Logs con `debugPrint('[ServiceName] Error: $e')`

4. **Estado de Loading**
   - Usa `_isLoading` flags para mostrar indicadores
   - Previene múltiples llamadas simultáneas

5. **Sincronización**
   - No fuerces sync en cada acción
   - Usa cache y sync periódica (1 hora)
   - Permite sync manual con pull-to-refresh

### Para Testing

1. **Test con Datos Mock**
   - Crea clientes de prueba antes de testear sincronización
   - Verifica que búsqueda funciona con caracteres especiales (ñ, á, etc.)

2. **Test Offline**
   - Desactiva WiFi/datos móviles
   - Verifica que búsqueda local funciona
   - Verifica que creación de clientes funciona offline
   - Reactiva conexión y verifica sync

3. **Test de Permisos**
   - Test con permisos de contactos denegados
   - Verifica mensajes de error apropiados

---

## 📚 13. RECURSOS ADICIONALES

### Documentación de Dependencias

- **sqflite:** https://pub.dev/packages/sqflite
- **flutter_contacts:** https://pub.dev/packages/flutter_contacts
- **mobile_scanner:** https://pub.dev/packages/mobile_scanner
- **pdf:** https://pub.dev/packages/pdf
- **share_plus:** https://pub.dev/packages/share_plus

### WooCommerce API

- **Customer Endpoints:** https://woocommerce.github.io/woocommerce-rest-api-docs/#customers
- **Authentication:** https://woocommerce.github.io/woocommerce-rest-api-docs/#authentication

---

## 🤝 14. SOPORTE

Si encuentras problemas durante la integración:

1. Verifica que todos los pasos del checklist están completos
2. Revisa la sección de Troubleshooting
3. Ejecuta `flutter clean && flutter pub get`
4. Verifica logs con `flutter run -v`
5. Comprueba que todas las credenciales de WooCommerce son correctas

---

**Última actualización:** 2024-12-29
**Versión de Flutter:** 3.2.6+
**Commits incluidos:** 8afad95, 63654e6, f53bd43, 9f6fb0c

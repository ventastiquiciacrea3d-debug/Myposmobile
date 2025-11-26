# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MY POS MOBILE BARCODE** - A Flutter mobile Point of Sale (POS) application for iOS and Android with barcode scanning, order management, inventory control, and thermal label printing. The app integrates with WooCommerce REST API and uses an offline-first architecture with background synchronization.

- **Framework:** Flutter 3.2.6+
- **Language:** Dart
- **Package Name:** my_pos_mobile_barcode
- **Main Directory:** `my_pos_app/`

## Essential Commands

### Development Setup
```bash
# Navigate to Flutter project directory
cd my_pos_app

# Install dependencies
flutter pub get

# Generate Hive adapters (required after model changes)
flutter pub run build_runner build

# Watch mode for continuous code generation during development
dart run build_runner watch
```

### Running the Application
```bash
# Run in debug mode
flutter run

# Run with verbose logging
flutter run -v

# Run on specific device
flutter devices           # List available devices
flutter run -d <device-id>
```

### Building
```bash
# Clean build artifacts
flutter clean

# Build Android APK (release)
flutter build apk --release

# Build iOS (release)
flutter build ios --release
```

### Code Generation
**CRITICAL:** After modifying any `@HiveType` models, you MUST regenerate adapters:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Linting
```bash
# Analyze code
flutter analyze
```

## Architecture

### Pattern: Clean Architecture + MVVM + Provider

```
UI Layer (Screens/Widgets)
    ↓ consumes
Provider Layer (State Management - ChangeNotifier)
    ↓ calls
Repository Layer (Data Access)
    ↓ uses
Service Layer (Business Logic)
    ↓ interacts with
Data Layer (Hive/API/SecureStorage)
```

### Core Components

1. **Dependency Injection (GetIt):** `lib/locator.dart`
   - Two setup functions: `setupLocator()` for main app, `setupBackgroundLocator()` for background isolate
   - Services registered as singletons with dependency ordering
   - **IMPORTANT:** SharedPreferences → StorageService → WooCommerceService must initialize in this order
   - Always call `await getIt.allReady()` before using services

2. **State Management (Provider):** `lib/providers/`
   - All providers extend `ChangeNotifier`
   - Use `notifyListeners()` after state changes
   - Access pattern in UI: `context.read<Provider>()` for actions, `context.watch<Provider>()` for reactive updates
   - Key providers:
     - `AppStateProvider`: Global app state, connectivity, sync status
     - `OrderProvider`: Order CRUD, tax calculations, history pagination
     - `InventoryProvider`: Stock management
     - `CustomerProvider`: Customer data
     - `ScannerProvider`: Scanner configuration
     - `LabelProvider`: Print queue

3. **Data Persistence (Hive):** NoSQL local database
   - All models use `@HiveType` annotation with `part '*.g.dart'`
   - Adapters auto-generated via `build_runner`
   - Registered in `locator.dart` via `registerHiveAdapters()`
   - Key boxes: `products`, `orders`, `pendingOrders`, `labelQueue`, `syncQueue`, `inventoryMovements`
   - **IMPORTANT:** Adapter type IDs are hardcoded (0-10); never change existing IDs

4. **API Integration (WooCommerce):** `lib/services/woocommerce_service.dart`
   - Uses Dio HTTP client with JWT authentication
   - Access token + refresh token pattern (auto-refresh on 401)
   - Custom exceptions: `ApiException`, `NetworkException`, `AuthenticationException`, `ServerException`
   - All endpoints check connectivity before making requests

5. **Offline-First Sync:** `lib/services/sync_manager.dart`
   - Queue-based synchronization using `SyncOperation` model
   - Operations queued in Hive when offline
   - 5-minute scheduled sync + immediate sync on connectivity restore
   - Background service runs sync in separate isolate

6. **Routing:** `lib/config/routes.dart`
   - Named routing pattern with `Routes` class constants
   - Helper methods: `Routes.navigateTo()`, `Routes.replaceWith()`, `Routes.goBack()`
   - Arguments passed via `ModalRoute.settings.arguments`

### Key Patterns

1. **SWR (Stale-While-Revalidate) Caching:** `lib/repositories/product_repository.dart`
   - Product details cached for 15 minutes
   - In-memory search cache for 5 minutes
   - Automatic background refresh for stale data
   - Stream events emitted on API updates: `onProductUpdatedFromApi`

2. **Multi-Layer Storage:**
   - **Hive:** Structured data (products, orders, sync queue)
   - **SharedPreferences:** User settings, preferences
   - **FlutterSecureStorage:** Encrypted secrets (API tokens, URLs, device UUID)
   - Unified interface via `StorageService`

3. **Error Handling:**
   - Try-catch blocks with `debugPrint` logging
   - User-facing errors shown via Fluttertoast (Spanish)
   - Log format: `[ServiceName] [MethodName] Message`

## Critical Implementation Details

### Working with Models

**When adding/modifying Hive models:**
1. Add `@HiveType(typeId: X)` to class (use next available ID)
2. Add `@HiveField(N)` to each field (sequential numbering)
3. Include `part 'model_name.g.dart';`
4. Run `flutter pub run build_runner build --delete-conflicting-outputs`
5. Register adapter in `locator.dart` → `registerHiveAdapters()`

**Example:**
```dart
import 'package:hive/hive.dart';

part 'my_model.g.dart';

@HiveType(typeId: 11)  // Next available ID
class MyModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  MyModel({required this.id, required this.name});
}
```

### Adding New Providers

1. Create provider in `lib/providers/` extending `ChangeNotifier`
2. Register in `main.dart` MultiProvider hierarchy
3. If depends on other providers, use `ChangeNotifierProxyProvider`
4. Call `notifyListeners()` after state mutations
5. Dispose resources in `dispose()` override

### Working with Repositories

- **ProductRepository:** Always use SWR methods (`getProductWithSWR`, `searchProductsWithSWR`)
- **OrderRepository:** Save orders to `pendingOrders` box until synced, then move to `orders`
- **InventoryRepository:** Track all stock changes via `InventoryMovement` model

### API Service Usage

```dart
final wooService = getIt<WooCommerceService>();

try {
  final product = await wooService.getProduct(productId);
  // Handle success
} on ProductNotFoundException catch (e) {
  // Product doesn't exist
} on NetworkException catch (e) {
  // No connectivity - fall back to cache
} on ApiException catch (e) {
  // API error - show user message
}
```

### Sync Operations

To queue an operation for background sync:
```dart
final syncOp = SyncOperation(
  id: uuid.v4(),
  type: SyncOperationType.createOrder,
  data: {'order': orderData},
  timestamp: DateTime.now(),
);

await storageService.enqueueSyncOperation(syncOp);
await getIt<SyncManager>().syncNow(); // Trigger immediate sync if online
```

### Navigation

```dart
// Navigate to route
Routes.navigateTo(context, Routes.orderScreen);

// Navigate with arguments
Routes.navigateTo(context, Routes.scannerScreen, arguments: {'mode': 'rapid'});

// Replace current route
Routes.replaceWith(context, Routes.splashScreen);

// Go back
Routes.goBack(context);
```

## Configuration & Constants

### Key Files
- `lib/config/constants.dart`: All SharedPreferences keys, SecureStorage keys, Hive box names
- `lib/config/routes.dart`: Route definitions and navigation helpers
- `lib/app.dart`: Material theme configuration (red #E53935 primary color)

### Settings Keys (constants.dart)
- API Configuration: Stored in FlutterSecureStorage (api_url, jwt_access_token, jwt_refresh_token, mypos_api_key)
- User Preferences: Stored in SharedPreferences (connection_mode, manual_scan_mode_enabled, offline_mode_enabled, default_tax_rate)
- Device ID: Stored in FlutterSecureStorage (device_uuid)

## Testing

Currently no test suite exists. To add tests:
```bash
# Run tests
flutter test

# Run specific test file
flutter test test/models/product_test.dart

# Run with coverage
flutter test --coverage
```

## Project Structure

```
my_pos_app/
├── lib/
│   ├── main.dart                    # Entry point: Hive init, MultiProvider setup
│   ├── app.dart                     # MaterialApp with theming
│   ├── locator.dart                 # GetIt dependency injection setup
│   ├── config/                      # Configuration files
│   │   ├── constants.dart           # Keys for SharedPreferences/SecureStorage/Hive
│   │   └── routes.dart              # Named routes and navigation helpers
│   ├── models/                      # Hive models with @HiveType annotations
│   ├── screens/                     # UI pages (scanner, order, inventory, settings, etc.)
│   ├── providers/                   # State management (ChangeNotifier)
│   ├── services/                    # Business logic (API, storage, sync, connectivity)
│   ├── repositories/                # Data access layer (product, order, inventory)
│   ├── widgets/                     # Reusable UI components
│   └── utils/                       # Utility functions (PDF, TSPL, timers)
├── assets/
│   ├── animations/                  # Lottie JSON files
│   └── fonts/                       # Roboto font family
├── android/                         # Android native code
├── ios/                             # iOS native code
└── pubspec.yaml                     # Dependencies and asset configuration
```

## Important Notes

- **Language:** UI and error messages are in Spanish (es_CR locale)
- **Default Tax Rate:** 13% (0.13) - Costa Rica IVA
- **Authentication:** JWT-based with access + refresh token rotation
- **Offline Support:** All features work offline; changes sync when online
- **Background Service:** Runs in separate isolate for non-blocking sync
- **Barcode Formats:** Supports all standard formats via mobile_scanner
- **Thermal Printing:** ESC-POS command generation for thermal label printers
- **Code Generation:** Required for Hive adapters - always run after model changes

## Common Issues

1. **Build errors after model changes:** Run `flutter pub run build_runner build --delete-conflicting-outputs`
2. **Service not found in GetIt:** Ensure `setupLocator()` called in `main.dart` and awaited before app starts
3. **Hive adapter errors:** Check that adapter type IDs are unique and registered in `registerHiveAdapters()`
4. **Sync not working:** Verify `SyncManager` is initialized and `startPeriodicSync()` called in `AppStateProvider.initialize()`
5. **API 401 errors:** Token refresh should be automatic; check FlutterSecureStorage has valid jwt_refresh_token

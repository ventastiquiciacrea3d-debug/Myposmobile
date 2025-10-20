// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_pos_mobile_barcode/models/product.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'models/order.dart';
import 'models/inventory_movement.dart';
import 'models/label_print_item.dart';
import 'models/inventory_adjustment_cache.dart';
import 'models/sync_operation.dart';
import 'providers/scanner_provider.dart';
import 'providers/order_provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/label_provider.dart';
import 'locator.dart';
import 'config/constants.dart';
import 'services/background_service.dart';

Product parseProductJsonInBackground(String jsonString) {
  final Map<String, dynamic> jsonMap = json.decode(jsonString);
  return Product.fromJson(jsonMap);
}

class ErrorMaterialApp extends StatelessWidget {
  final Object error;
  const ErrorMaterialApp({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "Error Crítico al Iniciar:\n\n$error\n\nPor favor, reinicia la aplicación.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("[MAIN_INIT] Starting application initialization...");

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await initializeDateFormatting('es_CR', null);
    Intl.defaultLocale = 'es_CR';
  } catch (_) {
    await initializeDateFormatting('es', null);
    Intl.defaultLocale = 'es';
  }

  try {
    final appDocumentDirectory = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDirectory.path);
    registerHiveAdapters();

    await Hive.openBox(hiveSettingsBoxName);
    await Hive.openBox<Product>(hiveProductsBoxName);
    await Hive.openBox<List<String>>(hiveBarcodeIndexBoxName);
    await Hive.openBox<Order>(hiveOrdersBoxName);
    await Hive.openBox<Order>(hivePendingOrdersBoxName);
    await Hive.openBox<LabelPrintItem>(hiveLabelQueueBoxName);
    await Hive.openBox<InventoryAdjustmentCache>(hiveInventoryAdjustmentCacheBoxName);
    await Hive.openBox<SyncOperation>(hiveSyncQueueBoxName);
    await Hive.openBox<InventoryMovement>(hiveInventoryMovementsBoxName);

    await setupLocator();

    final backgroundService = AppBackgroundService();
    await backgroundService.initializeService();

    runApp(const CoreApp());

  } catch (e, stacktrace) {
    debugPrint("!! FATAL ERROR during main initialization: $e\n$stacktrace");
    runApp(ErrorMaterialApp(error: e));
  }
}

class CoreApp extends StatelessWidget {
  const CoreApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => LabelProvider()),
        ChangeNotifierProvider(create: (context) => OrderProvider(sharedPreferences: getIt<SharedPreferences>())),
        ChangeNotifierProvider(create: (context) => InventoryProvider(sharedPreferences: getIt<SharedPreferences>())),
        ChangeNotifierProvider(create: (context) => ScannerProvider(sharedPreferences: getIt<SharedPreferences>())),
        ChangeNotifierProxyProvider2<OrderProvider, LabelProvider, AppStateProvider>(
          create: (context) => AppStateProvider(
            orderProvider: context.read<OrderProvider>(),
            labelProvider: context.read<LabelProvider>(),
          ),
          update: (_, orderProvider, labelProvider, previous) =>
          previous ?? AppStateProvider(orderProvider: orderProvider, labelProvider: labelProvider),
        ),
      ],
      child: const MyPosApp(),
    );
  }
}
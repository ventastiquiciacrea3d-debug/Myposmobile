// lib/config/routes.dart
import 'package:flutter/material.dart';
import '../screens/inventory_adjustment_form_screen.dart';
import '../screens/inventory_csv_import_screen.dart';
import '../models/label_print_item.dart';
import '../screens/customer_edit_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/label_printing_screen.dart';
import '../screens/label_settings_screen.dart';
import '../screens/order_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/thermal_printing_screen.dart';
// --- INICIO DE CORRECCIÓN ---
import '../screens/customer_search_screen.dart'; // Importar la nueva pantalla
// --- FIN DE CORRECCIÓN ---


class Routes {
  static const String splash = '/';
  static const String scanner = '/scanner';
  static const String order = '/order';
  static const String settings = '/settings';
  static const String customerEdit = '/customer/edit';
  // --- INICIO DE CORRECCIÓN ---
  static const String customerSearch = '/customer/search'; // Añadir la nueva ruta
  // --- FIN DE CORRECCIÓN ---
  static const String inventory = '/inventory';
  static const String inventoryAdjustmentForm = '/inventory/adjustment/form';
  static const String inventoryCsvImport = '/inventory/import/csv';
  static const String labelPrinting = '/labels/print';
  static const String labelSettings = '/labels/settings';
  static const String thermalPrinting = '/labels/thermal_print';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const SplashScreen(),
      scanner: (context) => const ScannerScreen(),
      order: (context) => const OrderScreen(),
      settings: (context) => const SettingsScreen(),
      customerEdit: (context) => const CustomerEditScreen(),
      // --- INICIO DE CORRECCIÓN ---
      customerSearch: (context) => const CustomerSearchScreen(), // Registrar la nueva ruta
      // --- FIN DE CORRECCIÓN ---
      inventory: (context) => const InventoryScreen(),
      labelPrinting: (context) => const LabelPrintingScreen(),
      labelSettings: (context) => const LabelSettingsScreen(),
      inventoryCsvImport: (context) => const InventoryCsvImportScreen(),
      thermalPrinting: (context) {
        final printQueue = ModalRoute.of(context)!.settings.arguments as List<LabelPrintItem>;
        return ThermalPrintingScreen(printQueue: printQueue);
      },
      inventoryAdjustmentForm: (context) {
        final args = ModalRoute.of(context)?.settings.arguments as InventoryAdjustmentFormScreenArguments?;
        return InventoryAdjustmentFormScreen(arguments: args);
      },
    };
  }

  static Future<T?> navigateTo<T extends Object?>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
  }

  static Future<T?> replaceWith<T extends Object?, TO extends Object?>(BuildContext context, String routeName, {TO? result, Object? arguments}) {
    return Navigator.pushReplacementNamed<T, TO>(context, routeName, arguments: arguments, result: result);
  }

  static void goBack<T extends Object?>(BuildContext context, [ T? result ]) {
    if (Navigator.canPop(context)) {
      Navigator.pop<T>(context, result);
    }
  }
}
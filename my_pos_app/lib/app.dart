// lib/app.dart
import 'package:flutter/material.dart';
import 'config/routes.dart'; // Importa la configuración de rutas de la aplicación.
import 'services/background_service.dart';

// MyPosApp es el widget raíz de la aplicación.
class MyPosApp extends StatelessWidget {
  const MyPosApp({super.key});

  /// ✓ CORRECCIÓN: Inicializar background service DESPUÉS del splash
  /// Se ejecuta en el main isolate una sola vez después de la primera navegación
  static Future<void> initializeBackgroundServicePostSplash() async {
    try {
      debugPrint("[MyPosApp] Initializing background service post-splash...");
      final backgroundService = AppBackgroundService();
      await backgroundService.initializeService();
      debugPrint("[MyPosApp] Background service initialized successfully");
    } catch (e) {
      debugPrint("[MyPosApp] Warning: Background service initialization failed: $e");
      // No es crítico, la app puede funcionar sin el background service
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define el tema claro para la aplicación.
    final lightTheme = ThemeData(
      primarySwatch: Colors.red,
      primaryColor: const Color(0xFFE53935),
      scaffoldBackgroundColor: Colors.grey[100],
      cardColor: Colors.white,

      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFE53935),
        foregroundColor: Colors.white,
        elevation: 1,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          fontFamily: 'Roboto',
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE53935),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE53935),
          disabledForegroundColor: Colors.grey.shade400,
          side: const BorderSide(color: Color(0xFFE53935)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE53935), width: 2), ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: Colors.white,
      ),

      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom( foregroundColor: const Color(0xFFE53935) )
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey.shade200;
          }
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFE53935);
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey.shade300;
          }
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFE53935).withOpacity(0.5);
          }
          return Colors.grey.shade400;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey.shade300.withOpacity(0.5);
          }
          return Colors.transparent;
        }),
      ),

      chipTheme: ChipThemeData(
          selectedColor: const Color(0xFFE53935).withOpacity(0.15),
          labelStyle: const TextStyle(fontSize: 13, color: Colors.black87),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: Colors.grey.shade300)
      ),

      colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.red)
          .copyWith(secondary: Colors.redAccent, surface: Colors.grey.shade100),
    );

    return MaterialApp(
      title: 'MY POS MOBILE BARCODE',
      theme: lightTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: Routes.splash,
      routes: Routes.getRoutes(),
    );
  }
}

// lib/services/screen_state_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Servicio de Detección de Estado de Pantalla
///
/// Detecta cuando la pantalla está apagada/encendida/desbloqueada
/// para pausar/reanudar polling automáticamente.
///
/// Ahorro de batería: Pausa polling cuando pantalla está apagada
///
/// NOTA: Flutter no tiene API nativa para esto. Este servicio usa
/// una aproximación con WidgetsBindingObserver que detecta cuando
/// la app pasa a background (similar a pantalla apagada en términos
/// de ahorro de batería).
///
/// Para detección real de pantalla, se necesitaría plugin nativo:
/// - Android: PowerManager
/// - iOS: UIScreen.mainScreen.brightness
class ScreenStateService with WidgetsBindingObserver {
  // Estados
  bool _isScreenOn = true;
  bool _isAppInForeground = true;

  // Callbacks
  final Function()? onScreenOff;
  final Function()? onScreenOn;
  final Function()? onScreenUnlocked;

  // Stream controller para emitir eventos
  final StreamController<ScreenState> _stateController =
      StreamController<ScreenState>.broadcast();

  Stream<ScreenState> get stateStream => _stateController.stream;

  // Getters
  bool get isScreenOn => _isScreenOn;
  bool get isAppInForeground => _isAppInForeground;

  ScreenStateService({
    this.onScreenOff,
    this.onScreenOn,
    this.onScreenUnlocked,
  });

  /// Inicializar servicio
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[ScreenState] Service initialized');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('[ScreenState] App lifecycle changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App en primer plano = pantalla encendida y desbloqueada
        _isScreenOn = true;
        _isAppInForeground = true;

        _stateController.add(ScreenState.screenUnlocked);
        onScreenUnlocked?.call();

        debugPrint('[ScreenState] ✅ Screen UNLOCKED - enabling polling');
        break;

      case AppLifecycleState.inactive:
        // App en transición (ej: selector de apps, notificación)
        // Consideramos pantalla aún encendida pero app no activa
        _isAppInForeground = false;
        debugPrint('[ScreenState] ⏸️ App INACTIVE');
        break;

      case AppLifecycleState.paused:
        // App en background = pantalla puede estar apagada o usuario en otra app
        _isScreenOn = false;
        _isAppInForeground = false;

        _stateController.add(ScreenState.screenOff);
        onScreenOff?.call();

        debugPrint('[ScreenState] 🔴 Screen OFF (or app background) - pausing polling');
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App siendo destruida o oculta
        _isScreenOn = false;
        _isAppInForeground = false;
        debugPrint('[ScreenState] App DETACHED/HIDDEN');
        break;
    }
  }

  /// Obtener estado actual
  ScreenState getCurrentState() {
    if (_isAppInForeground && _isScreenOn) {
      return ScreenState.screenUnlocked;
    } else if (_isScreenOn && !_isAppInForeground) {
      return ScreenState.screenOn;
    } else {
      return ScreenState.screenOff;
    }
  }

  /// Simular evento de pantalla encendida (para testing)
  void simulateScreenOn() {
    _isScreenOn = true;
    _stateController.add(ScreenState.screenOn);
    onScreenOn?.call();
    debugPrint('[ScreenState] [SIMULATED] Screen ON');
  }

  /// Simular evento de pantalla apagada (para testing)
  void simulateScreenOff() {
    _isScreenOn = false;
    _stateController.add(ScreenState.screenOff);
    onScreenOff?.call();
    debugPrint('[ScreenState] [SIMULATED] Screen OFF');
  }

  /// Obtener estadísticas
  Map<String, dynamic> getStats() {
    return {
      'is_screen_on': _isScreenOn,
      'is_app_foreground': _isAppInForeground,
      'current_state': getCurrentState().name,
    };
  }

  /// Limpiar recursos
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateController.close();
    debugPrint('[ScreenState] Service disposed');
  }
}

/// Estados de pantalla
enum ScreenState {
  screenOff,      // Pantalla apagada o app en background
  screenOn,       // Pantalla encendida pero app no activa
  screenUnlocked, // Pantalla desbloqueada y app activa
}

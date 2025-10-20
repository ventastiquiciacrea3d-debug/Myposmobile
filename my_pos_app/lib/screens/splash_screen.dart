// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../providers/app_state_provider.dart';
import '../config/routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _navigationDone = false;
  AppStateProvider? _appStateProvider;

  @override
  void initState() {
    super.initState();
    debugPrint("[SplashScreen] initState");

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();

    // La inicialización se dispara después de que el primer frame se haya renderizado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _appStateProvider = context.read<AppStateProvider>();
        _appStateProvider!.addListener(_onAppStateChange);
        _onAppStateChange(); // Llama una vez para comprobar el estado inicial.
      }
    });
  }

  void _onAppStateChange() {
    if (!mounted || _navigationDone || _appStateProvider == null) return;

    // Navega solo cuando el AppStateProvider ya no esté cargando.
    if (!_appStateProvider!.isLoading) {
      _navigationDone = true;
      _appStateProvider!.removeListener(_onAppStateChange);

      // Pequeño retraso para que la animación de entrada termine.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          final route = _appStateProvider!.isAppConfigured ? Routes.scanner : Routes.settings;
          debugPrint("[SplashScreen] Navigation to $route");
          Navigator.of(context).pushReplacementNamed(route);
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    try {
      _appStateProvider?.removeListener(_onAppStateChange);
    } catch (e) {
      debugPrint("[SplashScreen] Could not remove listener on dispose: $e");
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE53935), Color(0xFFC62828)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5), ), ],
                ),
                child: const Center(
                  child: Text(
                    "POS",
                    style: TextStyle( fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFFE53935), ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "MY POS MOBILE BARCODE",
                style: TextStyle( fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Punto de Venta Móvil para WooCommerce",
                style: TextStyle( fontSize: 14, color: Colors.white70, ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Consumer<AppStateProvider>(
                    builder: (context, appState, _) => Text(
                        appState.isLoading ? "Inicializando servicios..." : (appState.isAppConfigured ? "Configurado" : "No configurado"),
                        style: const TextStyle(color: Colors.white70, fontSize: 10)
                    ),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}
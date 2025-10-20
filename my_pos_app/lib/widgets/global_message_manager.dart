// lib/widgets/global_message_manager.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

class GlobalMessageManager extends StatefulWidget {
  final Widget child;
  const GlobalMessageManager({Key? key, required this.child}) : super(key: key);

  @override
  State<GlobalMessageManager> createState() => _GlobalMessageManagerState();
}

class _GlobalMessageManagerState extends State<GlobalMessageManager> {
  @override
  void initState() {
    super.initState();
    // Escuchar cambios sin necesidad de un Consumer en el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppStateProvider>().addListener(_showMessages);
      }
    });
  }

  @override
  void dispose() {
    if (mounted) {
      context.read<AppStateProvider>().removeListener(_showMessages);
    }
    super.dispose();
  }

  void _showMessages() {
    final appState = context.read<AppStateProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Ocultar banner actual antes de mostrar uno nuevo para evitar solapamientos
    scaffoldMessenger.hideCurrentMaterialBanner();

    if (appState.error != null) {
      scaffoldMessenger.showMaterialBanner(
        MaterialBanner(
          padding: const EdgeInsets.all(10),
          content: Text(appState.error!, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade700,
          actions: [
            TextButton(
              child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                scaffoldMessenger.hideCurrentMaterialBanner();
                appState.clearError();
              },
            ),
          ],
        ),
      );
    } else if (appState.notification != null) {
      // Puedes usar SnackBar para notificaciones menos intrusivas
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(appState.notification!),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () => scaffoldMessenger.hideCurrentSnackBar(),
          ),
        ),
      );
      // Limpiar la notificación después de mostrarla para que no reaparezca
      appState.clearNotification();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
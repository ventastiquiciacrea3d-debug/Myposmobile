// lib/widgets/global_message_manager.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state_notifier.dart';
import '../providers/app_state.dart';

/// ✓ FASE 2 RIVERPOD: Migrado a ConsumerStatefulWidget
class GlobalMessageManager extends ConsumerStatefulWidget {
  final Widget child;
  const GlobalMessageManager({super.key, required this.child});

  @override
  ConsumerState<GlobalMessageManager> createState() => _GlobalMessageManagerState();
}

class _GlobalMessageManagerState extends ConsumerState<GlobalMessageManager> {
  @override
  void initState() {
    super.initState();
    // Escuchar cambios sin necesidad de un Consumer en el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.listenManual(appStateNotifierProvider, (previous, next) {
          _showMessages(next);
        });
      }
    });
  }

  void _showMessages(AppState appState) {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Ocultar banner actual antes de mostrar uno nuevo para evitar solapamientos
    scaffoldMessenger.hideCurrentMaterialBanner();

    if (appState.appError != null) {
      scaffoldMessenger.showMaterialBanner(
        MaterialBanner(
          padding: const EdgeInsets.all(10),
          content: Text(appState.appError!, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade700,
          actions: [
            TextButton(
              child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                scaffoldMessenger.hideCurrentMaterialBanner();
                ref.read(appStateNotifierProvider.notifier).clearError();
              },
            ),
          ],
        ),
      );
    } else if (appState.appNotification != null) {
      // Puedes usar SnackBar para notificaciones menos intrusivas
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(appState.appNotification!),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () => scaffoldMessenger.hideCurrentSnackBar(),
          ),
        ),
      );
      // Limpiar la notificación después de mostrarla para que no reaparezca
      ref.read(appStateNotifierProvider.notifier).clearNotification();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
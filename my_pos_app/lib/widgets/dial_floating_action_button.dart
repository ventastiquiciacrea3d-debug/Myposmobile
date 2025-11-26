// lib/widgets/dial_floating_action_button.dart
import 'package:flutter/material.dart';
import '../config/routes.dart';

/// ✓ SOLUCIÓN SIMPLIFICADA: FloatingActionButton estándar con ModalBottomSheet
/// Reemplaza el widget complejo con animaciones CustomPaint por una solución simple
class DialFloatingActionButton extends StatelessWidget {
  const DialFloatingActionButton({super.key});

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text(
                    'Acciones Rápidas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
                // Options
                _buildOption(
                  context,
                  icon: Icons.inventory_2_outlined,
                  label: 'Inventario',
                  subtitle: 'Gestionar stock y movimientos',
                  onTap: () {
                    Navigator.pop(context);
                    Routes.navigateTo(context, Routes.inventory);
                  },
                ),
                _buildOption(
                  context,
                  icon: Icons.print,
                  label: 'Etiquetas',
                  subtitle: 'Imprimir etiquetas de productos',
                  onTap: () {
                    Navigator.pop(context);
                    Routes.navigateTo(context, Routes.labelPrinting);
                  },
                ),
                _buildOption(
                  context,
                  icon: Icons.settings_outlined,
                  label: 'Ajustes',
                  subtitle: 'Configuración de la aplicación',
                  onTap: () {
                    Navigator.pop(context);
                    Routes.navigateTo(context, Routes.settings);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFE53935),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: const Color(0xFFE53935),
      foregroundColor: Colors.white,
      elevation: 6.0,
      shape: const CircleBorder(),
      onPressed: () => _showOptionsBottomSheet(context),
      child: const Icon(
        Icons.menu,
        size: 28,
      ),
    );
  }
}
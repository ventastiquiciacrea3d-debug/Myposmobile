// lib/widgets/bottom_navigation.dart
import 'package:flutter/material.dart';
import '../config/routes.dart'; // Importar Routes para la navegación

class BottomNavigation extends StatelessWidget {
  final int currentIndex; // El índice de la pestaña actualmente seleccionada
  final Function(int) onTap; // Callback cuando se toca un ítem
  final bool centerFabExists; // Indica si hay un FAB central para ajustar layout

  const BottomNavigation({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.centerFabExists = false, // Por defecto no hay FAB, las pantallas lo activarán
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Lista de BottomNavigationBarItems
    // Ajustada para tener "Código" y "Pedidos".
    // Los otros ítems (Productos, Inventario, Ajustes) se accederán desde el FAB.
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.qr_code_scanner),
        label: 'CÓDIGO',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'PEDIDOS',
      ),
    ];

    // Si hay un FAB central, necesitamos añadir un placeholder o ajustar los ítems
    // para que el espacio del FAB no se solape con un ítem activo.
    // Una forma es añadir un ítem "invisible" o simplemente reorganizar
    // la lógica de los índices en las pantallas que usan esto con un FAB.

    // Para una BottomAppBar con notch, a menudo se distribuyen los ítems
    // a cada lado del notch. Con solo 2 ítems, esto es más simple.

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey.shade600,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      items: items,
      // Si quisieras un espacio explícito para el FAB, podrías hacer algo como:
      // items: centerFabExists
      //     ? [
      //         items[0], // Código
      //         const BottomNavigationBarItem(label: '', icon: SizedBox.shrink()), // Placeholder para el FAB
      //         items[1], // Pedidos
      //       ]
      //     : items,
      // pero esto requiere que el currentIndex y onTap manejen el índice del placeholder.
      // Es más común usar una BottomAppBar con Row y distribuir los botones manualmente.
      // Sin embargo, para mantener BottomNavigationBar, el FAB simplemente se superpondrá.
    );
  }
}
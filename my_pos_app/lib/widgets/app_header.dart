// lib/widgets/app_header.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/order_provider.dart';
import '../config/routes.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showSearchButton;
  final bool showSettingsButton;
  final bool showCartButton;
  final VoidCallback? onCartPressed;
  final VoidCallback? onSettingsPressed;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final PreferredSizeWidget? bottom;

  const AppHeader({
    Key? key,
    required this.title,
    this.showSearchButton = false,
    this.showSettingsButton = true,
    this.showCartButton = true,
    this.onCartPressed,
    this.onSettingsPressed,
    this.onBackPressed,
    this.showBackButton = false,
    this.bottom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // --- INICIO DE LA CORRECCIÓN ---
      automaticallyImplyLeading: false, // Evita que Flutter añada un botón de retroceso automáticamente
      leading: showBackButton
          ? IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Volver',
        onPressed: onBackPressed ?? () => Routes.goBack(context),
      )
          : null,
      // --- FIN DE LA CORRECCIÓN ---
      title: Text(title),
      centerTitle: true,
      actions: [
        if (showSearchButton)
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar',
            onPressed: () { /* Lógica de búsqueda */ },
          ),
        if (showCartButton)
          Selector<OrderProvider, int>(
            selector: (_, provider) => provider.currentOrder?.items.length ?? 0,
            builder: (context, itemCount, child) {
              return IconButton(
                icon: Badge(
                  label: Text(itemCount.toString()),
                  isLabelVisible: itemCount > 0,
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                tooltip: 'Ver Pedido Actual',
                onPressed: onCartPressed ?? () => Routes.navigateTo(context, Routes.order),
              );
            },
          ),
        if (showSettingsButton)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración',
            onPressed: onSettingsPressed ?? () => Routes.navigateTo(context, Routes.settings),
          ),
        const SizedBox(width: 8),
      ],
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}
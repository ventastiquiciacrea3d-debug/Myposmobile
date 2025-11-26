// lib/widgets/app_header.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/order_notifier.dart';
import '../config/routes.dart';

class AppHeader extends ConsumerWidget implements PreferredSizeWidget {
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
    super.key,
    required this.title,
    this.showSearchButton = false,
    this.showSettingsButton = true,
    this.showCartButton = true,
    this.onCartPressed,
    this.onSettingsPressed,
    this.onBackPressed,
    this.showBackButton = false,
    this.bottom,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Consumer(
            builder: (context, ref, child) {
              final orderState = ref.watch(currentOrderProvider);
              final itemCount = orderState.when(
                data: (state) => state.order?.items.length ?? 0,
                loading: () => 0,
                error: (_, __) => 0,
              );

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
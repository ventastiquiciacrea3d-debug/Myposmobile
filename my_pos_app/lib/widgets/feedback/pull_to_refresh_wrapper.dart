// lib/widgets/feedback/pull_to_refresh_wrapper.dart
import 'package:flutter/material.dart';

/// ✓ PROPUESTA 7: Pull-to-refresh wrapper con feedback visual mejorado
class PullToRefreshWrapper extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final String refreshingMessage;
  final Color? color;

  const PullToRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
    this.refreshingMessage = "Actualizando...",
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color ?? Theme.of(context).primaryColor,
      backgroundColor: Colors.white,
      strokeWidth: 3.0,
      displacement: 40.0,
      // Custom refresh indicator con mensaje
      child: Stack(
        children: [
          child,
          // Mensaje de "Actualizando" opcional
          // (Se puede mejorar con un overlay personalizado)
        ],
      ),
    );
  }
}

/// Pull-to-refresh para ListView
class RefreshableListView extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function() onRefresh;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  const RefreshableListView({
    super.key,
    required this.children,
    required this.onRefresh,
    this.padding,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return PullToRefreshWrapper(
      onRefresh: onRefresh,
      child: ListView(
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }
}

/// Pull-to-refresh para ListView.builder
class RefreshableListBuilder extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final Future<void> Function() onRefresh;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final Widget? emptyState;

  const RefreshableListBuilder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onRefresh,
    this.padding,
    this.physics,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    // Si no hay items y hay empty state, mostrarlo
    if (itemCount == 0 && emptyState != null) {
      return PullToRefreshWrapper(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: emptyState,
          ),
        ),
      );
    }

    return PullToRefreshWrapper(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
      ),
    );
  }
}

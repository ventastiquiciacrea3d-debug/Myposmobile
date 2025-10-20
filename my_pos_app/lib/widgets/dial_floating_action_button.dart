// lib/widgets/dial_floating_action_button.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/routes.dart';

class DialFloatingActionButton extends StatefulWidget {
  const DialFloatingActionButton({Key? key}) : super(key: key);

  @override
  State<DialFloatingActionButton> createState() => _DialFloatingActionButtonState();
}

class _DialFloatingActionButtonState extends State<DialFloatingActionButton>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  late Animation<double> _scaleMenuItemsAnimation;
  late Animation<Color?> _fabBackgroundColorAnimation;
  late Animation<Color?> _fabIconColorAnimation;

  int? _hoveredItemIndex;
  final GlobalKey _fabKey = GlobalKey();

  final Color _fabClosedBackgroundColor = Colors.red;
  final Color _fabOpenBackgroundColor = Colors.white;
  final Color _fabClosedIconColor = Colors.white;
  final Color _fabOpenIconColor = Colors.red;

  final Color _expandingMenuBackgroundColor = Colors.red.withOpacity(0.95);

  final double _expandingBackgroundFinalRadius = 85.0;
  final double _menuItemsOrbitRadius = 60.0;
  final double _menuItemIconSize = 22.0;
  final double _menuItemTapTargetSize = 48.0;
  final double _menuItemLabelHeight = 20.0;

  final List<Map<String, dynamic>> _menuItems = [
    {'icon': Icons.settings_outlined, 'label': 'Ajustes', 'route': Routes.settings, 'message': null},
    {'icon': Icons.inventory_2_outlined, 'label': 'Inventario', 'route': Routes.inventory, 'message': null},
    {'icon': Icons.print, 'label': 'Etiquetas', 'route': Routes.labelPrinting, 'message': null},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animationController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (mounted && _hoveredItemIndex != null) {
          setState(() {
            _hoveredItemIndex = null;
          });
        }
      }
    });

    _progressAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _scaleMenuItemsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
      ),
    );

    _fabBackgroundColorAnimation = ColorTween(
      begin: _fabClosedBackgroundColor,
      end: _fabOpenBackgroundColor,
    ).animate(CurvedAnimation(parent: _animationController, curve: const Interval(0.0, 0.6)));

    _fabIconColorAnimation = ColorTween(
      begin: _fabClosedIconColor,
      end: _fabOpenIconColor,
    ).animate(CurvedAnimation(parent: _animationController, curve: const Interval(0.0, 0.6)));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!mounted) return;
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
      } else {
        _hoveredItemIndex = null;
        _animationController.reverse();
      }
    });
  }

  double _calculateItemAngle(int index, int totalItems) {
    if (totalItems <= 0) return 0;
    if (totalItems == 1) return -math.pi / 2;
    const double arcSpanDegrees = 135;
    const double arcSpanRadians = arcSpanDegrees * math.pi / 180;
    const double startAngle = (-math.pi / 2) - (arcSpanRadians / 2);
    return startAngle + (index * (arcSpanRadians / (totalItems > 1 ? totalItems - 1 : 1)));
  }

  void _updateHoveredItem(Offset globalPosition) {
    if (!_isOpen || !_animationController.isCompleted) {
      if (mounted && _hoveredItemIndex != null && (_animationController.isAnimating || !_isOpen)) {
        setState(() => _hoveredItemIndex = null);
      }
      return;
    }

    final RenderBox? fabBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (fabBox == null || !fabBox.hasSize) return;

    final Offset fabCenterInGlobal = fabBox.localToGlobal(fabBox.size.center(Offset.zero));
    final Offset localPositionFromFabCenter = globalPosition - fabCenterInGlobal;

    final double touchAngle = math.atan2(localPositionFromFabCenter.dy, localPositionFromFabCenter.dx);
    final double distance = localPositionFromFabCenter.distance;
    int? newHoveredIndex;

    if (distance < _expandingBackgroundFinalRadius * 1.15) {
      double minAngleDiff = double.infinity;
      for (int i = 0; i < _menuItems.length; i++) {
        final double itemAngle = _calculateItemAngle(i, _menuItems.length);
        double diff = touchAngle - itemAngle;
        while (diff <= -math.pi) diff += 2 * math.pi;
        while (diff > math.pi) diff -= 2 * math.pi;

        if (diff.abs() < minAngleDiff) {
          minAngleDiff = diff.abs();
          newHoveredIndex = i;
        }
      }
      if (_menuItems.isNotEmpty && newHoveredIndex != null) {
        final double angleBetweenItems = (_menuItems.length > 1)
            ? ((135 * math.pi / 180) / (_menuItems.length - 1))
            : (2 * math.pi);
        if (minAngleDiff > (angleBetweenItems / 2.0) * 1.25) {
          newHoveredIndex = null;
        }
      } else {
        newHoveredIndex = null;
      }
    } else {
      newHoveredIndex = null;
    }

    if (mounted && _hoveredItemIndex != newHoveredIndex) {
      setState(() => _hoveredItemIndex = newHoveredIndex);
    }
  }

  void _selectAndPerformAction(int? index, BuildContext contextForAction) {
    final bool wasOpen = _isOpen;
    if (_isOpen) _toggleMenu();

    if (index != null && index >= 0 && index < _menuItems.length && wasOpen) {
      final item = _menuItems[index];
      Future.delayed(Duration(milliseconds: (_animationController.duration!.inMilliseconds * 0.5).round()), () {
        if (!mounted) return;
        final route = item['route'] as String?;
        final message = item['message'] as String?;
        if (route != null && route.isNotEmpty) {
          Routes.navigateTo(contextForAction, route);
        } else if (message != null && message.isNotEmpty) {
          ScaffoldMessenger.of(contextForAction).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
          );
        }
      });
    }
  }

  Widget _buildMenuItem({
    required IconData iconData,
    required String label,
    required int index,
    required bool isHovered,
  }) {
    final double itemAngle = _calculateItemAngle(index, _menuItems.length);
    final bool showLabel = isHovered && _isOpen && _animationController.isCompleted;

    final Offset offset = Offset(
      math.cos(itemAngle) * _menuItemsOrbitRadius,
      math.sin(itemAngle) * _menuItemsOrbitRadius,
    );

    return Transform.translate(
      offset: offset,
      child: AnimatedBuilder(
        animation: _scaleMenuItemsAnimation,
        builder: (context, child) {
          final double currentItemScale = _scaleMenuItemsAnimation.value;
          final double clampedOpacity = currentItemScale.clamp(0.0, 1.0);

          if (clampedOpacity < 0.01 && !_isOpen) {
            return const SizedBox.shrink();
          }

          return Opacity(
            opacity: clampedOpacity,
            child: ScaleTransition(
              scale: _scaleMenuItemsAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showLabel)
                    AnimatedOpacity(
                      opacity: _animationController.isCompleted ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 5.0),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 1.5, offset: const Offset(0, 1), )]),
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 10.0, color: Colors.white, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (!showLabel && isHovered && _isOpen && _animationController.isCompleted)
                    SizedBox(height: _menuItemLabelHeight + 5.0),

                  Container(
                    width: _menuItemTapTargetSize,
                    height: _menuItemTapTargetSize,
                    alignment: Alignment.center,
                    child: Icon(
                      iconData,
                      color: Colors.white,
                      size: _menuItemIconSize + (showLabel ? 2 : 0),
                      shadows: const [ Shadow(color: Colors.black38, blurRadius: 2, offset: Offset(0,1)) ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
        AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, child) {
            final currentProgress = _progressAnimation.value;
            if (currentProgress == 0 && !_isOpen) return const SizedBox.shrink();
            return Transform.scale(
              scale: currentProgress,
              child: Opacity(
                opacity: currentProgress.clamp(0.0, 1.0),
                child: Container(
                  width: _expandingBackgroundFinalRadius * 2,
                  height: _expandingBackgroundFinalRadius * 2,
                  decoration: BoxDecoration(
                    color: _expandingMenuBackgroundColor,
                    shape: BoxShape.circle,
                    boxShadow: _isOpen && currentProgress > 0.5 ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12 * currentProgress.clamp(0.0, 1.0)),
                        blurRadius: 6 + (3 * currentProgress.clamp(0.0, 1.0)),
                        spreadRadius: 0.5 + (0.5 * currentProgress.clamp(0.0, 1.0)),
                      )
                    ] : [],
                  ),
                ),
              ),
            );
          },
        ),
        // --- CORRECCIÓN: Se elimina el widget CustomPaint y el painter _PizzaSlicePainter ---
        if (!_animationController.isDismissed || _isOpen)
          SizedBox(
            width: _expandingBackgroundFinalRadius * 2.2,
            height: _expandingBackgroundFinalRadius * 2.2,
            child: GestureDetector(
              onPanStart: (details) { if (_isOpen) _updateHoveredItem(details.globalPosition);},
              onPanUpdate: (details) { if (_isOpen) _updateHoveredItem(details.globalPosition);},
              onPanEnd: (details) { if (_isOpen) _selectAndPerformAction(_hoveredItemIndex, context);},
              onTapUp: (details) {
                if (_isOpen) {
                  _updateHoveredItem(details.globalPosition);
                  _selectAndPerformAction(_hoveredItemIndex, context);
                }
              },
              behavior: HitTestBehavior.deferToChild,
              child: Container(
                color: Colors.transparent,
                child: Stack(
                  alignment: Alignment.center,
                  children: List.generate(_menuItems.length, (index) {
                    final item = _menuItems[index];
                    return _buildMenuItem(
                      iconData: item['icon'] as IconData,
                      label: item['label'] as String,
                      index: index,
                      isHovered: _hoveredItemIndex == index && _isOpen,
                    );
                  }),
                ),
              ),
            ),
          ),
        FloatingActionButton(
          key: _fabKey,
          backgroundColor: _fabBackgroundColorAnimation.value,
          foregroundColor: _fabIconColorAnimation.value,
          elevation: _isOpen ? 2.0 : 6.0,
          shape: const CircleBorder(),
          onPressed: _toggleMenu,
          child: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _animationController,
            size: 28,
          ),
        ),
      ],
    );
  }
}
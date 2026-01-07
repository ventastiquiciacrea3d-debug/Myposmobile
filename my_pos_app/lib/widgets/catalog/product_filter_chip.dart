// lib/widgets/catalog/product_filter_chip.dart
import 'package:flutter/material.dart';

class ProductFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final IconData icon;
  final Color selectedColor;
  final VoidCallback onTap;

  const ProductFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected ? selectedColor : Colors.grey[600],
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? selectedColor : Colors.grey[700],
          ),
        ),
        backgroundColor: isSelected
            ? selectedColor.withOpacity(0.15)
            : Colors.grey[200],
        side: BorderSide(
          color: isSelected
              ? selectedColor.withOpacity(0.6)
              : Colors.grey[400]!,
          width: isSelected ? 1.5 : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelPadding: const EdgeInsets.only(right: 8),
      ),
    );
  }
}

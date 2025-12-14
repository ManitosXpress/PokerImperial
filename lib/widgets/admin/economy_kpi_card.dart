import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compact KPI Card for Economic Intelligence Dashboard
/// 
/// Displays a single key performance indicator with:
/// - Icon
/// - Label
/// - Value
/// - Optional trend indicator
class EconomyKPICard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color iconColor;
  final Color backgroundColor;
  final String? trend; // e.g., "+12%", "-5%"
  final bool isPercentage;
  final bool isCurrency;

  const EconomyKPICard({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = const Color(0xFF00FFC3),
    this.backgroundColor = const Color(0xFF1A1F2E),
    this.trend,
    this.isPercentage = false,
    this.isCurrency = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0', 'en_US');
    
    String displayValue;
    if (isCurrency) {
      displayValue = '\$${formatter.format(value)}';
    } else if (isPercentage) {
      displayValue = '${value.toStringAsFixed(1)}%';
    } else {
      displayValue = formatter.format(value);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon and trend row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              if (trend != null) _buildTrendIndicator(trend!),
            ],
          ),
          const SizedBox(height: 12),
          
          // Label
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          
          // Value
          Text(
            displayValue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(String trend) {
    final isPositive = trend.startsWith('+');
    final color = isPositive ? Colors.greenAccent : Colors.redAccent;
    final icon = isPositive ? Icons.trending_up : Icons.trending_down;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            trend,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

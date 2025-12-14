import 'package:flutter/material.dart';

class EconomicKPIs extends StatelessWidget {
  final double volume24h;
  final int turnover24h;
  final double ggr24h;

  const EconomicKPIs({
    super.key,
    required this.volume24h,
    required this.turnover24h,
    required this.ggr24h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          _buildKpiCard(
            title: 'Volumen (24h)',
            value: '\$${volume24h.toStringAsFixed(0)}',
            icon: Icons.show_chart,
            color: Colors.cyan,
            subtitle: 'Fichas apostadas',
          ),
          const SizedBox(width: 16),
          _buildKpiCard(
            title: 'Turnover (24h)',
            value: turnover24h.toString(),
            icon: Icons.loop,
            color: Colors.purpleAccent,
            subtitle: 'Manos jugadas',
          ),
          const SizedBox(width: 16),
          _buildKpiCard(
            title: 'GGR (Hoy)',
            value: '\$${ggr24h.toStringAsFixed(0)}',
            icon: Icons.local_fire_department,
            color: Colors.orangeAccent,
            subtitle: 'Rake Bruto',
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

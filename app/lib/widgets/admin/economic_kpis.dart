import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../imperial_currency.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Expanded(
            child: _buildImperialKpiCard(
              title: 'VOLUMEN (24h)',
              valueWidget: ImperialCurrency(
                amount: volume24h,
                style: GoogleFonts.outfit(
                  color: const Color(0xFFFFD700),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                iconSize: 20,
              ),
              icon: Icons.bar_chart,
              borderColor: const Color(0xFFFFD700),
              subtitle: 'Fichas apostadas',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildImperialKpiCard(
              title: 'TURNOVER (24h)',
              valueWidget: Text(
                turnover24h.toString(),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              icon: Icons.loop,
              borderColor: Colors.blueAccent, // Secondary metric
              subtitle: 'Manos jugadas',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildImperialKpiCard(
              title: 'GGR (Hoy)',
              valueWidget: ImperialCurrency(
                amount: ggr24h,
                style: GoogleFonts.outfit(
                  color: const Color(0xFF00FF88),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                iconSize: 20,
              ),
              icon: Icons.local_fire_department,
              borderColor: const Color(0xFF00FF88),
              subtitle: 'Rake Bruto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImperialKpiCard({
    required String title,
    required Widget valueWidget,
    required IconData icon,
    required Color borderColor,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C), // Dark Navy
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title, 
                style: GoogleFonts.outfit(
                  color: Colors.white54, 
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5
                )
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: borderColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          valueWidget,
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

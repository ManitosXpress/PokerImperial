import 'package:flutter/material.dart';

/// CRASH-PROOF: Poker table background layout
/// Purely presentational widget with no null dependencies
class PokerTableLayout extends StatelessWidget {
  final double tableWidth;
  final double tableHeight;
  final bool isMobile;
  final Widget? centerContent; // Optional content (community cards, pot, etc.)

  const PokerTableLayout({
    super.key,
    required this.tableWidth,
    required this.tableHeight,
    this.isMobile = false,
    this.centerContent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tableWidth,
      height: tableHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        border: Border.all(
          color: const Color(0xFF3E2723),
          width: isMobile ? 15 : 25,
        ),
        gradient: const RadialGradient(
          colors: [
            Color(0xFFFFF8E1), // Light center (Spotlight)
            Color(0xFF5D4037), // Darker edge (Vignette)
          ],
          stops: [0.2, 1.0],
          center: Alignment.center,
          radius: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.9),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Racetrack / Inner Line
          Positioned.fill(
            child: Container(
              margin: EdgeInsets.all(isMobile ? 10 : 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(130),
                border: Border.all(
                  color: const Color(0xFF1C1C1C),
                  width: 2,
                ),
              ),
            ),
          ),
          
          // Table Logo (Background)
          Center(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/images/table_logo_imperial.png',
                width: tableWidth * (isMobile ? 0.5 : 0.4),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // CRASH-PROOF: If logo fails to load, show nothing
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          
          // Center content (community cards, pot, etc.)
          if (centerContent != null) centerContent!,
        ],
      ),
    );
  }
}

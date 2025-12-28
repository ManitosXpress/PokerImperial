import 'package:flutter/material.dart';

/// CRASH-PROOF: Displays the pot with full null safety
/// Handles null pot values gracefully
class PotDisplayWidget extends StatelessWidget {
  final int? pot;
  final double tableHeight;

  const PotDisplayWidget({
    super.key,
    this.pot,
    this.tableHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    // SAFETY: Default to 0 if pot is null
    final displayPot = pot ?? 0;

    // Don't show pot if it's 0
    if (displayPot <= 0) {
      return const SizedBox.shrink();
    }

    try {
      return Positioned(
        top: tableHeight * 0.25,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD700).withOpacity(0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'POT',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/coin.png',
                      width: 16,
                      height: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$displayPot',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      // CRASH-PROOF: If rendering fails, show nothing
      print('⚠️ Error rendering pot display: $e');
      return const SizedBox.shrink();
    }
  }
}

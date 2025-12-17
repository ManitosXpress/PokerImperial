import 'package:flutter/material.dart';

class PrizePoolCalculator extends StatelessWidget {
  final double buyIn;
  final int estimatedPlayers;

  const PrizePoolCalculator({
    super.key,
    required this.buyIn,
    required this.estimatedPlayers,
  });

  double get totalPrizePool => buyIn * estimatedPlayers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.2),
            const Color(0xFFCC9900).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 32),
              SizedBox(width: 12),
              Text(
                'Prize Pool Estimado',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '\$${totalPrizePool.toStringAsFixed(0)}',
            style: TextStyle(
              color: const Color(0xFFFFD700),
              fontSize: 48,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: const Color(0xFFFFD700).withOpacity(0.5),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$estimatedPlayers jugadores × \$${buyIn.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

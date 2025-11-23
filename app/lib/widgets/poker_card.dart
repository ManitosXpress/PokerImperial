import 'package:flutter/material.dart';

class PokerCard extends StatelessWidget {
  final String cardCode; // e.g., "Ah", "Kd", "10s"
  final double width;

  const PokerCard({super.key, required this.cardCode, this.width = 60});

  @override
  Widget build(BuildContext context) {
    final rank = cardCode.substring(0, cardCode.length - 1);
    final suit = cardCode.substring(cardCode.length - 1).toUpperCase();
    
    Color color = (suit == 'H' || suit == 'D') ? Colors.red : Colors.black;
    String suitSymbol = '';
    switch (suit) {
      case 'H': suitSymbol = '♥'; break;
      case 'D': suitSymbol = '♦'; break;
      case 'C': suitSymbol = '♣'; break;
      case 'S': suitSymbol = '♠'; break;
    }

    return Container(
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top Left Rank
          Positioned(
            top: 2,
            left: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rank,
                  style: TextStyle(color: color, fontSize: width * 0.35, fontWeight: FontWeight.bold, height: 1),
                ),
                Text(
                  suitSymbol,
                  style: TextStyle(color: color, fontSize: width * 0.25, height: 1),
                ),
              ],
            ),
          ),
          // Center Suit (Large)
          Center(
            child: Text(
              suitSymbol,
              style: TextStyle(color: color, fontSize: width * 0.6, height: 1),
            ),
          ),
          // Bottom Right Rank (Rotated)
          Positioned(
            bottom: 2,
            right: 2,
            child: Transform.rotate(
              angle: 3.14159,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rank,
                    style: TextStyle(color: color, fontSize: width * 0.35, fontWeight: FontWeight.bold, height: 1),
                  ),
                  Text(
                    suitSymbol,
                    style: TextStyle(color: color, fontSize: width * 0.25, height: 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

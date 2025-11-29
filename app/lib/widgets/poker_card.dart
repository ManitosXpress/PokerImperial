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
                  style: TextStyle(color: color, fontSize: width * 0.3, fontWeight: FontWeight.bold, height: 1),
                ),
                Text(
                  suitSymbol,
                  // Much smaller suit icon as requested
                  style: TextStyle(color: color, fontSize: width * 0.15, height: 1),
                ),
              ],
            ),
          ),
          
          // Center Content (Pips or Face)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(width * 0.15),
              child: _buildCenterContent(rank, suitSymbol, color, width),
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
                    style: TextStyle(color: color, fontSize: width * 0.3, fontWeight: FontWeight.bold, height: 1),
                  ),
                  Text(
                    suitSymbol,
                    // Much smaller suit icon as requested
                    style: TextStyle(color: color, fontSize: width * 0.15, height: 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterContent(String rank, String suit, Color color, double width) {
    if (['J', 'Q', 'K'].contains(rank)) {
      return Center(
        child: Text(
          rank, // Placeholder for Face Cards if no assets
          style: TextStyle(color: color.withOpacity(0.2), fontSize: width * 0.8, fontWeight: FontWeight.bold),
        ),
      );
    }
    
    if (rank == 'A') {
       return Center(
        child: Text(
          suit,
          style: TextStyle(color: color, fontSize: width * 0.5, height: 1),
        ),
      );
    }

    int count = int.tryParse(rank) ?? 0;
    if (count == 0) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        double w = constraints.maxWidth;
        double h = constraints.maxHeight;
        // Slightly larger pips
        double pipSize = width * 0.24; 
        
        List<Widget> pips = [];
        
        // Helper to add pip
        void addPip(double x, double y, {bool inverted = false}) {
          pips.add(Positioned(
            left: x * w - (pipSize/2),
            top: y * h - (pipSize/2),
            child: inverted 
              ? Transform.rotate(angle: 3.14159, child: Text(suit, style: TextStyle(color: color, fontSize: pipSize, height: 1)))
              : Text(suit, style: TextStyle(color: color, fontSize: pipSize, height: 1)),
          ));
        }

        // Column positions
        double left = 0.22; // Moved slightly in
        double center = 0.5;
        double right = 0.78; // Moved slightly in
        
        // Row positions - Spread out more
        double top = 0.18;
        double mid = 0.5;
        double bot = 0.82;

        switch (count) {
          case 2:
            addPip(center, top);
            addPip(center, bot, inverted: true);
            break;
          case 3:
            addPip(center, top);
            addPip(center, mid);
            addPip(center, bot, inverted: true);
            break;
          case 4:
            addPip(left, top);
            addPip(right, top);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            break;
          case 5:
            addPip(left, top);
            addPip(right, top);
            addPip(center, mid);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            break;
          case 6:
            addPip(left, top);
            addPip(right, top);
            addPip(left, mid);
            addPip(right, mid);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            break;
          case 7:
            addPip(left, top);
            addPip(right, top);
            addPip(left, mid);
            addPip(right, mid);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            addPip(center, 0.35); // Extra pip
            break;
          case 8:
            addPip(left, top);
            addPip(right, top);
            addPip(left, mid);
            addPip(right, mid);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            addPip(center, 0.33);
            addPip(center, 0.67, inverted: true);
            break;
          case 9:
            addPip(left, top);
            addPip(right, top);
            addPip(left, 0.4); 
            addPip(right, 0.4);
            addPip(left, 0.6, inverted: true);
            addPip(right, 0.6, inverted: true);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            addPip(center, mid);
            break;
          case 10:
            addPip(left, top);
            addPip(right, top);
            addPip(left, 0.38);
            addPip(right, 0.38);
            addPip(left, 0.62, inverted: true);
            addPip(right, 0.62, inverted: true);
            addPip(left, bot, inverted: true);
            addPip(right, bot, inverted: true);
            addPip(center, 0.22);
            addPip(center, 0.78, inverted: true);
            break;
        }
        
        return Stack(children: pips);
      },
    );
  }
}

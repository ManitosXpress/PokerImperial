import 'package:flutter/material.dart';

class ChipStack extends StatelessWidget {
  final int amount;
  final double size;

  const ChipStack({super.key, required this.amount, this.size = 20});

  @override
  Widget build(BuildContext context) {
    // Determine chip colors based on amount (simplified logic)
    // In a real app, you'd break down the amount into denominations
    List<Color> chipColors = [];
    int remaining = amount;
    
    while (remaining > 0) {
      if (remaining >= 100) {
        chipColors.add(Colors.red.shade800);
        remaining -= 100;
      } else if (remaining >= 50) {
        chipColors.add(Colors.blue.shade800);
        remaining -= 50;
      } else if (remaining >= 10) {
        chipColors.add(Colors.green.shade800);
        remaining -= 10;
      } else {
        chipColors.add(Colors.white);
        remaining -= 1;
      }
      if (chipColors.length > 5) break; // Cap visual stack height
    }

    return SizedBox(
      height: size + (chipColors.length * 4),
      width: size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: List.generate(chipColors.length, (index) {
          return Positioned(
            bottom: index * 4.0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chipColors[index],
                border: Border.all(color: Colors.white, width: 2), // Dashed border effect simulated
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: size * 0.6,
                  height: size * 0.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

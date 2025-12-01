import 'package:flutter/material.dart';

class ChipStack extends StatelessWidget {
  final int amount;
  final double size;

  const ChipStack({super.key, required this.amount, this.size = 45});

  @override
  Widget build(BuildContext context) {
    // Use the coin image for all chips
    int chipCount = (amount / 10).ceil(); // Example logic: 1 chip per 10 units, or just show a fixed number based on magnitude
    if (chipCount < 1) chipCount = 1;
    if (chipCount > 5) chipCount = 5; // Cap at 5 chips for visual stack

    return SizedBox(
      height: size + (chipCount * 4),
      width: size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: List.generate(chipCount, (index) {
          return Positioned(
            bottom: index * 4.0,
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/coin.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

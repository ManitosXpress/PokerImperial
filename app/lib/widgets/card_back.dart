import 'package:flutter/material.dart';

class CardBack extends StatelessWidget {
  final double width;
  final double height;

  const CardBack({
    super.key, 
    required this.width, 
    required this.height
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // Dark background
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1), // Gold border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: width * 0.7,
          height: height * 0.7,
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFD4AF37).withOpacity(0.3), 
              width: 1
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Opacity(
              opacity: 0.7,
              child: Image.asset(
                'assets/images/logo_imperial.png',
                width: width * 0.6,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

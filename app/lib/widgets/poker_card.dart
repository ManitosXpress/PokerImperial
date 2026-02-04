import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PokerCard extends StatelessWidget {
  final String? cardCode; // e.g., "Ah", "Kd", "10s", nullable for safety
  final double width;

  const PokerCard({super.key, this.cardCode, this.width = 60});

  @override
  Widget build(BuildContext context) {
    // FIX: Robust image path construction
    String formattedCode = (cardCode ?? '').toLowerCase();
    
    // Fallback if empty
    if (formattedCode.isEmpty || formattedCode == 'null') {
      formattedCode = 'card_back';
    }

    // Construct path
    final String cardPath = 'assets/images/cards/$formattedCode.svg';

    return SvgPicture.asset(
      cardPath,
      width: width,
      // fit: BoxFit.contain, // SVG usually scales well, contain is default-ish behavior for sized box
      placeholderBuilder: (BuildContext context) => SvgPicture.asset(
          'assets/images/cards/card_back.svg',
          width: width,
      ),
    );
  }
}

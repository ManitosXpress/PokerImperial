import 'package:flutter/material.dart';

class PokerCard extends StatelessWidget {
  final String? cardCode; // e.g., "Ah", "Kd", "10s", nullable for safety
  final double width;

  const PokerCard({super.key, this.cardCode, this.width = 60});

  @override
  Widget build(BuildContext context) {
    // Solución Manual para las Imágenes (Flutter)
    // Busca donde renderizas la imagen y asegúrate de tener esto:
    final String cardPath = (cardCode == null || cardCode == "null" || cardCode!.isEmpty)
        ? 'assets/images/cards/card_back.png' // Imagen por defecto
        : 'assets/images/cards/$cardCode.png';

    return Image.asset(
      cardPath,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        'assets/images/cards/card_back.png',
        width: width,
        fit: BoxFit.contain,
      ),
    );
  }
}

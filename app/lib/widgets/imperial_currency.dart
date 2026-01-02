import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ImperialCurrency extends StatelessWidget {
  final dynamic amount; // String, int, or double
  final TextStyle? style;
  final double? iconSize;
  final Color? color;
  final bool isSpaceBetween;

  const ImperialCurrency({
    super.key,
    required this.amount,
    this.style,
    this.iconSize,
    this.color,
    this.isSpaceBetween = true,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the text style to use
    final textStyle = style ?? GoogleFonts.outfit(
      color: color ?? Colors.white,
      fontWeight: FontWeight.bold,
    );

    // Calculate a reasonable icon size based on the text size if not provided
    final double computedIconSize = iconSize ?? (textStyle.fontSize ?? 14.0) * 1.2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/imperial_coin.png',
          width: computedIconSize,
          height: computedIconSize,
          cacheWidth: (computedIconSize * 3).toInt(), // Optimize for Web/Chrome
          fit: BoxFit.contain,
        ),
        if (isSpaceBetween) SizedBox(width: computedIconSize * 0.2), // Small gap relative to size
        Text(
          amount.toString(),
          style: textStyle,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:math' as math;

class CoinStackSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final double width;

  const CoinStackSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.width = 60,
  });

  @override
  State<CoinStackSlider> createState() => _CoinStackSliderState();
}

class _CoinStackSliderState extends State<CoinStackSlider> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double height = constraints.maxHeight;
        // Calculate percentage of the current value
        final double range = widget.max - widget.min;
        final double percentage = range == 0 ? 0 : ((widget.value - widget.min) / range).clamp(0.0, 1.0);
        
        // Coin dimensions
        const double coinSize = 50.0;
        // "Apegalas bien": very tight stack.
        const double effectiveCoinHeight = 4.0; 
        
        // Calculate max coins that can fit visually
        // Total height = (n-1) * effectiveHeight + coinSize
        // n-1 = (Height - coinSize) / effectiveHeight
        // n = ((Height - coinSize) / effectiveHeight) + 1
        
        final int maxCoins = ((height - coinSize) / effectiveCoinHeight).floor() + 1;
        final int numCoins = 1 + ((maxCoins - 1) * percentage).round();
        
        return GestureDetector(
          onVerticalDragUpdate: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final Offset localPos = box.globalToLocal(details.globalPosition);
            
            // Invert Y because slider goes up
            final double normalizedY = 1.0 - (localPos.dy / height).clamp(0.0, 1.0);
            
            final double newValue = widget.min + (normalizedY * range);
            
            widget.onChanged(newValue.clamp(widget.min, widget.max));
          },
          onTapUp: (details) {
             final RenderBox box = context.findRenderObject() as RenderBox;
            final Offset localPos = box.globalToLocal(details.globalPosition);
            final double normalizedY = 1.0 - (localPos.dy / height).clamp(0.0, 1.0);
            final double newValue = widget.min + (normalizedY * range);
            widget.onChanged(newValue.clamp(widget.min, widget.max));
          },
          child: Container(
            width: widget.width,
            color: Colors.transparent, // Hit test target
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Background track (optional, maybe a faint slot?)
                Container(
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // The coins
                ...List.generate(numCoins, (index) {
                  // Position from bottom
                  final double bottom = index * effectiveCoinHeight;
                  
                  return Positioned(
                    bottom: bottom,
                    child: Image.asset(
                      'assets/images/coin.png',
                      width: coinSize,
                      height: coinSize,
                      fit: BoxFit.contain,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../widgets/imperial_currency.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../coin_stack_slider.dart';

class BettingDialog extends StatefulWidget {
  final int currentBet;
  final int myChips;
  final int myCurrentBet;
  final int pot;
  final int minBet;
  final Function(int) onBet;

  const BettingDialog({
    super.key,
    required this.currentBet,
    required this.myChips,
    required this.myCurrentBet,
    required this.pot,
    required this.minBet,
    required this.onBet,
  });

  @override
  State<BettingDialog> createState() => _BettingDialogState();
}

class _BettingDialogState extends State<BettingDialog> {
  late double sliderValue;
  late int maxBet;

  @override
  void initState() {
    super.initState();
    maxBet = widget.myCurrentBet + widget.myChips;
    sliderValue = widget.minBet.toDouble();
  }

  // Quick Action Button (Transparent Black + Gold Border)
  Widget buildOptionButton(String text, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          splashColor: const Color(0xFFFFD700).withOpacity(0.2),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Circular +/- Button (Gradient Gold)
  Widget buildCircleButton(IconData icon, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD700), Color(0xFFB8860B)], // Gold to Dark Gold
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(icon, color: Colors.black87, size: 28),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Dialog(
      backgroundColor: Colors.transparent, // Handle background in Container
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 650),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Color(0xFF2D1414), // Dark Chocolate/Brown
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5), // Gold Border
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Amount Display (LCD Style) ---
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                '${sliderValue.toInt()} \$',
                style: const TextStyle(
                  color: Color(0xFFFFD700), // Gold Text
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto', // Or any monospaced/tech font if available
                  shadows: [
                    Shadow(color: Color(0x88FFD700), blurRadius: 10),
                  ],
                ),
              ),
            ),
            
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Left Column: Controls ---
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Quick Actions
                        buildOptionButton('APOSTAR TODO', () {
                          setState(() => sliderValue = maxBet.toDouble());
                        }),
                        buildOptionButton('BOTE ENTERO', () {
                          double newAmount = widget.pot.toDouble();
                          if (newAmount < widget.minBet) newAmount = widget.minBet.toDouble();
                          if (newAmount > maxBet) newAmount = maxBet.toDouble();
                          setState(() => sliderValue = newAmount);
                        }),
                        buildOptionButton('MEDIO BOTE', () {
                          double newAmount = (widget.pot / 2).toDouble();
                          if (newAmount < widget.minBet) newAmount = widget.minBet.toDouble();
                          if (newAmount > maxBet) newAmount = maxBet.toDouble();
                          setState(() => sliderValue = newAmount);
                        }),
                        
                        const Spacer(),
                        
                        // +/- Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            buildCircleButton(Icons.remove, () {
                              double newVal = sliderValue - 20;
                              if (newVal < widget.minBet) newVal = widget.minBet.toDouble();
                              setState(() => sliderValue = newVal);
                            }),
                            buildCircleButton(Icons.add, () {
                              double newVal = sliderValue + 20;
                              if (newVal > maxBet) newVal = maxBet.toDouble();
                              setState(() => sliderValue = newVal);
                            }),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 24),
                  
                  // --- Right Column: Coin Slider (UNTOUCHED) ---
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        const Text(
                          'Apostar\ntodo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFD700), 
                            fontSize: 10,
                            fontWeight: FontWeight.bold
                          ),
                        ),
                        Expanded(
                          child: CoinStackSlider(
                            value: sliderValue,
                            min: widget.minBet.toDouble(),
                            max: maxBet.toDouble(),
                            onChanged: (value) {
                              setState(() {
                                sliderValue = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Image.asset(
                          'assets/images/bet_slider_icon.png',
                          width: 50,
                          height: 50,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // --- Action Buttons (Cancel / Submit) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Cancel Button (Simple Text)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'CANCELAR', 
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    )
                  ),
                ),
                
                // Submit Button (3D Green Gradient)
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)], // Light Green to Dark Green
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        offset: const Offset(0, 4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onBet(sliderValue.toInt());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Text(
                      languageProvider.getText('raise').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                        shadows: [Shadow(color: Colors.black26, offset: Offset(1, 1), blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

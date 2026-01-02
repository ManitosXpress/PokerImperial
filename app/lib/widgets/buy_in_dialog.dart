import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BuyInDialog extends StatefulWidget {
  final int minBuyIn;
  final int maxBuyIn;
  final int userBalance;
  final Function(int) onJoin;

  const BuyInDialog({
    Key? key,
    required this.minBuyIn,
    required this.maxBuyIn,
    required this.userBalance,
    required this.onJoin,
  }) : super(key: key);

  @override
  _BuyInDialogState createState() => _BuyInDialogState();
}

class _BuyInDialogState extends State<BuyInDialog> {
  late double _currentValue;
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Default to min buy-in, but cap at user balance and max buy-in
    int startVal = widget.minBuyIn;
    if (widget.userBalance < startVal) {
      // User can't even afford min buy-in, logic handled below but setup here
      startVal = widget.userBalance; 
    }
    
    _currentValue = startVal.toDouble();
    _controller.text = startVal.toString();
    
    print('💰 [BuyInDialog] Init. Range: ${widget.minBuyIn}-${widget.maxBuyIn}. Balance: ${widget.userBalance}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final val = int.tryParse(_controller.text);
    
    print('🤔 [BuyInDialog] Validating buy-in: $val');

    if (val == null) {
      setState(() => _errorText = 'Ingrese un número válido');
      return;
    }

    if (val < widget.minBuyIn) {
      setState(() => _errorText = 'El mínimo es ${widget.minBuyIn}');
      return;
    }
    
    if (val > widget.maxBuyIn) {
      setState(() => _errorText = 'El máximo es ${widget.maxBuyIn}');
      return;
    }

    if (val > widget.userBalance) {
      setState(() => _errorText = 'Saldo insuficiente (${widget.userBalance})');
      return;
    }

    print('✅ [BuyInDialog] Valid buy-in: $val. Joining...');
    widget.onJoin(val);
    Navigator.of(context).pop();
  }

  void _updateSlider(double val) {
    setState(() {
      _currentValue = val;
      _controller.text = val.toInt().toString();
      _errorText = null; 
    });
  }

  void _updateText(String val) {
    final num = double.tryParse(val);
    if (num != null) {
      setState(() {
        // Clamp for slider visual only, don't force text change while typing
        if (num >= widget.minBuyIn && num <= widget.maxBuyIn) {
             _currentValue = num;
        }
        _errorText = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color goldColor = Color(0xFFFFD700);
    
    // Effective Max for Slider (cannot exceed actual max or user balance)
    final double sliderMax = (widget.maxBuyIn > widget.userBalance 
        ? widget.userBalance 
        : widget.maxBuyIn).toDouble();
        
    final double sliderMin = widget.minBuyIn.toDouble();
    
    // If user has less than min buy-in, show error state immediately
    final bool canAfford = widget.userBalance >= widget.minBuyIn;

    return Dialog(
      backgroundColor: const Color(0xFF16213E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: goldColor, size: 48),
            const SizedBox(height: 16),
            const Text(
              'BUY-IN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rango de la mesa: \$${widget.minBuyIn} - \$${widget.maxBuyIn}',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            Text(
              'Tu saldo: \$${widget.userBalance}',
              style: TextStyle(color: canAfford ? Colors.greenAccent : Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            
            const SizedBox(height: 32),
            
            if (!canAfford)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: const Text(
                  'No tienes suficientes créditos para entrar a esta mesa.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              )
            else
              Column(
                children: [
                   TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _updateText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: const TextStyle(color: goldColor, fontSize: 32),
                      border: InputBorder.none,
                      errorText: _errorText,
                    ),
                  ),
                  
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: goldColor,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: goldColor.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _currentValue.clamp(sliderMin, sliderMax),
                      min: sliderMin,
                      max: sliderMax,
                      divisions: (sliderMax - sliderMin) > 0 ? (sliderMax - sliderMin) ~/ 10 : 1, // Steps of 10 usually
                      label: _currentValue.toInt().toString(),
                      onChanged: _updateSlider,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canAfford ? _validateAndSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ENTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

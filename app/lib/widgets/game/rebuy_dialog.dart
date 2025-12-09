import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/poker_loading_indicator.dart';

class RebuyDialog extends StatefulWidget {
  final int initialAmount;
  final int timeoutSeconds;
  final Function(int amount) onRebuy;
  final VoidCallback onLeave;

  const RebuyDialog({
    super.key,
    this.initialAmount = 1000,
    this.timeoutSeconds = 30,
    required this.onRebuy,
    required this.onLeave,
  });

  @override
  State<RebuyDialog> createState() => _RebuyDialogState();
}

class _RebuyDialogState extends State<RebuyDialog> {
  late TextEditingController _amountController;
  late Timer _timer;
  late int _secondsLeft;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.initialAmount.toString());
    _secondsLeft = widget.timeoutSeconds;
    
    // Start countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsLeft > 0) {
            _secondsLeft--;
          } else {
            _timer.cancel();
            // Auto-leave handled by parent via socket kick event usually, 
            // but we can trigger leave action here too just in case.
            widget.onLeave(); 
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _amountController.dispose();
    super.dispose();
  }

  void _handleRebuy() {
    final amount = int.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) return;

    setState(() => _isLoading = true);
    widget.onRebuy(amount);
    // Don't close dialog immediately, wait for success response or parent to rebuild
  }

  @override
  Widget build(BuildContext context) {
    // Imperial Palette
    const Color goldColor = Color(0xFFC89A4E);
    const Color darkBg = Color(0xFF1C1C1C);

    final walletProvider = Provider.of<WalletProvider>(context);
    final currentBalance = walletProvider.balance;
    final amount = int.tryParse(_amountController.text) ?? 0;
    final canAfford = currentBalance >= amount;

    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: darkBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withOpacity(0.7), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'BANCARROTA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Te has quedado sin fichas.',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              
              const SizedBox(height: 24),

              // Timer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _secondsLeft < 10 ? Colors.red : goldColor.withOpacity(0.5)
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Expulsión en: ${_secondsLeft}s',
                      style: TextStyle(
                        color: _secondsLeft < 10 ? Colors.red : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Wallet Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Saldo Disponible:', style: TextStyle(color: Colors.white70)),
                    Text(
                      '$currentBalance',
                      style: const TextStyle(color: goldColor, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Amount Input
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Monto de Recarga',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: goldColor.withOpacity(0.3)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: goldColor),
                  ),
                  suffixIcon: const Icon(Icons.monetization_on, color: goldColor),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
              
              if (!canAfford)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Saldo insuficiente en billetera',
                    style: TextStyle(color: Colors.red[400], fontSize: 12),
                  ),
                ),

              const SizedBox(height: 30),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onLeave,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('SALIR', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isLoading || !canAfford) ? null : _handleRebuy,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: PokerLoadingIndicator(size: 20, color: Colors.black))
                        : const Text('RECARGAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


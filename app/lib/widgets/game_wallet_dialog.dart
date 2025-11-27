import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/socket_service.dart';
import '../providers/language_provider.dart';

class GameWalletDialog extends StatefulWidget {
  final String roomId;

  const GameWalletDialog({super.key, required this.roomId});

  @override
  State<GameWalletDialog> createState() => _GameWalletDialogState();
}

class _GameWalletDialogState extends State<GameWalletDialog> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _topUp() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Invalid amount');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final socketService = context.read<SocketService>();
    
    await socketService.topUp(
      widget.roomId,
      amount,
      onSuccess: (addedAmount) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added $addedAmount chips to game'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = error;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletProvider = context.watch<WalletProvider>();
    final lang = context.read<LanguageProvider>();
    final isSpanish = lang.currentLocale.languageCode == 'es';

    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e).withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: const Color(0xFFffd700).withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Color(0xFFffd700), size: 28),
                const SizedBox(width: 12),
                Text(
                  isSpanish ? 'Billetera' : 'Wallet',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Balance Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSpanish ? 'Saldo Disponible:' : 'Available Balance:',
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                  Text(
                    walletProvider.balance.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Color(0xFFffd700),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Top Up Input
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: isSpanish ? 'Agregar Fichas' : 'Add Chips',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintText: isSpanish ? 'Monto' : 'Amount',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFffd700)),
                ),
                prefixIcon: const Icon(Icons.add_circle_outline, color: Color(0xFFffd700)),
              ),
            ),
            
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      isSpanish ? 'Cancelar' : 'Cancel',
                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _topUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFffd700),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isSpanish ? 'Agregar' : 'Add'),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/language_provider.dart';

class WithdrawCreditsDialog extends StatefulWidget {
  const WithdrawCreditsDialog({super.key});

  @override
  State<WithdrawCreditsDialog> createState() => _WithdrawCreditsDialogState();
}

class _WithdrawCreditsDialogState extends State<WithdrawCreditsDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _walletController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    final amount = double.tryParse(_amountController.text);
    final wallet = _walletController.text.trim();

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Invalid amount');
      return;
    }

    if (wallet.isEmpty) {
      setState(() => _error = 'Wallet address required');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await context.read<WalletProvider>().withdrawCredits(
      amount,
      wallet,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal processed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _error = context.read<WalletProvider>().errorMessage ?? 'Withdrawal failed';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LanguageProvider>();
    final isSpanish = lang.currentLocale.languageCode == 'es';

    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e).withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.remove_circle, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                Text(
                  isSpanish ? 'Retirar Créditos' : 'Withdraw Credits',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: isSpanish ? 'Monto' : 'Amount',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.monetization_on, color: Colors.amber),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _walletController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: isSpanish ? 'Dirección de Billetera' : 'Wallet Address',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.account_balance_wallet, color: Colors.blue),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text(isSpanish ? 'Cancelar' : 'Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _withdraw,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isSpanish ? 'Retirar' : 'Withdraw'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

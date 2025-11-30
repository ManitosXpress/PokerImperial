import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/wallet_provider.dart';

/// Wallet Display Widget
/// Shows current balance with real-time updates
class WalletDisplay extends StatelessWidget {
  final VoidCallback? onTap;

  const WalletDisplay({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final walletProvider = context.watch<WalletProvider>();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFffd700).withOpacity(0.8),
              const Color(0xFFffed4e).withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFffd700).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/credits_icon.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 8),
            if (walletProvider.isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF1a1a2e)),
                ),
              )
            else
              Text(
                walletProvider.balance.toStringAsFixed(0),
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1a1a2e),
                ),
              ),
              if (walletProvider.inGameBalance > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '(+${walletProvider.inGameBalance.toStringAsFixed(0)})',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1a1a2e).withOpacity(0.7),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

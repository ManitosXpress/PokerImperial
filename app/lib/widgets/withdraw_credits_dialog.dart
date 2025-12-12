import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/language_provider.dart';
import '../providers/club_provider.dart';

class WithdrawCreditsDialog extends StatefulWidget {
  final bool isClubRequest;
  const WithdrawCreditsDialog({super.key, this.isClubRequest = false});

  @override
  State<WithdrawCreditsDialog> createState() => _WithdrawCreditsDialogState();
}

class _WithdrawCreditsDialogState extends State<WithdrawCreditsDialog> {
  final TextEditingController _amountController = TextEditingController();
  // Removed wallet controller as per request
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // Bot de Telegram
  static const String telegramBotUrl = 'https://t.me/AgenteImperialbot';

  Future<void> _requestWithdrawalViaTelegram() async {
    final user = context.read<app_auth.AuthProvider>().user;
    if (user == null) return;

    final amount = double.tryParse(_amountController.text);
    // Wallet address removed

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Monto inválido');
      return;
    }



    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Crear mensaje
      String message;
      if (widget.isClubRequest) {
        final clubProvider = context.read<ClubProvider>();
        final myClub = clubProvider.myClub;
        final clubId = myClub?['id'] ?? 'N/A';
        final clubName = myClub?['name'] ?? 'N/A';

        message = '''
💸 *Solicitud de Retiro a Staff del Club - Poker Imperial*

ClubId: $clubId
Nombre del club: $clubName
👤 Usuario: ${user.email}
🆔 UID: ${user.uid}
💰 Monto: $amount créditos

Por favor procesar mi retiro.
Gracias!
''';
      } else {
        message = '''
💸 *Retiro de Créditos - Poker Imperial*

👤 Usuario: ${user.email}
🆔 UID: ${user.uid}
💰 Monto: $amount créditos

Por favor procesar mi retiro.
Gracias!
''';
      }

      // Copiar al portapapeles
      await Clipboard.setData(ClipboardData(text: message));
      
      // Intentar abrir Telegram
      final encodedMessage = Uri.encodeComponent(message);
      final telegramUrl = '$telegramBotUrl?text=$encodedMessage';
      
      final uri = Uri.parse(telegramUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud copiada. Pégala en el chat de Telegram.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() => _error = 'No se pudo abrir Telegram');
      }
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LanguageProvider>();
    final isSpanish = lang.currentLocale.languageCode == 'es';

    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e), // Dark background
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1), // Subtle border
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD95368), // Red/Pink from image
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove, color: Colors.black, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSpanish ? 'Retirar Créditos' : 'Withdraw Credits',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isClubRequest
                          ? (isSpanish 
                              ? 'Solicita retiro al staff de tu club via Telegram'
                              : 'Request withdrawal from your club staff via Telegram')
                          : (isSpanish 
                              ? 'Solicita retiro al administrador via Telegram'
                              : 'Request withdrawal from admin via Telegram'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: isSpanish ? 'Ingresa monto' : 'Enter amount',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: const Color(0xFF2A2A35), // Darker grey/blue
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                prefixIcon: Container(
                  margin: const EdgeInsets.only(left: 12, right: 8),
                  child: const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 24),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isSpanish ? 'Cancelar' : 'Cancel',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _requestWithdrawalViaTelegram,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD95368), // Red/Pink from image
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: _isLoading 
                      ? const SizedBox.shrink() 
                      : const Icon(Icons.send_rounded, size: 18),
                    label: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            isSpanish ? 'Solicitar' : 'Request',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

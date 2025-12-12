import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/language_provider.dart';
import '../providers/club_provider.dart';

/// Dialog para solicitar créditos via Telegram
/// El admin agrega los créditos manualmente en Firebase
class AddCreditsDialog extends StatefulWidget {
  const AddCreditsDialog({super.key, this.isClubRequest = false});

  final bool isClubRequest;

  static const String telegramBotUrl = 'https://t.me/AgenteImperialbot';

  @override
  State<AddCreditsDialog> createState() => _AddCreditsDialogState();
}

class _AddCreditsDialogState extends State<AddCreditsDialog> {
  final TextEditingController _customAmountController = TextEditingController();
  double? _selectedAmount;
  bool _isLoading = false;

  Future<void> _requestCreditsViaTelegram() async {
    setState(() => _isLoading = true);
    try {
      final double amount = _selectedAmount ?? double.tryParse(_customAmountController.text) ?? 0;
      
      if (amount <= 0) {
        throw Exception('Por favor ingresa un monto válido');
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuario no identificado');
      }

      // Mensaje para el bot
      String message;
      
      if (widget.isClubRequest) {
        final clubProvider = context.read<ClubProvider>();
        final myClub = clubProvider.myClub;
        final clubId = myClub?['id'] ?? 'N/A';
        final clubName = myClub?['name'] ?? 'N/A';

        message = 'Solicitud de Créditos a Staff del Club - Poker Imperial\n\n'
            '  ClubId: $clubId\n'
            '  Nombre del club: $clubName\n'
            '  Email: ${user.displayName ?? "N/A"}\n'
            '  UID: ${user.uid}\n'
            '  Monto: ${amount.toInt()} creditos\n\n'
            'Por favor agregar estos créditos a mi cuenta.\n'
            'Gracias!';
      } else {
        message = 'Solicitud de recarga:\n'
            'ID: ${user.uid}\n'
            'Email: ${user.email}\n'
            'Monto: ${amount.toInt()} creditos\n\n'
            'Por favor agregar estos créditos a mi cuenta.\n'
            'Gracias!';
      }
      await Clipboard.setData(ClipboardData(text: message));

      // Abrir Telegram
      final encodedMessage = Uri.encodeComponent(message);
      final urlString = '${AddCreditsDialog.telegramBotUrl}?text=$encodedMessage';
      final Uri url = Uri.parse(urlString);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        
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
        throw Exception('No se pudo abrir Telegram');
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
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
        side: BorderSide(color: const Color(0xFFe94560).withOpacity(0.3), width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.add_circle, color: const Color(0xFFe94560), size: 28),
                const SizedBox(width: 12),
                  Text(
                    widget.isClubRequest 
                        ? (isSpanish ? 'Solicitar al Club' : 'Request to Club')
                        : (isSpanish ? 'Agregar Créditos' : 'Add Credits'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.isClubRequest
                  ? (isSpanish 
                      ? 'Solicita créditos al staff de tu club via Telegram' 
                      : 'Request credits from your club staff via Telegram')
                  : (isSpanish 
                      ? 'Solicita créditos al administrador via Telegram'
                      : 'Request credits from admin via Telegram'),
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),

            // Predefined amounts
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [100, 500, 1000, 5000].map((amount) {
                final isSelected = _selectedAmount == amount;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAmount = amount.toDouble();
                      _customAmountController.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFe94560)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFe94560)
                            : Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monetization_on,
                          color: isSelected ? Colors.white : const Color(0xFFffd700),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          amount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Custom amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit, color: Colors.white.withOpacity(0.7), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isSpanish ? 'Monto Personalizado' : 'Custom Amount',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customAmountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: isSpanish ? 'Ingresa monto' : 'Enter amount',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(
                        Icons.monetization_on,
                        color: const Color(0xFFffd700),
                        size: 20,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _selectedAmount = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                // Cancel button
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    child: Text(
                      isSpanish ? 'Cancelar' : 'Cancel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Request button (WhatsApp)
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _requestCreditsViaTelegram,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFe94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                isSpanish ? 'Solicitar' : 'Request',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
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

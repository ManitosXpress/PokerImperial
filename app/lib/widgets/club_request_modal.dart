import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/club_provider.dart';
import '../screens/club/club_dashboard_screen.dart';
import '../providers/language_provider.dart';

class ClubRequestModal extends StatefulWidget {
  const ClubRequestModal({super.key});

  @override
  State<ClubRequestModal> createState() => _ClubRequestModalState();
}

class _ClubRequestModalState extends State<ClubRequestModal> {
  final PageController _pageController = PageController();
  final _formKey = GlobalKey<FormState>();
  
  // Form Controllers
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _creditsController = TextEditingController();

  int _currentPage = 0;
  bool _isSubmitting = false;
  static const String telegramBotUrl = 'https://t.me/AgenteBingobot';

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _logoUrlController.dispose();
    _creditsController.dispose();
    super.dispose();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _submitRequest(LanguageProvider lang) async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    final logoUrl = _logoUrlController.text.trim();
    final credits = _creditsController.text.trim();
    
    // TELEGRAM INTEGRATION - ENABLED
    // Pre-formatted message for Telegram (keeping this in Spanish as it's for the bot/admin, or should it be localized? Admin likely speaks Spanish. Keeping as is.)
    final message = '🎰 Solicitud de Nuevo Club\n\n'
        '📋 Nombre: $name\n'
        '📝 Descripción: ${description.isEmpty ? 'N/A' : description}\n'
        '🖼️ Logo: ${logoUrl.isEmpty ? 'N/A' : logoUrl}\n'
        '💰 Créditos Iniciales: $credits\n\n'

        '👤 Usuario ID: ${user.uid}\n'
        '📧 Email: ${user.email ?? 'N/A'}\n'
        '📱 Nombre: ${user.displayName ?? 'N/A'}\n'
        '     Role: club\n\n'
        '✅ Acepto el esquema de comisiones 50/30/20.';

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: message));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.getText('opening_telegram')),
          backgroundColor: const Color(0xFF0088cc),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Launch Telegram
    final encodedMessage = Uri.encodeComponent(message);
    final urlString = '$telegramBotUrl?text=$encodedMessage';
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir Telegram');
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E), // Dark blue-grey
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFFFD700), width: 2), // Gold border
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 60),
                const SizedBox(height: 16),
                Text(
                  '${lang.getText('confirmation_text')} ${lang.getText('follow_steps')}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Close dialog and navigate to Club Dashboard (refreshing the view)
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const ClubDashboardScreen()),
                      (route) => false, // Remove all previous routes
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700), // Gold
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(lang.getText('accept'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error launching Telegram: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al abrir Telegram. Por favor, abre la app manualmente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2D1414), // Dark red-brown
              Color(0xFF1A1A2E), // Dark blue-grey
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFFD700),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFD700).withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
                border: const Border(
                  bottom: BorderSide(
                    color: Color(0xFFFFD700),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _currentPage == 0 ? lang.getText('business_model') : lang.getText('club_request'),
                      style: const TextStyle(
                        // ...
                      ),
                    ),
                  ),
                  // ... (close button)
                ],
              ),
            ),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildPitchPage(lang),
                  _buildFormPage(lang),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitchPage(LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.emoji_events,
            color: Color(0xFFFFD700),
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Gana dinero con tu propio Club de Poker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Distribution Chart Visualization
          _buildDistributionItem('50%', 'Plataforma', Colors.blueGrey.shade400),
          const SizedBox(height: 16),
          _buildDistributionItem('30%', 'TÚ (Club Owner)', const Color(0xFFFFD700), isHighlight: true),
          const SizedBox(height: 16),
          _buildDistributionItem('20%', 'Tus Vendedores', Colors.greenAccent),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFD700).withOpacity(0.3),
              ),
            ),
            child: const Text(
              'El Rake es del 8% del bote total.\n\nDe ese Rake, tú te llevas el 30% generado por tus jugadores.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                lang.getText('apply'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionItem(String percentage, String label, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.3),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(isHighlight ? 1.0 : 0.5),
          width: isHighlight ? 3 : 2,
        ),
        boxShadow: isHighlight
            ? [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              percentage,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(isHighlight ? 1.0 : 0.9),
                fontSize: 16,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          if (isHighlight)
            const Icon(
              Icons.star,
              color: Color(0xFFFFD700),
              size: 24,
            ),
        ],
      ),
    );
  }

  Widget _buildFormPage(LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              lang.getText('club_request'),
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _nameController,
              label: lang.getText('club_name'),
              icon: Icons.shield,
              validator: (v) => v?.isEmpty == true ? 'Este campo es requerido' : null,
            ),
            const SizedBox(height: 18),
            _buildTextField(
              controller: _descController,
              label: lang.getText('short_desc'),
              icon: Icons.description,
              maxLines: 2,
            ),
            const SizedBox(height: 18),
            _buildTextField(
              controller: _logoUrlController,
              label: lang.getText('logo_url'),
              icon: Icons.image,
            ),
            const SizedBox(height: 18),
            _buildTextField(
              controller: _creditsController,
              label: lang.getText('initial_credits'),
              icon: Icons.monetization_on,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v?.isEmpty == true) return 'Este campo es requerido';
                if (int.tryParse(v!) == null) return 'Debe ser un número válido';
                return null;
              },
            ),
            const SizedBox(height: 32),
            
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : () => _submitRequest(lang),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.telegram, size: 24),
                label: Text(
                  _isSubmitting ? lang.getText('opening_telegram') : lang.getText('request_via_telegram'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _pageController.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Text(
                lang.getText('return_conditions'),
                style: const TextStyle(
                  color: Colors.white54,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 14,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFFD700),
              size: 20,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFFFD700),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFFFD700),
              width: 2.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.red,
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.red,
              width: 2.5,
            ),
          ),
          filled: true,
          fillColor: Colors.black.withOpacity(0.3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

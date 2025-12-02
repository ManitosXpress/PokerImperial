import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/club_provider.dart';

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
  static const String telegramBotUrl = 'http://t.me/AgenteBingobot'; // Replace with actual bot if different

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

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // final name = _nameController.text;
    // final credits = _creditsController.text;
    
    // // Pre-formatted message
    // final message = 'Solicitud de Nuevo Club: $name\n'
    //     'Usuario: ${user.uid}\n'
    //     'Créditos: $credits\n'
    //     'Acepto el esquema de comisiones 60/30/10.';

    // // Copy to clipboard
    // await Clipboard.setData(ClipboardData(text: message));

    // if (mounted) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //       content: Text('Solicitud copiada. Enviando a Telegram...'),
    //       backgroundColor: Color(0xFF0088cc),
    //     ),
    //   );
      
    //   // Close modal
    //   Navigator.pop(context);
    // }

    // // Launch Telegram
    // final Uri url = Uri.parse(telegramBotUrl);
    // try {
    //   if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    //     throw Exception('Could not launch Telegram');
    //   }
    // } catch (e) {
    //   debugPrint('Error launching Telegram: $e');
    // }

    // DIRECT CREATION (TEMPORARY)
    try {
      await Provider.of<ClubProvider>(context, listen: false)
          .createClub(_nameController.text, _descController.text);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Club creado exitosamente!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear club: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.maxFinite,
        height: 600,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFD700), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentPage == 0 ? 'MODELO DE NEGOCIO' : 'SOLICITUD DE CLUB',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
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
                  _buildPitchPage(),
                  _buildFormPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitchPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Gana dinero con tu propio Club de Poker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Distribution Chart Visualization
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDistributionItem('60%', 'Plataforma', Colors.blueGrey),
                const SizedBox(height: 16),
                _buildDistributionItem('30%', 'TÚ (Club Owner)', const Color(0xFFFFD700), isHighlight: true),
                const SizedBox(height: 16),
                _buildDistributionItem('10%', 'Tus Jugadores del club', Colors.green),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text(
            'El Rake es del 8% del bote total.\nDe ese Rake, tú te llevas el 30% generado por tus jugadores.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'ENTENDIDO, QUIERO APLICAR',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionItem(String percentage, String label, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(isHighlight ? 1.0 : 0.5),
          width: isHighlight ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            percentage,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(isHighlight ? 1.0 : 0.9),
              fontSize: 18,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTextField(
              controller: _nameController,
              label: 'Nombre del Club',
              icon: Icons.shield,
              validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _descController,
              label: 'Descripción Corta',
              icon: Icons.description,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _logoUrlController,
              label: 'Link de Imagen/Logo (Opcional)',
              icon: Icons.image,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _creditsController,
              label: 'Créditos Iniciales a Comprar',
              icon: Icons.monetization_on,
              keyboardType: TextInputType.number,
              validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
            ),
            const SizedBox(height: 32),
            
            ElevatedButton.icon(
              onPressed: _submitRequest,
              icon: const Icon(Icons.check_circle),
              label: const Text('CREAR CLUB'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700), // Gold
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _currentPage = 0),
              child: const Text(
                'Volver a leer condiciones',
                style: TextStyle(color: Colors.white54),
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
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: const Color(0xFFFFD700)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
        filled: true,
        fillColor: Colors.black12,
      ),
    );
  }
}

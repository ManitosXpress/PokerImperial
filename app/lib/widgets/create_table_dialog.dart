import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreateTableDialog extends StatefulWidget {
  final Function(Map<String, int>) onCreate;

  const CreateTableDialog({Key? key, required this.onCreate}) : super(key: key);

  @override
  _CreateTableDialogState createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // No default values, use hints
  final TextEditingController _sbController = TextEditingController();
  final TextEditingController _bbController = TextEditingController();
  final TextEditingController _minBuyInController = TextEditingController();
  final TextEditingController _maxBuyInController = TextEditingController();

  @override
  void dispose() {
    _sbController.dispose();
    _bbController.dispose();
    _minBuyInController.dispose();
    _maxBuyInController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final sb = int.parse(_sbController.text);
      final bb = int.parse(_bbController.text);
      final minBuyIn = int.parse(_minBuyInController.text);
      final maxBuyIn = int.parse(_maxBuyInController.text);

      print('📋 [CreateTableDialog] Validated values: SB=$sb, BB=$bb, Min=$minBuyIn, Max=$maxBuyIn');

      widget.onCreate({
        'smallBlind': sb,
        'bigBlind': bb,
        'minBuyIn': minBuyIn,
        'maxBuyIn': maxBuyIn,
      });
      Navigator.of(context).pop();
    } else {
      print('❌ [CreateTableDialog] Validation failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color goldColor = Color(0xFFFFD700);
    const Color inputBg = Color(0xFF1A1A2E);
    const Color textColor = Colors.white70;

    return Dialog(
      backgroundColor: const Color(0xFF16213E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Center(
                child: Text(
                  'CONFIGURAR MESA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Blinds Row
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      controller: _sbController,
                      label: 'SB (Small Blind)',
                      hint: 'Ej: 10',
                      validator: (val) {
                        return _validateNumber(val, min: 1);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      controller: _bbController,
                      label: 'BB (Big Blind)',
                      hint: 'Ej: 20',
                      validator: (val) {
                        final sb = int.tryParse(_sbController.text) ?? 0;
                        return _validateNumber(val, min: sb + 1, errorMsg: 'Debe ser > SB');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Buy-In Row
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      controller: _minBuyInController,
                      label: 'Min Buy-In',
                      hint: 'Ej: 1000',
                      validator: (val) {
                         final bb = int.tryParse(_bbController.text) ?? 0;
                        return _validateNumber(val, min: bb * 10, errorMsg: 'Min ${bb*10}');
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      controller: _maxBuyInController,
                      label: 'Max Buy-In',
                      hint: 'Ej: 5000',
                      validator: (val) {
                        final min = int.tryParse(_minBuyInController.text) ?? 0;
                        return _validateNumber(val, min: min, errorMsg: '>= Min');
                      },
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Crear Mesa',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: const Color(0xFF1A1A2E).withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFFD700)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    );
  }

  String? _validateNumber(String? value, {int min = 0, String? errorMsg}) {
    if (value == null || value.isEmpty) {
      return 'Requerido';
    }
    final num = int.tryParse(value);
    if (num == null) {
      return 'Inválido';
    }
    if (num < min) {
      return errorMsg ?? 'Min $min';
    }
    return null;
  }
}

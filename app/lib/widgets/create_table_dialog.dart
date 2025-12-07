import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateTableDialog extends StatefulWidget {
  const CreateTableDialog({super.key});

  @override
  State<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _smallBlindController = TextEditingController(text: '10');
  final _bigBlindController = TextEditingController(text: '20');
  final _minBuyInController = TextEditingController(text: '100');
  final _maxBuyInController = TextEditingController(text: '1000');

  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _smallBlindController.dispose();
    _bigBlindController.dispose();
    _minBuyInController.dispose();
    _maxBuyInController.dispose();
    super.dispose();
  }

  Future<void> _createTable() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('createPublicTableFunction').call({
        'name': _nameController.text.trim(),
        'smallBlind': int.parse(_smallBlindController.text),
        'bigBlind': int.parse(_bigBlindController.text),
        'minBuyIn': int.parse(_minBuyInController.text),
        'maxBuyIn': int.parse(_maxBuyInController.text),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${result.data['message']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1f3a),
              Color(0xFF0f1425),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Crear Mesa Pública',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Table Name
                _buildTextField(
                  controller: _nameController,
                  label: 'Nombre de la Mesa',
                  icon: Icons.table_chart,
                  validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                // Blinds Row
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _smallBlindController,
                        label: 'Ciega Pequeña',
                        icon: Icons.remove_circle_outline,
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Número inválido'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _bigBlindController,
                        label: 'Ciega Grande',
                        icon: Icons.add_circle_outline,
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Número inválido'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Buy-In Row
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _minBuyInController,
                        label: 'Buy-In Mínimo',
                        icon: Icons.arrow_downward,
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Número inválido'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _maxBuyInController,
                        label: 'Buy-In Máximo',
                        icon: Icons.arrow_upward,
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Número inválido'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Create Button
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createTable,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.add_circle, color: Colors.black),
                    label: Text(
                      _isCreating ? 'CREANDO...' : 'CREAR MESA',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFFFD700)),
        prefixIcon: Icon(icon, color: const Color(0xFFFFD700)),
        filled: true,
        fillColor: Colors.black.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}

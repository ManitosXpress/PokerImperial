import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import 'lobby_screen.dart';

/// Login Screen
/// Provides authentication UI with Email/Password
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isRegistering = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    
    bool success;
    if (_isRegistering) {
      success = await authProvider.registerWithUsername(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        nickname: _nicknameController.text.trim(),
      );
    } else {
      success = await authProvider.signInWithUsername(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
    }

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } else if (authProvider.errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
      authProvider.clearError();
    }
  }



  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final lang = context.read<LanguageProvider>();
    final isSpanish = lang.currentLocale.languageCode == 'es';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker3_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.8),
                Colors.black.withOpacity(0.85),
                Colors.black.withOpacity(0.9),
              ],
            ),
          ),
          child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 12,
                color: const Color(0xFF1C1C1C).withOpacity(0.95), // Black background
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFC89A4E), width: 2), // Gold Border
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo/Title
                        Image.asset(
                          'assets/images/bingo_imperial_logo_v4.png',
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 24),

                        // Username field
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: isSpanish ? 'Usuario' : 'Username',
                            labelStyle: const TextStyle(color: Color(0xFFC89A4E)), // Gold label
                            prefixIcon: const Icon(Icons.person, color: Color(0xFFC89A4E)), // Gold icon
                            filled: true,
                            fillColor: const Color(0xFF2C2C2C), // Slightly lighter black for inputs
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 2),
                            ),
                          ),
                          style: const TextStyle(color: Color(0xFFF1E3D3)), // Light Beige text
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return isSpanish ? 'Ingresa tu usuario' : 'Enter username';
                            }
                            if (value.contains(' ')) {
                              return isSpanish ? 'Sin espacios' : 'No spaces';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Nickname field (only for registration)
                        if (_isRegistering)
                          Column(
                            children: [
                              TextFormField(
                                controller: _nicknameController,
                                decoration: InputDecoration(
                                  labelText: isSpanish ? 'Apodo' : 'Nickname',
                                  labelStyle: const TextStyle(color: Color(0xFFC89A4E)),
                                  prefixIcon: const Icon(Icons.person, color: Color(0xFFC89A4E)),
                                  filled: true,
                                  fillColor: const Color(0xFF2C2C2C),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 2),
                                  ),
                                ),
                                style: const TextStyle(color: Color(0xFFF1E3D3)),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return isSpanish ? 'Ingresa un apodo' : 'Enter nickname';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),

                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: isSpanish ? 'Contraseña' : 'Password',
                            labelStyle: const TextStyle(color: Color(0xFFC89A4E)),
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFFC89A4E)),
                            filled: true,
                            fillColor: const Color(0xFF2C2C2C),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 2),
                            ),
                          ),
                          style: const TextStyle(color: Color(0xFFF1E3D3)),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return isSpanish ? 'Ingresa contraseña' : 'Enter password';
                            }
                            if (_isRegistering && value.length < 6) {
                              return isSpanish ? 'Mínimo 6 caracteres' : 'Min 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Email Auth Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: authProvider.isLoading ? null : _handleAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC89A4E), // Gold button
                              foregroundColor: const Color(0xFF1C1C1C), // Black text
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                            ),
                            child: authProvider.isLoading
                                ? const CircularProgressIndicator(color: Color(0xFF1C1C1C))
                                : Text(
                                    _isRegistering
                                        ? (isSpanish ? 'Registrarse' : 'Register')
                                        : (isSpanish ? 'Iniciar Sesión' : 'Sign In'),
                                    style: GoogleFonts.montserrat(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1C1C1C), // Black text
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Toggle Register/Login
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegistering = !_isRegistering;
                            });
                          },
                          child: Text(
                            _isRegistering
                                ? (isSpanish ? '¿Ya tienes cuenta? Inicia sesión' : 'Have account? Sign in')
                                : (isSpanish ? '¿No tienes cuenta? Regístrate' : 'No account? Register'),
                            style: const TextStyle(color: Color(0xFFF1E3D3)), // Beige text
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

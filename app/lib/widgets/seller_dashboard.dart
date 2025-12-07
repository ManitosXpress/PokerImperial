import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/club_provider.dart';
import 'credentials_dialog.dart';

/// Seller Dashboard Widget
/// Similar to ClubOwnerDashboard but with restricted functionality:
/// - Can only register players (not sellers)
/// - Can only transfer credits to players (not sellers or owner)
class SellerDashboard extends StatefulWidget {
  final String clubId;
  final String clubName;

  const SellerDashboard({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final credit = userData?['credit'] ?? 0;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF0088cc).withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0088cc).withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SELLER PANEL',
                    style: TextStyle(
                      color: Color(0xFF0088cc),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                  Icon(Icons.store, color: const Color(0xFF0088cc).withOpacity(0.8), size: 20),
                ],
              ),
              const SizedBox(height: 20),
              
              // Credit Display
              const Text(
                'Tu Capital Disponible',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${credit.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(color: Color(0xFF0088cc), blurRadius: 10, offset: Offset(0, 0)),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              const Divider(color: Colors.white10),
              const SizedBox(height: 24),

              // Action Grid
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.person_add_alt_1,
                      label: 'Registrar\nJugador',
                      color: const Color(0xFF0088cc),
                      onTap: () => _showRegisterPlayerDialog(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.currency_exchange,
                      label: 'Transferir\nCréditos',
                      color: const Color(0xFF0088cc),
                      onTap: () => _showTransferCreditsDialog(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRegisterPlayerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RegisterPlayerDialog(clubId: widget.clubId),
    );
  }

  void _showTransferCreditsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SellerTransferDialog(clubId: widget.clubId),
    );
  }
}

// --- Action Card Widget ---
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Register Player Dialog (Seller can only create players) ---
class _RegisterPlayerDialog extends StatefulWidget {
  final String clubId;
  const _RegisterPlayerDialog({required this.clubId});

  @override
  State<_RegisterPlayerDialog> createState() => _RegisterPlayerDialogState();
}

class _RegisterPlayerDialogState extends State<_RegisterPlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    debugPrint('Seller registering player for clubId: ${widget.clubId}');

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('sellerCreatePlayerFunction').call({
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
        'displayName': _nameController.text.trim(),
        'clubId': widget.clubId,
      });

      if (mounted) {
        Navigator.pop(context); // Close registration dialog
        
        // Show credentials dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => CredentialsDialog(
            username: _usernameController.text.trim(),
            password: _passwordController.text.trim(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Registrar Nuevo Jugador', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088cc).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0088cc).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF0088cc), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El jugador será asignado a tu club automáticamente.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Nombre'),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Usuario'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.contains(' ')) return 'Sin espacios';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Contraseña'),
                obscureText: true,
                validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _register,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0088cc),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Registrar'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF0088cc))),
    );
  }
}

// --- Seller Transfer Dialog (Only to players) ---
class _SellerTransferDialog extends StatefulWidget {
  final String clubId;
  const _SellerTransferDialog({required this.clubId});

  @override
  State<_SellerTransferDialog> createState() => _SellerTransferDialogState();
}

class _SellerTransferDialogState extends State<_SellerTransferDialog> {
  final _amountController = TextEditingController();
  String? _selectedPlayerId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _players = [];

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    try {
      final provider = Provider.of<ClubProvider>(context, listen: false);
      final members = await provider.fetchClubLeaderboard(widget.clubId);
      if (mounted) {
        setState(() {
          // Filter to only show players (not sellers or owner)
          _players = members.where((m) {
            final role = m['role'] ?? 'player';
            return role == 'player';
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading players: $e');
    }
  }

  Future<void> _transfer() async {
    if (_selectedPlayerId == null || _amountController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('sellerTransferCreditFunction').call({
        'clubId': widget.clubId,
        'targetUid': _selectedPlayerId,
        'amount': int.parse(_amountController.text),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Transferencia exitosa!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Transferir a Jugador', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0088cc).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF0088cc).withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF0088cc), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Solo puedes transferir a jugadores de tu club.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          DropdownButtonFormField<String>(
            value: _selectedPlayerId,
            dropdownColor: const Color(0xFF16213E),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Seleccionar Jugador',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF0088cc))),
            ),
            items: _players.map((p) {
              return DropdownMenuItem(
                value: p['uid'] as String,
                child: Text(p['displayName'] ?? 'Sin nombre'),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedPlayerId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Monto',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF0088cc))),
              suffixText: 'Créditos',
              suffixStyle: TextStyle(color: Color(0xFF0088cc)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _transfer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0088cc),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Transferir'),
        ),
      ],
    );
  }
}

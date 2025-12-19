import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'imperial_currency.dart';
import '../providers/club_provider.dart';
import 'credentials_dialog.dart';
import '../widgets/poker_loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/club/transaction_history_screen.dart';
import '../screens/tournament/create_tournament_screen.dart';

const String ADMIN_CONTACT_URL = 'https://t.me/AgenteBingobot';

class ClubOwnerDashboard extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubOwnerDashboard({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubOwnerDashboard> createState() => _ClubOwnerDashboardState();
}

class _ClubOwnerDashboardState extends State<ClubOwnerDashboard> {
  int _ownerCredit = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchOwnerCredit();
  }

  Future<void> _fetchOwnerCredit() async {
    // In a real app, this might come from a UserProvider stream.
    // For now, we'll fetch it once or rely on parent updates if possible.
    // Assuming we can get it from Firestore or a provider.
    // Here we'll just use a placeholder or fetch if needed.
    // Ideally, the parent screen should pass the owner's credit or a provider should expose it.
    // Let's try to get it from the current user's data if available in a provider,
    // otherwise we might need to fetch the user document.
    
    // For this implementation, we'll assume the user is the owner and we can get their credit
    // from a WalletProvider or similar, but since I don't have full context of all providers,
    // I'll implement a simple fetch for the current user's credit to be safe.
    
    // Actually, let's just use a stream builder on the user's document in the build method
    // or assume the parent passes it? The requirements say "Mostrando el credit del dueño".
    // I'll implement a simple fetch here for now.
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // This is a bit of a hack if we don't have a provider, but it works.
        // Better would be Consumer<WalletProvider> if it exists.
        // I'll leave this as a TODO to integrate with WalletProvider if found.
      }
    } catch (e) {
      debugPrint('Error fetching credit: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // We can try to find a provider that has user data.
    // If not, we'll use a StreamBuilder for real-time updates of the owner's credit.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        // We need the Firestore document for 'credit'.
        // Let's assume there's a provider or we use a StreamBuilder on Firestore.
        // To keep it self-contained and robust:
        return StreamBuilder<dynamic>( // dynamic to avoid importing cloud_firestore if not needed, but we need it.
          // Actually, let's use a standard Firestore stream.
          // I'll need to import cloud_firestore.
          stream: _getOwnerStream(user.uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final userData = snapshot.data!.data();
            final credit = userData?['credit'] ?? 0;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // Glassmorphism
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.1),
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
                        'EXECUTIVE PANEL',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontSize: 12,
                        ),
                      ),
                      Icon(Icons.admin_panel_settings, color: const Color(0xFFFFD700).withOpacity(0.8), size: 20),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Liquidity Indicator
                  const Text(
                    'Tu Capital Disponible',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  ImperialCurrency(
                    amount: credit,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      shadows: [
                        Shadow(color: Color(0xFFFFD700), blurRadius: 10, offset: Offset(0, 0)),
                      ],
                    ),
                    iconSize: 36,
                  ),
                  
                  const SizedBox(height: 24),

                  // --- A. Header Financiero (Compactado) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _CompactActionChip(
                        icon: Icons.arrow_downward, 
                        label: 'Cargar', 
                        color: Colors.greenAccent,
                        onTap: () => _showDepositDialog(context),
                      ),
                      _CompactActionChip(
                        icon: Icons.arrow_upward, 
                        label: 'Retirar', 
                        color: Colors.redAccent,
                        onTap: () => _showWithdrawDialog(context),
                      ),
                      _CompactActionChip(
                        icon: Icons.currency_exchange, 
                        label: 'Transferir', 
                        color: Colors.amber,
                        onTap: () => _showTransferCreditsDialog(context),
                      ),
                      _CompactActionChip(
                        icon: Icons.history, 
                        label: 'Historial', 
                        color: Colors.blueAccent,
                        onTap: () => _showHistoryDialog(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  // --- B. Game Operations Center ---
                  const Text(
                    'GESTIÓN DE JUEGO',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _GameOpCard(
                          title: 'Mesas Públicas',
                          icon: Icons.table_bar,
                          buttonText: 'Crear Nueva Sala',
                          imageAsset: 'assets/images/poker_table_bg.jpg', // Placeholder or use gradient
                          onTap: () => _showCreateTableDialog(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _GameOpCard(
                          title: 'Torneos',
                          icon: Icons.emoji_events,
                          buttonText: 'Crear Torneo',
                          imageAsset: 'assets/images/tournament_bg.jpg', // Placeholder or use gradient
                          onTap: () => _showCreateTournamentDialog(context),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Extra Management (Member Registration)
                   SizedBox(
                    width: double.infinity,
                    child: _ActionCard(
                      icon: Icons.person_add_alt_1,
                      label: 'Registrar Nuevo Miembro',
                      onTap: () => _showRegisterMemberDialog(context),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  // Helper to get stream without importing cloud_firestore directly in the widget signature if possible,
  // but we need to import it. I'll add the import at the top.
  Stream<dynamic> _getOwnerStream(String uid) {
    // Assuming cloud_firestore is available.
    // I will add the import 'package:cloud_firestore/cloud_firestore.dart';
    // But wait, I need to check if I can import it.
    // The user has 'firebase_auth', likely 'cloud_firestore' too.
    // I will add the import.
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  void _showRegisterMemberDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RegisterMemberDialog(clubId: widget.clubId),
    );
  }

  void _showTransferCreditsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _TransferCreditsDialog(clubId: widget.clubId),
    );
  }

  void _showHistoryDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TransactionHistoryScreen()),
    );
  }

  void _showDepositDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _FinancialRequestDialog(
        type: 'Solicitud de recarga',
        clubName: widget.clubName,
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _FinancialRequestDialog(
        type: 'Retiro de Créditos',
        clubName: widget.clubName,
      ),
    );
  }

  void _showCreateTableDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _CreateTableDialog(clubId: widget.clubId),
    );
  }

  void _showCreateTournamentDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTournamentScreen(clubId: widget.clubId),
      ),
    );
  }
}

// --- Action Card Widget ---
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
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
              Icon(icon, color: color ?? const Color(0xFFFFD700), size: 28),
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



// --- Register Member Dialog ---
class _RegisterMemberDialog extends StatefulWidget {
  final String clubId;
  const _RegisterMemberDialog({required this.clubId});

  @override
  State<_RegisterMemberDialog> createState() => _RegisterMemberDialogState();
}

class _RegisterMemberDialogState extends State<_RegisterMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'player';
  bool _isLoading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    debugPrint('Registering member for clubId: ${widget.clubId}');

    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('ownerCreateMemberFunction').call({
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
        'displayName': _nameController.text.trim(),
        'role': _selectedRole,
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
      title: const Text('Registrar Nuevo Miembro', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                dropdownColor: const Color(0xFF16213E),
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Rol'),
                items: const [
                  DropdownMenuItem(value: 'player', child: Text('Jugador')),
                  DropdownMenuItem(value: 'seller', child: Text('Vendedor')),
                ],
                onChanged: (v) => setState(() => _selectedRole = v!),
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
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
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
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
    );
  }
}

// --- Transfer Credits Dialog ---
class _TransferCreditsDialog extends StatefulWidget {
  final String clubId;
  const _TransferCreditsDialog({required this.clubId});

  @override
  State<_TransferCreditsDialog> createState() => _TransferCreditsDialogState();
}

class _TransferCreditsDialogState extends State<_TransferCreditsDialog> {
  final _amountController = TextEditingController();
  String? _selectedMemberId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    // We need to fetch members. Using ClubProvider is best if available.
    // Assuming ClubProvider is available in context.
    try {
      final provider = Provider.of<ClubProvider>(context, listen: false);
      final members = await provider.fetchClubLeaderboard(widget.clubId);
      if (mounted) {
        setState(() {
          _members = members;
        });
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
    }
  }

  Future<void> _transfer() async {
    if (_selectedMemberId == null || _amountController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('ownerTransferCreditFunction').call({
        'clubId': widget.clubId,
        'targetUid': _selectedMemberId,
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
      title: const Text('Transferir Créditos', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedMemberId,
            dropdownColor: const Color(0xFF16213E),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Seleccionar Miembro',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
            ),
            items: _members.map((m) {
              return DropdownMenuItem(
                value: m['uid'] as String,
                child: Text(m['displayName'] ?? 'Sin nombre'),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedMemberId = v),
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
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
              suffixText: 'Créditos',
              suffixStyle: TextStyle(color: Color(0xFFFFD700)),
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
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Transferir'),
        ),
      ],
    );
  }
}

// --- Financial Request Dialog ---
class _FinancialRequestDialog extends StatefulWidget {
  final String type;
  final String clubName;

  const _FinancialRequestDialog({required this.type, required this.clubName});

  @override
  State<_FinancialRequestDialog> createState() => _FinancialRequestDialogState();
}

class _FinancialRequestDialogState extends State<_FinancialRequestDialog> {
  final _amountController = TextEditingController();

  void _sendRequest() async {
    if (_amountController.text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amount = _amountController.text;
    final type = widget.type;
    final email = user.email ?? 'No Email';
    final uid = user.uid;

    final message = '''
$type - ${widget.clubName}

Usuario: $email
UID: $uid
Monto: $amount créditos

Por favor procesar esta solicitud. Gracias.
''';

    final encodedMessage = Uri.encodeComponent(message);
    final urlString = '$ADMIN_CONTACT_URL?text=$encodedMessage';
    final url = Uri.parse(urlString);

    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la app de mensajería: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.type, style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Ingresa el monto para generar la solicitud.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
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
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
              suffixText: 'Créditos',
              suffixStyle: TextStyle(color: Color(0xFFFFD700)),
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
          onPressed: _sendRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          child: const Text('Solicitar'),
        ),
      ],
    );
  }
}

// --- Compact Action Chip ---
class _CompactActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CompactActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Game Op Card ---
class _GameOpCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String buttonText;
  final String imageAsset;
  final VoidCallback onTap;

  const _GameOpCard({
    required this.title,
    required this.icon,
    required this.buttonText,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2A40),
            const Color(0xFF1A1A2E),
          ],
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              icon,
              size: 100,
              color: Colors.white.withOpacity(0.03),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Create Table Dialog ---
class _CreateTableDialog extends StatefulWidget {
  final String clubId;
  const _CreateTableDialog({required this.clubId});

  @override
  State<_CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<_CreateTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sbController = TextEditingController();
  final _bbController = TextEditingController();
  final _minBuyInController = TextEditingController();
  final _maxBuyInController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _sbController.dispose();
    _bbController.dispose();
    _minBuyInController.dispose();
    _maxBuyInController.dispose();
    super.dispose();
  }

  Future<void> _createTable() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('createClubTableFunction').call({
        'clubId': widget.clubId,
        'name': _nameController.text.trim(),
        'smallBlind': int.parse(_sbController.text),
        'bigBlind': int.parse(_bbController.text),
        'buyInMin': int.parse(_minBuyInController.text),
        'buyInMax': int.parse(_maxBuyInController.text),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Sala creada! Ahora está en espera de jugadores.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'Crear Mesa Privada',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildLabel('Nombre de la Mesa'),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Ej: Mesa VIP'),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('SB'),
                          TextFormField(
                            controller: _sbController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('10'),
                            validator: (v) => v!.isEmpty ? 'Req' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('BB'),
                          TextFormField(
                            controller: _bbController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('20'),
                            validator: (v) => v!.isEmpty ? 'Req' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Min Buy-In'),
                          TextFormField(
                            controller: _minBuyInController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('1000'),
                            validator: (v) => v!.isEmpty ? 'Req' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Max Buy-In'),
                          TextFormField(
                            controller: _maxBuyInController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('5000'),
                            validator: (v) => v!.isEmpty ? 'Req' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createTable,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text('Crear Mesa', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: Colors.black26,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFD700)),
      ),
    );
  }
}

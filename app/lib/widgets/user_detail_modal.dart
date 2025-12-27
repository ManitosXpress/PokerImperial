import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'imperial_currency.dart';
import 'poker_loading_indicator.dart';

class UserDetailModal extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;

  const UserDetailModal({
    super.key,
    required this.uid,
    required this.userData,
  });

  @override
  State<UserDetailModal> createState() => _UserDetailModalState();
}

class _UserDetailModalState extends State<UserDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E).withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                _buildHeader(),
                const Divider(color: Colors.white10, height: 1),
                _buildFinancialKPIs(),
                const Divider(color: Colors.white10, height: 1),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTransactionsTab(),
                      _buildSecurityTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = widget.userData['displayName'] ?? 'Usuario Desconocido';
    final email = widget.userData['email'] ?? 'No Email';
    final role = widget.userData['role'] ?? 'player';
    final isVip = role == 'club' || role == 'admin';
    final isOnline = widget.userData['isOnline'] ?? false; // Assuming this field exists or we default to false

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isVip ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
              boxShadow: isVip ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.3), blurRadius: 10)] : [],
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white10,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(isOnline),
                  ],
                ),
                Text(
                  email,
                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'UID: ${widget.uid}',
                      style: GoogleFonts.sourceCodePro(fontSize: 12, color: Colors.white38),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.uid));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('UID copiado al portapapeles')),
                        );
                      },
                      child: const Icon(Icons.copy, size: 14, color: Colors.white38),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOnline ? Colors.green : Colors.grey, width: 0.5),
      ),
      child: Text(
        isOnline ? 'ONLINE' : 'OFFLINE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isOnline ? Colors.green : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildFinancialKPIs() {
    final credit = widget.userData['credit'] ?? 0;
    // These would ideally come from a separate stats document or be calculated
    // For now, I'll use placeholders or data from userData if available
    final totalVolume = widget.userData['totalVolume'] ?? 0; 
    final netPnL = widget.userData['netPnL'] ?? 0;
    final rakeGenerated = widget.userData['rakeGenerated'] ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildKPICard('Créditos Actuales', credit, isCurrency: true),
          const SizedBox(width: 12),
          _buildKPICard('Volumen Total', totalVolume, isCurrency: true),
          const SizedBox(width: 12),
          _buildKPICard('Net PnL', netPnL, isCurrency: true, colorize: true),
          const SizedBox(width: 12),
          _buildKPICard('Rake Generado', rakeGenerated, isCurrency: true),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, dynamic value, {bool isCurrency = false, bool colorize = false}) {
    Color valueColor = Colors.white;
    if (colorize) {
      if (value > 0) valueColor = Colors.greenAccent;
      else if (value < 0) valueColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white54),
          ),
          const SizedBox(height: 4),
          isCurrency
              ? ImperialCurrency(
                  amount: _currencyFormat.format(value),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor),
                  iconSize: 14,
                )
              : Text(
                  value.toString(),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor),
                ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.black12,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFFFFD700),
        labelColor: const Color(0xFFFFD700),
        unselectedLabelColor: Colors.white54,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'TRANSACCIONES'),
          Tab(text: 'SEGURIDAD & NOTAS'),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('financial_ledger')
          .where('userId', isEqualTo: widget.uid)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: PokerLoadingIndicator(size: 30, color: Colors.amber));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No hay transacciones recientes',
              style: GoogleFonts.outfit(color: Colors.white30),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildTransactionItem(data);
          },
        );
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> data) {
    final type = data['type'] ?? 'UNKNOWN';
    final amount = data['amount'] ?? 0;
    final timestamp = data['timestamp'] as Timestamp?;
    final dateStr = timestamp != null 
        ? DateFormat('dd MMM HH:mm').format(timestamp.toDate()) 
        : '-';

    IconData icon;
    Color color;
    String label;

    switch (type) {
      case 'deposit':
      case 'game_win':
        icon = Icons.arrow_upward;
        color = Colors.greenAccent;
        label = type == 'deposit' ? 'Depósito' : 'Ganancia Juego';
        break;
      case 'withdrawal':
      case 'game_loss':
        icon = Icons.arrow_downward;
        color = Colors.redAccent;
        label = type == 'withdrawal' ? 'Retiro' : 'Pérdida Juego';
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
        label = type.toString().toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(
                  '$dateStr • Ref: ${data['referenceId'] ?? 'N/A'}',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ImperialCurrency(
            amount: _currencyFormat.format(amount),
            style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.bold),
            iconSize: 12,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    final createdAt = widget.userData['createdAt'] as Timestamp?;
    final dateStr = createdAt != null 
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate()) 
        : 'Desconocido';
    final ip = widget.userData['ipAddress'] ?? 'No registrada';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Fecha de Registro', dateStr),
          const SizedBox(height: 12),
          _buildInfoRow('IP de Registro', ip),
          const SizedBox(height: 30),
          Text(
            'ACCIONES CRÍTICAS',
            style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            'Restablecer Contraseña',
            Icons.lock_reset,
            Colors.orange,
            () {
              // Implement password reset logic
            },
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            'Banear Usuario',
            Icons.block,
            Colors.red,
            () {
              // Implement ban logic
            },
          ),
           const SizedBox(height: 12),
          _buildActionButton(
            'Editar Saldo Manualmente',
            Icons.account_balance_wallet,
            Colors.amber,
            () => _showManualBalanceEditDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.outfit(color: Colors.white54)),
        Text(value, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: Colors.white,
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  void _showManualBalanceEditDialog() {
    final TextEditingController amountController = TextEditingController();
    bool isAdding = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('Editar Saldo Manualmente', style: GoogleFonts.outfit(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Esta acción afectará directamente el saldo del usuario y quedará registrada en el ledger.',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Añadir (+)'),
                      selected: isAdding,
                      onSelected: (val) => setState(() => isAdding = true),
                      selectedColor: Colors.green.withOpacity(0.2),
                      labelStyle: TextStyle(color: isAdding ? Colors.green : Colors.white54),
                      backgroundColor: Colors.black12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Restar (-)'),
                      selected: !isAdding,
                      onSelected: (val) => setState(() => isAdding = false),
                      selectedColor: Colors.red.withOpacity(0.2),
                      labelStyle: TextStyle(color: !isAdding ? Colors.red : Colors.white54),
                      backgroundColor: Colors.black12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.attach_money, color: Colors.amber),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
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
              onPressed: () {
                if (amountController.text.isEmpty) return;
                Navigator.pop(context);
                _showDoubleConfirmation(isAdding, double.tryParse(amountController.text) ?? 0);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDoubleConfirmation(bool isAdding, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('CONFIRMACIÓN FINAL', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '¿Estás SEGURO de que deseas ${isAdding ? 'AÑADIR' : 'RESTAR'} ${_currencyFormat.format(amount)} al usuario ${widget.userData['displayName']}?\n\nEsta acción es irreversible.',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              // Here we would call the cloud function
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Solicitud enviada (Simulación)')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('CONFIRMAR EJECUCIÓN'),
          ),
        ],
      ),
    );
  }
}

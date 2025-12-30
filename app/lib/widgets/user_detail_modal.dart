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
  
  // Design Constants
  final Color _goldColor = const Color(0xFFFFD700);
  final Color _darkBg = const Color(0xFF1A1A2E);
  final Color _surfaceColor = const Color(0xFF252538);

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.9,
            constraints: const BoxConstraints(maxWidth: 1300),
            decoration: BoxDecoration(
              color: _darkBg.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _goldColor.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
                BoxShadow(
                  color: _goldColor.withOpacity(0.05),
                  blurRadius: 50,
                  spreadRadius: 0,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: DefaultTabController(
              length: 2,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildHeader(),
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, _goldColor.withOpacity(0.3), Colors.transparent],
                              ),
                            ),
                          ),
                          _buildFinancialKPIs(),
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.white.withOpacity(0.1), Colors.transparent],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverPersistentHeader(
                      delegate: _SliverAppBarDelegate(
                        _buildTabBar(),
                      ),
                      pinned: true,
                    ),
                  ];
                },
                body: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTransactionsTab(),
                      _buildSecurityTab(),
                    ],
                  ),
                ),
              ),
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
    final isOnline = widget.userData['isOnline'] ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: _surfaceColor.withOpacity(0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with Status Ring
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _goldColor, width: 2),
                  boxShadow: [
                    BoxShadow(color: _goldColor.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)
                  ],
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: _darkBg,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.cinzel(
                      fontSize: 32, 
                      fontWeight: FontWeight.bold, 
                      color: _goldColor
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF00FF88) : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: _darkBg, width: 2),
                    boxShadow: [
                       BoxShadow(
                        color: isOnline ? const Color(0xFF00FF88).withOpacity(0.5) : Colors.transparent,
                        blurRadius: 6,
                       )
                    ]
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 24, 
                          fontWeight: FontWeight.w700, 
                          color: Colors.white,
                          letterSpacing: 0.5
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVip)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _goldColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _goldColor.withOpacity(0.5)),
                        ),
                        child: Text(
                          'VIP',
                          style: GoogleFonts.outfit(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold, 
                            color: _goldColor
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.uid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('ID copiado', style: GoogleFonts.outfit(color: _darkBg)),
                        backgroundColor: _goldColor,
                        behavior: SnackBarBehavior.floating,
                        width: 200,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID: ${widget.uid.substring(0, 8)}...',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 12, 
                            color: Colors.white38,
                            fontWeight: FontWeight.w500
                          ),
                        ),
                        const SizedBox(width: 8),
                         Icon(Icons.copy_rounded, size: 12, color: _goldColor.withOpacity(0.7)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Close Button
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialKPIs() {
    final credit = widget.userData['credit'] ?? 0;
    final totalVolume = widget.userData['totalVolume'] ?? 0; 
    final netPnL = widget.userData['netPnL'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      color: Colors.black.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "RESUMEN FINANCIERO",
            style: GoogleFonts.outfit(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildKPICard('CRÉDITOS', credit, icon: Icons.account_balance_wallet_outlined, isPrimary: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('NET PNL', netPnL, icon: Icons.show_chart, colorize: true)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
             children: [
              Expanded(child: _buildKPICard('VOLUMEN', totalVolume, icon: Icons.equalizer)),
              const SizedBox(width: 12),
              Expanded(child: _buildKPICard('RAKE', widget.userData['rakeGenerated'] ?? 0, icon: Icons.casino_outlined)),
             ],
          )
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, dynamic value, {IconData? icon, bool isPrimary = false, bool colorize = false}) {
    Color valueColor = Colors.white;
    if (colorize) {
      if (value > 0) valueColor = const Color(0xFF00FF88);
      else if (value < 0) valueColor = const Color(0xFFFF4444);
    } else if (isPrimary) {
      valueColor = _goldColor;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimary ? _goldColor.withOpacity(0.1) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary ? _goldColor.withOpacity(0.3) : Colors.white.withOpacity(0.05)
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon, 
                  size: 14, 
                  color: isPrimary ? _goldColor : Colors.white38
                ),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 10, 
                  fontWeight: FontWeight.w600, 
                  color: isPrimary ? _goldColor.withOpacity(0.8) : Colors.white38,
                  letterSpacing: 1
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ImperialCurrency(
             amount: _currencyFormat.format(value),
             style: GoogleFonts.outfit(
               fontSize: 20, 
               fontWeight: FontWeight.bold, 
               color: valueColor
             ),
             iconSize: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _goldColor,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: _goldColor,
        unselectedLabelColor: Colors.white38,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
        overlayColor: MaterialStateProperty.all(_goldColor.withOpacity(0.1)),
        tabs: const [
          Tab(text: 'TRANSACCIONES'),
          Tab(text: 'SEGURIDAD'),
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
          return Center(child: Text('Error', style: TextStyle(color: Colors.white.withOpacity(0.3))));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: PokerLoadingIndicator(size: 30, color: Color(0xFFFFD700)));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 48, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                Text(
                  'Sin actividad reciente',
                  style: GoogleFonts.outfit(color: Colors.white30, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
             // Reuse your proposed logic, refined style
             final type = data['type'] ?? 'UNKNOWN';
             final amount = data['amount'] ?? 0;
             final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
             
             Color color = Colors.grey;
             IconData icon = Icons.circle;
             String label = type.toString().toUpperCase();

             if (type == 'deposit' || type == 'game_win') {
                 color = const Color(0xFF00FF88); // Neon Green
                 icon = Icons.south_west; // Arrow coming in
                 label = type == 'deposit' ? 'DEPÓSITO' : 'GANANCIA';
             } else if (type == 'withdrawal' || type == 'game_loss') {
                 color = const Color(0xFFFF4444); // Neon Red
                 icon = Icons.north_east; // Arrow going out
                 label = type == 'withdrawal' ? 'RETIRO' : 'PÉRDIDA';
             }

             return Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: Colors.white.withOpacity(0.02),
                 borderRadius: BorderRadius.circular(12),
                 border: Border.all(color: Colors.white.withOpacity(0.05)),
               ),
               child: Row(
                 children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14
                            ),
                          ),
                          Text(
                            timestamp != null ? DateFormat('dd MMM, HH:mm').format(timestamp) : '-',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    ImperialCurrency(
                       amount: _currencyFormat.format(amount),
                       style: GoogleFonts.outfit(
                         color: color, 
                         fontWeight: FontWeight.bold,
                         fontSize: 16
                       ),
                       iconSize: 12,
                    ),
                 ],
               ),
             );
          },
        );
      },
    );
  }

  Widget _buildSecurityTab() {
     final createdAt = widget.userData['createdAt'] as Timestamp?;
     final dateStr = createdAt != null 
        ? DateFormat('dd MMMM yyyy, HH:mm').format(createdAt.toDate()) 
        : 'Desconocido';
    final ip = widget.userData['ipAddress'] ?? '---';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INFORMACIÓN DE ALTA',
            style: GoogleFonts.outfit(
              color: _goldColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Fecha de Registro', dateStr, Icons.calendar_today),
          const SizedBox(height: 12),
          _buildInfoRow('IP de Registro', ip, Icons.wifi),
          
          const SizedBox(height: 32),
          Container(height: 1, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 32),
           
          Text(
            'GESTIÓN DE CUENTA',
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          
           _buildActionButton(
             'Resetear Password',
             'Enviar correo de recuperación',
             Icons.lock_reset,
             Colors.orangeAccent,
             () { /* TODO */ },
          ),
          const SizedBox(height: 12),
           _buildActionButton(
             'Suspender Cuenta',
             'Restringir acceso temporalmente',
             Icons.block,
             Colors.redAccent,
             () { /* TODO */ },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white30),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
          const Spacer(),
          Text(value, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildActionButton(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: GoogleFonts.outfit(
                      color: Colors.white, 
                      fontWeight: FontWeight.w600,
                      fontSize: 16
                    )
                  ),
                  Text(
                    subtitle, 
                    style: GoogleFonts.outfit(
                      color: Colors.white38, 
                      fontSize: 12
                    )
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: color.withOpacity(0.5)),
          ],
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
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _goldColor.withOpacity(0.2))
          ),
          title: Row(
            children: [
              Icon(Icons.tune, color: _goldColor),
              const SizedBox(width: 12),
              Text('Ajuste de Saldo', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Seleccione operación y monto para ajustar el saldo del usuario.',
                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => isAdding = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isAdding ? Colors.green.withOpacity(0.2) : Colors.black26,
                          border: Border.all(color: isAdding ? Colors.green : Colors.transparent),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'AÑADIR (+)', 
                            style: GoogleFonts.outfit(
                                color: isAdding ? Colors.green : Colors.white38,
                                fontWeight: FontWeight.bold
                            )
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => isAdding = false),
                      child: Container(
                         padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !isAdding ? Colors.red.withOpacity(0.2) : Colors.black26,
                          border: Border.all(color: !isAdding ? Colors.red : Colors.transparent),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'RESTAR (-)', 
                            style: GoogleFonts.outfit(
                                color: !isAdding ? Colors.red : Colors.white38,
                                fontWeight: FontWeight.bold
                            )
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: Icon(Icons.attach_money, color: _goldColor),
                  filled: true,
                  fillColor: Colors.black12,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _goldColor)),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR', style: GoogleFonts.outfit(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (amountController.text.isEmpty) return;
                Navigator.pop(context);
                _showDoubleConfirmation(isAdding, double.tryParse(amountController.text) ?? 0);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _goldColor, 
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              ),
              child: Text('CONTINUAR', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('CONFIRMACIÓN', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '¿Está seguro de querer ${isAdding ? 'AÑADIR' : 'RESTAR'} ${_currencyFormat.format(amount)} a este usuario? Esta acción es irreversible.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Call cloud function
              Navigator.pop(context);
               ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Operación simulada con éxito', style: GoogleFonts.outfit(color: Colors.black)),
                    backgroundColor: _goldColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('EJECUTAR'),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => 48.0; // Standard TabBar height
  @override
  double get maxExtent => 48.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _tabBar;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

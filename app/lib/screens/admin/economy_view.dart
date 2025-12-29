import 'package:flutter/material.dart';
import '../../widgets/imperial_currency.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../widgets/admin/economic_kpis.dart';
import '../../widgets/admin/trend_charts.dart';
import '../../widgets/admin/risk_analysis_tables.dart';
import 'package:google_fonts/google_fonts.dart';

class EconomyView extends StatefulWidget {
  const EconomyView({super.key});

  @override
  State<EconomyView> createState() => _EconomyViewState();
}

class _EconomyViewState extends State<EconomyView> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  
  bool _isLoading = false;
  late TabController _tabController;

  // Selected User for Autocomplete
  Map<String, dynamic>? _selectedUser;

  // Stats Data
  Map<String, dynamic> _currentStats = {};
  List<Map<String, dynamic>> _dailyStats = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _fetchCurrentStats(),
      _fetchDailyStats(),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _fetchCurrentStats() async {
    try {
      final statsResult = await FirebaseFunctions.instance.httpsCallable('getSystemStatsFunction').call();
      final dynamic resultData = statsResult.data;
      
      if (resultData is Map) {
         _currentStats = {
            'totalCirculation': resultData['totalCirculation'] ?? 0,
            'accumulatedRake': resultData['accumulated_rake'] ?? 0,
         };
      }
      
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final yStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2,'0')}-${yesterday.day.toString().padLeft(2,'0')}";
      
      final dailyDoc = await FirebaseFirestore.instance.collection('stats_daily').doc(yStr).get();
      if (dailyDoc.exists) {
          final data = dailyDoc.data()!;
          _currentStats['volume24h'] = data['totalVolume'] ?? 0;
          _currentStats['turnover24h'] = data['handsPlayed'] ?? 0; 
          _currentStats['ggr24h'] = data['totalRake'] ?? 0;
      } else {
          _currentStats['volume24h'] = 0;
          _currentStats['turnover24h'] = 0;
          _currentStats['ggr24h'] = 0;
      }

    } catch (e) {
      debugPrint('Error fetching stats: $e');
    }
  }

  Future<void> _fetchDailyStats() async {
      try {
          final snapshot = await FirebaseFirestore.instance
              .collection('stats_daily')
              .orderBy('date', descending: false)
              .limitToLast(7)
              .get();
          
          _dailyStats = snapshot.docs.map((doc) => doc.data()).toList();
      } catch (e) {
          debugPrint('Error fetching daily stats: $e');
      }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _uidController.dispose();
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    if (query.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('displayName', isGreaterThanOrEqualTo: query)
        .where('displayName', isLessThan: '${query}z')
        .limit(10)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'displayName': data['displayName'] ?? 'Unknown',
        'email': data['email'] ?? '',
        'credits': data['credit'] ?? data['credits'] ?? 0,
      };
    }).toList();
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_uidController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor seleccione un usuario')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final isMinting = _tabController.index == 0;
    final functionName = isMinting ? 'adminMintCreditsFunction' : 'adminWithdrawCreditsFunction';
    final actionName = isMinting ? 'inyectados' : 'retirados';

    try {
      await FirebaseFunctions.instance.httpsCallable(functionName).call({
        'targetUid': _uidController.text.trim(),
        'amount': int.parse(_amountController.text.trim()),
        'reason': _reasonController.text.trim().isEmpty 
            ? 'Admin ${isMinting ? 'Mint' : 'Burn'}' 
            : _reasonController.text.trim(),
      });

      if (mounted) {
        setState(() => _isLoading = false);
        _amountController.clear();
        _reasonController.clear();
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Créditos $actionName correctamente'),
             backgroundColor: isMinting ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
           ),
        );
        
        // Refresh stats
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Cards (Liquidity & Rake)
          _buildStatsSection(),
          
          // 2. New KPIs (Volume, Turnover, GGR)
          EconomicKPIs(
              volume24h: (_currentStats['volume24h'] ?? 0).toDouble(),
              turnover24h: (_currentStats['turnover24h'] ?? 0).toInt(),
              ggr24h: (_currentStats['ggr24h'] ?? 0).toDouble(),
          ),
          
          const SizedBox(height: 32),
          
          // 3. Trend Charts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              "TENDENCIAS DEL MERCADO",
               style: GoogleFonts.outfit(color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          TrendCharts(dailyStats: _dailyStats),
          
          const SizedBox(height: 32),

          // 4. Risk Analysis Tables
           Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              "ANÁLISIS DE RIESGO",
               style: GoogleFonts.outfit(color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          const RiskAnalysisTables(),

          const SizedBox(height: 48),
          
          // 5. Admin Actions (Mint/Burn)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.5), width: 2)),
              ),
              child: Text(
                'BANCO CENTRAL (GESTIÓN MONETARIA)', 
                style: GoogleFonts.cinzel(
                  color: const Color(0xFFFFD700), 
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2
                )
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildMintBurnForm(),
          
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMintBurnForm() {
      final isMinting = _tabController.index == 0;
      final primaryColor = isMinting ? const Color(0xFF00FF88) : const Color(0xFFFF4444);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
             color: const Color(0xFF1E1E2C),
             borderRadius: BorderRadius.circular(24),
             border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
             boxShadow: [
               BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 0),
             ]
          ),
          child: Column(
            children: [
               // Custom Tab Bar
               Container(
                 margin: const EdgeInsets.all(8),
                 height: 50,
                 decoration: BoxDecoration(
                   color: Colors.black26,
                   borderRadius: BorderRadius.circular(16),
                 ),
                 child: TabBar(
                   controller: _tabController,
                   indicator: BoxDecoration(
                     color: isMinting ? const Color(0xFF00FF88).withOpacity(0.2) : const Color(0xFFFF4444).withOpacity(0.2),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: isMinting ? const Color(0xFF00FF88) : const Color(0xFFFF4444)),
                   ),
                   labelColor: Colors.white,
                   unselectedLabelColor: Colors.white38,
                   labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                   overlayColor: MaterialStateProperty.all(Colors.transparent),
                   tabs: [
                     Tab(
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: const [
                           Icon(Icons.add_circle, size: 18),
                           SizedBox(width: 8),
                           Text('EMISIÓN (MINT)'),
                         ],
                       ),
                     ),
                     Tab(
                        child: Row(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: const [
                           Icon(Icons.remove_circle, size: 18),
                           SizedBox(width: 8),
                           Text('QUEMA (BURN)'),
                         ],
                       ),
                     ),
                   ],
                 ),
               ),
               
               Padding(
                 padding: const EdgeInsets.all(32.0),
                 child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          isMinting 
                              ? 'AUMENTAR CIRCULANTE TOTAL' 
                              : 'REDUCIR CIRCULANTE TOTAL',
                          style: GoogleFonts.outfit(
                            color: primaryColor, 
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          isMinting
                            ? 'Los créditos serán creados e inyectados a la cuenta del usuario.'
                            : 'Los créditos serán retirados permanentemente de la economía.',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 40),
            
                      // User Autocomplete
                      Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          return _searchUsers(textEditingValue.text);
                        },
                        displayStringForOption: (option) => '${option['displayName']} (${option['email']})',
                        onSelected: (Map<String, dynamic> selection) {
                          setState(() {
                            _selectedUser = selection;
                            _uidController.text = selection['uid'];
                          });
                        },
                        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: textController,
                            focusNode: focusNode,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
                            decoration: InputDecoration(
                              labelText: 'BUSCAR USUARIO',
                              labelStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, letterSpacing: 1),
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.3),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), 
                                borderSide: BorderSide(color: primaryColor.withOpacity(0.5))
                              ),
                              prefixIcon: Icon(Icons.search, color: primaryColor),
                              helperText: _selectedUser != null 
                                  ? 'Saldo Actual: \$${_selectedUser!['credits']}' 
                                  : null,
                              helperStyle: GoogleFonts.outfit(color: const Color(0xFFFFD700)),
                            ),
                            validator: (v) {
                                if (_uidController.text.isEmpty) return 'Debe seleccionar un usuario';
                                return null;
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 20.0,
                              color: const Color(0xFF2A2A3E),
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 400, 
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(option['displayName'], style: GoogleFonts.outfit(color: Colors.white)),
                                      subtitle: Text(option['email'], style: GoogleFonts.outfit(color: Colors.white54)),
                                      trailing: ImperialCurrency(amount: option['credits'], style: GoogleFonts.outfit(color: const Color(0xFFFFD700)), iconSize: 14),
                                      onTap: () => onSelected(option),
                                      hoverColor: primaryColor.withOpacity(0.1),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
            
                      const SizedBox(height: 24),
                      
                      // Amount Field
                      TextFormField(
                        controller: _amountController,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'MONTO',
                          labelStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, letterSpacing: 1),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), 
                                borderSide: BorderSide(color: primaryColor.withOpacity(0.5))
                          ),
                          prefixIcon: Icon(Icons.attach_money, color: primaryColor),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          if (int.tryParse(v) == null) return 'Debe ser un número entero';
                          return null;
                        },
                      ),
            
                      const SizedBox(height: 24),
            
                      // Reason Field
                      TextFormField(
                        controller: _reasonController,
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'MOTIVO (OPCIONAL)',
                          labelStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, letterSpacing: 1),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), 
                                borderSide: BorderSide(color: primaryColor.withOpacity(0.5))
                          ),
                          prefixIcon: Icon(Icons.description, color: Colors.white30),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitTransaction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            shadowColor: primaryColor.withOpacity(0.5),
                            elevation: 8,
                          ),
                          child: _isLoading 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : Text(
                                isMinting ? 'CONFIRMAR INYECCIÓN' : 'CONFIRMAR RETIRO',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                              ),
                        ),
                      ),
                    ],
                  ),
                             ),
               ),
            ],
          ),
        ),
      );
  }

  Widget _buildStatsSection() {
    final liquidity = _currentStats['totalCirculation'] ?? 0;
    final houseRake = _currentStats['accumulatedRake'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            child: _buildImperialStatCard(
              title: 'LIQUIDEZ TOTAL',
              amount: liquidity,
              icon: Icons.account_balance,
              color: Colors.blueAccent, 
              // Keep blue for liquidity as it's standard, but could be Gold? 
              // Let's stick to theme: Liquidity = Business Blue/Gold.
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildImperialStatCard(
              title: 'GANANCIAS CASA (RAKE)',
              amount: houseRake,
              icon: Icons.diamond,
              color: const Color(0xFF00FF88), // Profit is Green
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImperialStatCard({
      required String title,
      required dynamic amount,
      required IconData icon,
      required Color color,
  }) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          image: const DecorationImage(
             image: AssetImage('assets/images/card_bg_overlay.png'), // Subtle texture if available, or just fallback
             fit: BoxFit.cover,
             opacity: 0.05,
          ),
          gradient: LinearGradient(
             colors: [const Color(0xFF1E1E2C), const Color(0xFF14141F)],
             begin: Alignment.topLeft,
             end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
             BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 4))
          ]
        ),
        child: Row(
          children: [
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: color.withOpacity(0.1),
                 shape: BoxShape.circle,
               ),
               child: Icon(icon, color: color, size: 28),
             ),
             const SizedBox(width: 20),
             Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   title, 
                   style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                 ),
                 ImperialCurrency(
                    amount: amount, 
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    iconSize: 22,
                 ),
               ],
             ),
          ],
        ),
      );
  }
}

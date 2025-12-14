import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../widgets/admin/economic_kpis.dart';
import '../../widgets/admin/trend_charts.dart';
import '../../widgets/admin/risk_analysis_tables.dart';

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
      // Get basic stats from Cloud Function
      final statsResult = await FirebaseFunctions.instance.httpsCallable('getSystemStatsFunction').call();
      final dynamic resultData = statsResult.data;
      
      if (resultData is Map) {
         _currentStats = {
            'totalCirculation': resultData['totalCirculation'] ?? 0,
            'accumulatedRake': resultData['accumulatedRake'] ?? 0,
         };
      }
      
      // Also fetch today's stats for KPIs (Volume, Turnover, GGR)
      // We can get this from stats_daily/TODAY if cron ran (it runs at midnight, so it shows yesterday).
      // For REAL-TIME today stats, we might need to query ledger or just show yesterday's finished stats.
      // Let's show "Last 24h" which usually implies yesterday's full day or rolling.
      // For simplicity and performance, let's fetch the latest entry from stats_daily.
      
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final yStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2,'0')}-${yesterday.day.toString().padLeft(2,'0')}";
      
      final dailyDoc = await FirebaseFirestore.instance.collection('stats_daily').doc(yStr).get();
      if (dailyDoc.exists) {
          final data = dailyDoc.data()!;
          _currentStats['volume24h'] = data['totalVolume'] ?? 0;
          _currentStats['turnover24h'] = data['handsPlayed'] ?? 0; // Assuming we added this to cron/index
          _currentStats['ggr24h'] = data['totalRake'] ?? 0;
      } else {
          // If no data for yesterday (cron hasn't run or new system), show 0
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

  // Search users by name/username
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
             backgroundColor: isMinting ? Colors.green : Colors.red,
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
          // 1. Top Cards (Liquidity & Rake) - Existing
          _buildStatsSection(),
          
          // 2. New KPIs (Volume, Turnover, GGR)
          EconomicKPIs(
              volume24h: (_currentStats['volume24h'] ?? 0).toDouble(),
              turnover24h: (_currentStats['turnover24h'] ?? 0).toInt(),
              ggr24h: (_currentStats['ggr24h'] ?? 0).toDouble(),
          ),
          
          const SizedBox(height: 24),
          
          // 3. Trend Charts
          TrendCharts(dailyStats: _dailyStats),
          
          const SizedBox(height: 24),

          // 4. Risk Analysis Tables
          const RiskAnalysisTables(),

          const SizedBox(height: 32),
          const Divider(color: Colors.white24),
          const SizedBox(height: 32),

          // 5. Admin Actions (Mint/Burn) - Existing but styled
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Gestión Monetaria (Banco Central)', style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          _buildMintBurnForm(),
          
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildMintBurnForm() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          color: const Color(0xFF1A1A2E),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.white70,
                      tabs: const [
                        Tab(text: 'INYECTAR (MINT)', icon: Icon(Icons.add_circle_outline)),
                        Tab(text: 'RETIRAR (BURN)', icon: Icon(Icons.remove_circle_outline)),
                      ],
                      onTap: (index) {
                        setState(() {}); 
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    _tabController.index == 0 
                        ? 'Emisión de Moneda' 
                        : 'Quema de Moneda',
                    style: TextStyle(
                      color: _tabController.index == 0 ? Colors.green : Colors.redAccent, 
                      fontSize: 18, 
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tabController.index == 0
                      ? 'Aumenta el circulante total. Use con precaución.'
                      : 'Reduce el circulante total. Use para correcciones o cashouts.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 24),

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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Buscar Usuario (Nombre)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search, color: Colors.amber),
                          helperText: _selectedUser != null 
                              ? 'UID: ${_selectedUser!['uid']}\nSaldo Actual: \$${_selectedUser!['credits']}' 
                              : null,
                          helperStyle: const TextStyle(color: Colors.greenAccent),
                        ),
                        validator: (v) {
                            if (_uidController.text.isEmpty) return 'Debe seleccionar un usuario de la lista';
                            return null;
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          color: const Color(0xFF2A2A3E),
                          child: SizedBox(
                            width: 300, 
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option['displayName'], style: const TextStyle(color: Colors.white)),
                                  subtitle: Text(option['email'], style: const TextStyle(color: Colors.white54)),
                                  trailing: Text('\$${option['credits']}', style: const TextStyle(color: Colors.amber)),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),
                  
                  // Amount Field
                  TextFormField(
                    controller: _amountController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money, color: Colors.amber),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requerido';
                      if (int.tryParse(v) == null) return 'Debe ser un número entero';
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Reason Field
                  TextFormField(
                    controller: _reasonController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Motivo (Opcional)',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description, color: Colors.amber),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitTransaction,
                      icon: Icon(_tabController.index == 0 ? Icons.add : Icons.remove),
                      label: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_tabController.index == 0 ? 'CONFIRMAR INYECCIÓN' : 'CONFIRMAR RETIRO'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tabController.index == 0 ? Colors.green : Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildStatsSection() {
        final liquidity = _currentStats['totalCirculation'] ?? 0;
        final houseRake = _currentStats['accumulatedRake'] ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Row(
            children: [
              // Liquidity Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    border: Border.all(color: Colors.blue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop, color: Colors.blue, size: 32),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Liquidity', style: TextStyle(color: Colors.white70)),
                          Text('\$${liquidity.toString()}', style: const TextStyle(color: Colors.blue, fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // House Revenue Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.casino, color: Colors.green, size: 32),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ganancias Casa (Rake)', style: TextStyle(color: Colors.white70)),
                          Text('\$${houseRake.toString()}', style: const TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }
}

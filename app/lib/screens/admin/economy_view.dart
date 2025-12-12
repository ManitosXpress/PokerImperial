import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class EconomyView extends StatefulWidget {
  const EconomyView({super.key});

  @override
  State<EconomyView> createState() => _EconomyViewState();
}

class _EconomyViewState extends State<EconomyView> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController(); // Added reason
  
  bool _isLoading = false;
  late TabController _tabController;

  // Selected User for Autocomplete
  Map<String, dynamic>? _selectedUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

    // Search by displayName or username
    // Note: This is a simple prefix search. For better search, use Algolia/Typesense.
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
        'credits': data['credit'] ?? data['credits'] ?? 0, // Handle plural inconsistency
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
        // Keep selected user for convenience or clear it? Let's keep it but maybe clear amount.
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Créditos $actionName correctamente'),
             backgroundColor: isMinting ? Colors.green : Colors.red,
           ),
        );
        
        // Refresh stats by forcing a rebuild
        setState(() {}); 
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
    return Column(
      children: [
        // Stats Section (Global)
        _buildStatsSection(),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                            setState(() {}); // Rebuild to update button color/text
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      Text(
                        _tabController.index == 0 
                            ? 'Banco Central: Emisión de Moneda' 
                            : 'Banco Central: Quema de Moneda',
                        style: TextStyle(
                          color: _tabController.index == 0 ? Colors.green : Colors.redAccent, 
                          fontSize: 20, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _tabController.index == 0
                          ? 'Aumenta el circulante total. Use con precaución.'
                          : 'Reduce el circulante total. Use para correcciones o cashouts.',
                        style: const TextStyle(color: Colors.white70),
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
                                width: 300, // Or dynamic width
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
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchStats(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final liquidity = data['totalCirculation'] ?? 0;
        final houseRake = data['accumulatedRake'] ?? 0;

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
      },
    );
  }

  Future<Map<String, dynamic>> _fetchStats() async {
      try {
          // Get basic stats from Cloud Function
          final statsResult = await FirebaseFunctions.instance.httpsCallable('getSystemStatsFunction').call();
          // Access 'data' from HttpsCallableResult, then cast to Map. 
          // Note: In some SDK versions, .data is already the result.
          // Let's handle dynamic type safely.
          final dynamic resultData = statsResult.data;
          
          if (resultData is Map) {
              return {
                  'totalCirculation': resultData['totalCirculation'] ?? 0,
                  'accumulatedRake': resultData['accumulatedRake'] ?? 0,
              };
          } else {
             // Fallback if structure is unexpected
             return {};
          }
      } catch (e) {
          debugPrint('Error fetching stats: $e');
          // If function fails, try reading Firestore directly as fallback for rake
          try {
             final economyDoc = await FirebaseFirestore.instance.collection('system_stats').doc('economy').get();
             final rake = economyDoc.data()?['accumulated_rake'] ?? 0;
             final circulation = economyDoc.data()?['totalCirculation'] ?? 0;
             return {
                 'totalCirculation': circulation,
                 'accumulatedRake': rake
             };
          } catch (e2) {
             return {};
          }
      }
  }
}

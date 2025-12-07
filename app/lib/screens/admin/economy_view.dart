import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EconomyView extends StatefulWidget {
  const EconomyView({super.key});

  @override
  State<EconomyView> createState() => _EconomyViewState();
}

class _EconomyViewState extends State<EconomyView> {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isLoading = false;

  Future<void> _mintCredits() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFunctions.instance.httpsCallable('adminMintCreditsFunction').call({
        'targetUid': _uidController.text.trim(),
        'amount': int.parse(_amountController.text.trim()),
      });

      if (mounted) {
        setState(() => _isLoading = false);
        _uidController.clear();
        _amountController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créditos inyectados correctamente')),
        );
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
    return Center(
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
                  // Stats Section
                  FutureBuilder<HttpsCallableResult>(
                    future: FirebaseFunctions.instance.httpsCallable('getSystemStatsFunction').call(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final data = snapshot.data!.data as Map<String, dynamic>;
                      final liquidity = data['totalCirculation'] ?? 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.monetization_on, color: Colors.green, size: 32),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Liquidity (Circulante)', style: TextStyle(color: Colors.white70)),
                                Text('\$${liquidity.toString()}', style: const TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const Text(
                    'Banco Central (Minting)',
                    style: TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Inyectar créditos en la billetera de un usuario. Esta acción aumenta el circulante total.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _uidController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'UID del Usuario Destino',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person, color: Colors.amber),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monto a Inyectar',
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _mintCredits,
                      icon: const Icon(Icons.account_balance_wallet),
                      label: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('INYECTAR CRÉDITOS'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
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
    );
  }
}

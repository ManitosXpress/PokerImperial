import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/imperial_currency.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/poker_loading_indicator.dart';

class TournamentCMSView extends StatefulWidget {
  const TournamentCMSView({super.key});

  @override
  State<TournamentCMSView> createState() => _TournamentCMSViewState();
}

class _TournamentCMSViewState extends State<TournamentCMSView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => const _CreateTournamentDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('tournaments')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (!snapshot.hasData) return const Center(child: PokerLoadingIndicator(size: 40, color: Colors.amber));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No hay torneos creados.', style: TextStyle(color: Colors.white54)));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final tournamentId = docs[index].id;
              final status = data['status'] ?? '';
              final showGodModeButton = status == 'RUNNING' || status == 'REGISTERING';

              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(data['name'] ?? 'Sin Nombre', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Buy-In: ', style: TextStyle(color: Colors.white70)),
                      ImperialCurrency(amount: data['buyIn'], style: const TextStyle(color: Colors.white70), iconSize: 14),
                      Text(' | Tipo: ${data['type']} | Estado: ${data['status']}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  trailing: showGodModeButton
                      ? ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/tournament-lobby',
                              arguments: {
                                'tournamentId': tournamentId,
                                'isAdminMode': true,
                              },
                            );
                          },
                          icon: const Icon(Icons.bolt, size: 18),
                          label: const Text('GESTIONAR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB71C1C), // Deep Red
                            foregroundColor: const Color(0xFFD4AF37), // Gold
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        )
                      : const Icon(Icons.chevron_right, color: Colors.white54),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CreateTournamentDialog extends StatefulWidget {
  const _CreateTournamentDialog();

  @override
  State<_CreateTournamentDialog> createState() => _CreateTournamentDialogState();
}

class _CreateTournamentDialogState extends State<_CreateTournamentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _buyInController = TextEditingController();
  String _type = 'Open';
  bool _isLoading = false;

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFunctions.instance.httpsCallable('createTournamentFunction').call({
        'name': _nameController.text,
        'buyIn': int.parse(_buyInController.text),
        'type': _type,
        // No clubId needed for admin/official tournaments
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Torneo creado correctamente')),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Crear Torneo Oficial', style: TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Nombre del Torneo', labelStyle: TextStyle(color: Colors.white70)),
              validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _buyInController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Buy-In', labelStyle: TextStyle(color: Colors.white70)),
              validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _type,
              dropdownColor: const Color(0xFF16213E),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Tipo', labelStyle: TextStyle(color: Colors.white70)),
              items: const [
                DropdownMenuItem(value: 'Open', child: Text('Abierto')),
                DropdownMenuItem(value: 'Inter-club', child: Text('Inter-club')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _create,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
          child: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
            : const Text('Crear'),
        ),
      ],
    );
  }
}

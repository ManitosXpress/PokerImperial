import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';

class CreateTournamentScreen extends StatefulWidget {
  final String? clubId;

  const CreateTournamentScreen({super.key, this.clubId});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameController = TextEditingController();
  final _buyInController = TextEditingController();
  String _selectedType = 'Open';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Tournament'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Tournament Name',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _buyInController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Buy-in Amount',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: widget.clubId != null ? 'Club' : _selectedType,
              dropdownColor: const Color(0xFF16213E),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Tournament Type',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
              ),
              items: (widget.clubId != null ? ['Club'] : ['Open', 'Inter-club']).map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: widget.clubId != null ? null : (newValue) { // Disable if clubId is set
                setState(() {
                  _selectedType = newValue!;
                });
              },
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (_nameController.text.isNotEmpty && _buyInController.text.isNotEmpty) {
                    // If clubId is present, use 'Club' type, otherwise use selected
                    final type = widget.clubId != null ? 'Club' : _selectedType;
                    
                    // We need to update createTournament in provider to accept clubId
                    // For now, we'll pass it as part of the data map if we were using a map, 
                    // but the provider method signature needs update.
                    // Let's assume we update the provider next.
                    
                    await Provider.of<TournamentProvider>(context, listen: false).createTournament(
                      _nameController.text,
                      int.parse(_buyInController.text),
                      type,
                      clubId: widget.clubId,
                    );
                    if (mounted) Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                ),
                child: const Text('Create Tournament'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

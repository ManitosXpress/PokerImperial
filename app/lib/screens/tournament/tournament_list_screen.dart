import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import 'create_tournament_screen.dart';
import '../../widgets/poker_loading_indicator.dart';

class TournamentListScreen extends StatefulWidget {
  const TournamentListScreen({super.key});

  @override
  State<TournamentListScreen> createState() => _TournamentListScreenState();
}

class _TournamentListScreenState extends State<TournamentListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => 
      Provider.of<TournamentProvider>(context, listen: false).fetchTournaments()
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TournamentProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: provider.isLoading
            ? const Center(
                child: PokerLoadingIndicator(
                  statusText: 'Loading Tournaments...',
                  color: Color(0xFFFFD700),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: provider.tournaments.length,
                itemBuilder: (context, index) {
                  final tournament = provider.tournaments[index];
                  return Card(
                    color: Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.emoji_events, color: Colors.amber),
                      title: Text(
                        tournament['name'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buy-in: ${tournament['buyIn']} | Prize: ${tournament['prizePool']}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Type: ${tournament['type']}',
                            style: TextStyle(
                              color: tournament['type'] == 'Inter-club' ? Colors.purpleAccent : Colors.greenAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          // Join logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Register'),
                      ),
                    ),
                  );
                },
              ),
      ),

    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import '../tournament/create_tournament_screen.dart';

class ClubTournamentsScreen extends StatefulWidget {
  final String clubId;
  final bool isOwner;

  const ClubTournamentsScreen({
    super.key,
    required this.clubId,
    required this.isOwner,
  });

  @override
  State<ClubTournamentsScreen> createState() => _ClubTournamentsScreenState();
}

class _ClubTournamentsScreenState extends State<ClubTournamentsScreen> {
  List<Map<String, dynamic>> _tournaments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTournaments();
  }

  Future<void> _loadTournaments() async {
    setState(() => _isLoading = true);
    final tournaments = await Provider.of<ClubProvider>(context, listen: false)
        .fetchClubTournaments(widget.clubId);
    if (mounted) {
      setState(() {
        _tournaments = tournaments;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Tournaments'),
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _tournaments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events_outlined,
                            size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        const Text(
                          'No tournaments yet',
                          style: TextStyle(color: Colors.white54, fontSize: 18),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tournaments.length,
                    itemBuilder: (context, index) {
                      final tournament = _tournaments[index];
                      return Card(
                        color: Colors.white.withOpacity(0.05),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.emoji_events, color: Colors.amber),
                          title: Text(
                            tournament['name'],
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Buy-in: ${tournament['buyIn']} | Prize: ${tournament['prizePool']}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              // Join logic
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Join'),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateTournamentScreen(clubId: widget.clubId),
                  ),
                );
                _loadTournaments();
              },
              label: const Text('Create Tournament'),
              icon: const Icon(Icons.add),
              backgroundColor: const Color(0xFFE94560),
            )
          : null,
    );
  }
}

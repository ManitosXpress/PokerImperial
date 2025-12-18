import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import '../../providers/wallet_provider.dart';
import '../tournament/create_tournament_screen.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../../widgets/tournament/tournament_list_item.dart';
import '../../widgets/tournament/club_hall_of_fame.dart';
import '../tournament/tournament_lobby_screen.dart';

class ClubTournamentsScreen extends StatefulWidget {
  final String clubId;
  final bool isOwner;
  final bool isEmbedded;

  const ClubTournamentsScreen({
    super.key,
    required this.clubId,
    required this.isOwner,
    this.isEmbedded = false,
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
    if (widget.isEmbedded) {
      return _buildContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TORNEOS DEL CLUB',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F0F1E)],
          ),
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        _isLoading
            ? const Center(
                child: PokerLoadingIndicator(
                  statusText: 'Cargando Torneos...',
                  color: Color(0xFFFFD700),
                ),
              )
            : Column(
                children: [
                  // Hall of Fame
                  ClubHallOfFame(clubId: widget.clubId),
                  // Tournaments List
                  Expanded(
                    child: _tournaments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.emoji_events_outlined,
                                    size: 64, color: Colors.white24),
                                SizedBox(height: 16),
                                Text(
                                  'No hay torneos todavía',
                                  style: TextStyle(color: Colors.white54, fontSize: 18),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '¡Crea el primer torneo del club!',
                                  style: TextStyle(color: Colors.white38, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _tournaments.length,
                            itemBuilder: (context, index) {
                              final tournament = _tournaments[index];
                              return TournamentListItem(
                                tournament: tournament,
                                onJoin: () => _handleJoinTournament(tournament),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ],
    );
  }

  void _handleJoinTournament(Map<String, dynamic> tournament) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TournamentLobbyScreen(
          tournamentId: tournament['id'],
        ),
      ),
    );
  }

}

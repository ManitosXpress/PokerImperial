import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import '../../providers/wallet_provider.dart';
import '../tournament/create_tournament_screen.dart';
import '../../widgets/poker_loading_indicator.dart';
import '../../widgets/tournament/tournament_list_item.dart';
import '../../widgets/tournament/club_hall_of_fame.dart';

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
      floatingActionButton: _buildFloatingActionButton(),
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
        // If embedded, show FAB in bottom right of the tab view
        if (widget.isEmbedded && widget.isOwner)
          Positioned(
            bottom: 16,
            right: 16,
            child: _buildFloatingActionButton()!,
          ),
      ],
    );
  }

  void _handleJoinTournament(Map<String, dynamic> tournament) {
    final buyIn = (tournament['buyIn'] as num).toDouble();
    final balance = Provider.of<WalletProvider>(context, listen: false).balance;

    if (balance < buyIn) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE94560), width: 2),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE94560), size: 32),
              SizedBox(width: 12),
              Text(
                'Saldo Insuficiente',
                style: TextStyle(color: Color(0xFFE94560)),
              ),
            ],
          ),
          content: const Text(
            'No tienes créditos suficientes para entrar al torneo.\n\n'
            'Por favor, comunícate con tu líder de club para cargar más crédito.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Entendido',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } else {
      // Proceed with join logic (to be implemented)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Uniéndose al torneo... (Lógica pendiente)'),
            ],
          ),
          backgroundColor: const Color(0xFF00C851),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget? _buildFloatingActionButton() {
    if (!widget.isOwner) return null;
    
    return FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTournamentScreen(clubId: widget.clubId),
          ),
        );
        _loadTournaments();
      },
      label: const Text(
        'CREAR TORNEO',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      icon: const Icon(Icons.add_circle_outline, size: 24),
      backgroundColor: const Color(0xFFE94560),
      elevation: 8,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}

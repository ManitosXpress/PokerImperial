import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/imperial_currency.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/club_provider.dart';
import '../game_screen.dart';
import '../../widgets/tournament/god_mode_admin_panel.dart';

class TournamentLobbyScreen extends StatefulWidget {
  final String tournamentId;
  final bool isAdminMode; // GOD MODE parameter

  const TournamentLobbyScreen({
    super.key,
    required this.tournamentId,
    this.isAdminMode = false, // Default to normal mode
  });

  @override
  State<TournamentLobbyScreen> createState() => _TournamentLobbyScreenState();
}

class _TournamentLobbyScreenState extends State<TournamentLobbyScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isRegistering = false;
  bool _isUnregistering = false;
  
  // Auto-redirect control variables
  bool _hasRedirected = false;
  StreamSubscription<DocumentSnapshot>? _tournamentSubscription;

  @override
  void initState() {
    super.initState();
    _setupAutoJoinListener();
  }

  /// Sets up a listener to automatically redirect registered players
  /// to their assigned table when the tournament starts.
  void _setupAutoJoinListener() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _tournamentSubscription = FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'REGISTERING';
      final activeTableId = data['activeTableId'] as String?;

      // Check if tournament is running and has an active table
      final isRunning = status == 'RUNNING' || status == 'active' || status == 'started';

      if (isRunning && activeTableId != null && !_hasRedirected) {
        // Check if the current user is a registered participant
        final registeredPlayerIds = List<String>.from(data['registeredPlayerIds'] ?? []);
        
        if (registeredPlayerIds.contains(currentUserId)) {
          _hasRedirected = true;
          print('🚀 Torneo iniciado. Redirigiendo automáticamente a mesa: $activeTableId');
          
          // Navigate to the game screen
          final isCreator = data['createdBy'] == currentUserId;
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => GameScreen(
                roomId: activeTableId,
                isTournamentMode: true,
                autoStart: isCreator, // Host auto-starts the game
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _tournamentSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _registerForTournament() async {
    setState(() => _isRegistering = true);

    try {
      final result = await Provider.of<TournamentProvider>(context, listen: false)
          .registerForTournament(widget.tournamentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains(']')) {
          errorMessage = errorMessage.split(']').last.trim();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegistering = false);
      }
    }
  }

  Future<void> _unregisterFromTournament() async {
    setState(() => _isUnregistering = true);

    try {
      final result = await Provider.of<TournamentProvider>(context, listen: false)
          .unregisterFromTournament(widget.tournamentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains(']')) {
          errorMessage = errorMessage.split(']').last.trim();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUnregistering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'LOBBY DEL TORNEO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
              ),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
            );
          }

          final tournament = snapshot.data!.data() as Map<String, dynamic>;
          final registeredPlayerIds = List<String>.from(tournament['registeredPlayerIds'] ?? []);
          final isRegistered = registeredPlayerIds.contains(currentUser?.uid);
          final tournamentStatus = tournament['status'] ?? 'REGISTERING';
          final canRegister = tournamentStatus == 'REGISTERING' || tournamentStatus == 'LATE_REG';
          final activeTableId = tournament['activeTableId'];

          return Stack(
            children: [
              // Background Image
              Positioned.fill(
                child: Image.asset(
                  'assets/images/tournament_lobby_bg.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Dark Overlay
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.85),
                ),
              ),
              // Content
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          // Tournament Header
                          SliverToBoxAdapter(
                            child: _buildTournamentHeader(tournament, widget.isAdminMode),
                          ),
                          
                          // God Mode Admin Panel (only for admins)
                          if (widget.isAdminMode)
                            SliverToBoxAdapter(
                              child: GodModeAdminPanel(
                                tournament: tournament,
                                tournamentId: widget.tournamentId,
                              ),
                            ),
                          
                          // Main Content Area (Players & Chat)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: SizedBox(
                              height: 600, // Fixed minimal height to ensure chat is usable
                              child: Row(
                                children: [
                                  // Left Panel: Tournament Tables
                                  Expanded(
                                    flex: 1,
                                    child: _buildTablesGrid(widget.tournamentId, tournament['createdBy']),
                                  ),
                                  
                                  // Right Panel: Chat
                                  Expanded(
                                    flex: 2,
                                    child: _buildChatArea(tournament['chatRoomId']),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Action Bar (Sticky)
                    _buildActionBar(isRegistered, canRegister, tournamentStatus, 
                        tournament['createdBy'] == currentUser?.uid, registeredPlayerIds.length, activeTableId),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTournamentHeader(Map<String, dynamic> tournament, bool isAdminMode) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD4AF37).withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          // Title Section
          Column(
            children: [
              if (isAdminMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB71C1C), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.admin_panel_settings, color: Color(0xFFB71C1C), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'GOD MODE ACTIVADO',
                        style: TextStyle(
                          color: Color(0xFFB71C1C),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                (tournament['name'] ?? 'Torneo').toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: Color(0x66D4AF37),
                      blurRadius: 20,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Stats Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModernStatCard(
                  'BUY-IN',
                  ImperialCurrency(
                    amount: tournament['buyIn'],
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 18, 
                      fontWeight: FontWeight.bold
                    ),
                    iconSize: 16,
                  ),
                  Icons.monetization_on_outlined,
                ),
                const SizedBox(width: 12),
                _buildModernStatCard(
                  'PREMIO',
                  ImperialCurrency(
                    amount: tournament['prizePool'] ?? 0,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    iconSize: 16,
                  ),
                  Icons.emoji_events_outlined,
                  isHighLight: true,
                ),
                const SizedBox(width: 12),
                _buildModernStatCard(
                  'JUGADORES',
                   Text(
                    '${(tournament['registeredPlayerIds'] as List).length}/${tournament['estimatedPlayers']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icons.people_outline,
                ),
                if (tournament['type'] != null) ...[
                  const SizedBox(width: 12),
                  _buildTypeTag(tournament['type']),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernStatCard(String label, Widget value, IconData icon, {bool isHighLight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isHighLight 
            ? const Color(0xFFD4AF37).withOpacity(0.1) 
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighLight 
              ? const Color(0xFFD4AF37).withOpacity(0.5) 
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon, 
                size: 14, 
                color: isHighLight ? const Color(0xFFD4AF37) : Colors.white54
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isHighLight ? const Color(0xFFD4AF37) : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
  }

  Widget _buildTypeTag(String type) {
    String label = type;
    IconData icon = Icons.label;
    
    switch (type) {
      case 'FREEZEOUT': label = 'Freezeout'; icon = Icons.ac_unit; break;
      case 'REBUY': label = 'Rebuy'; icon = Icons.refresh; break;
      case 'BOUNTY': label = 'Bounty'; icon = Icons.gps_fixed; break;
      case 'TURBO': label = 'Turbo'; icon = Icons.flash_on; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
               Icon(icon, size: 14, color: Colors.blue),
               const SizedBox(width: 6),
               const Text(
                'MODO',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTablesGrid(String tournamentId, String? creatorId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('poker_tables')
          .where('tournamentId', isEqualTo: tournamentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tables = snapshot.data!.docs;

        if (tables.isEmpty) {
          return const Center(
            child: Text(
              'No hay mesas disponibles',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index].data() as Map<String, dynamic>;
            final tableId = tables[index].id;
            final tableName = table['tableName'] ?? 'Mesa ${index + 1}';
            final players = (table['players'] as List?) ?? [];
            final status = table['status'] ?? 'pending';
            final isActive = status == 'active' || status == 'open_for_registration';

            return GestureDetector(
              onTap: isActive ? () => _joinTable(tableId) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF16213E) : Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? const Color(0xFFD4AF37) : Colors.white10,
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.table_restaurant,
                      color: isActive ? const Color(0xFFD4AF37) : Colors.white24,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tableName,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${players.length}/9',
                      style: TextStyle(
                        color: isActive ? Colors.white70 : Colors.white24,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _joinTable(String tableId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          roomId: tableId,
          isTournamentMode: true,
        ),
      ),
    );
  }

  Widget _buildChatArea(String? chatRoomId) {
    // Placeholder for chat area
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Center(
        child: Text(
          'Chat del Torneo',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildActionBar(bool isRegistered, bool canRegister, String tournamentStatus, bool isCreator, int playerCount, String? activeTableId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border.symmetric(horizontal: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (isCreator && tournamentStatus == 'REGISTERING')
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startTournament,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('COMENZAR TORNEO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else if (isRegistered)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUnregistering ? null : _unregisterFromTournament,
                  icon: _isUnregistering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.exit_to_app),
                  label: const Text('CANCELAR INSCRIPCIÓN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else if (canRegister)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isRegistering ? null : _registerForTournament,
                  icon: _isRegistering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.person_add),
                  label: const Text('UNIRSE AL TORNEO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                    shadowColor: const Color(0xFFD4AF37).withOpacity(0.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _startTournament() async {
    try {
      await Provider.of<TournamentProvider>(context, listen: false)
          .startTournament(widget.tournamentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Torneo iniciado!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStatusIndicator(String status) {
    String label = '';
    Color color = Colors.white;
    IconData icon = Icons.info;
    
    // Custom styles
    bool isPremium = true; 

    switch (status) {
      case 'REGISTERING':
        label = 'REGISTRO ABIERTO';
        color = const Color(0xFF00E676); // Premium Neon Green
        icon = Icons.how_to_reg;
        break;
      case 'LATE_REG':
        label = 'REGISTRO TARDÍO';
        color = const Color(0xFFFF9100);
        icon = Icons.access_time_filled;
        break;
      case 'RUNNING':
        label = 'EN CURSO';
        color = const Color(0xFFD4AF37); // Gold
        icon = Icons.play_circle_filled;
        break;
      case 'FINISHED':
        label = 'FINALIZADO';
        color = Colors.grey;
        icon = Icons.flag;
        isPremium = false;
        break;
    }

    if (isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.2),
              color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
           boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

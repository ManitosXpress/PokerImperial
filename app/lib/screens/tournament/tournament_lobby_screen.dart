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
                                  // Left Panel: Registered Players
                                  Expanded(
                                    flex: 1,
                                    child: _buildPlayersList(widget.tournamentId, tournament['createdBy']),
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

  Widget _buildPlayersList(String tournamentId, String? hostId) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.1))),
            ),
            child: const Text(
              'JUGADORES INSCRITOS',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(tournamentId)
                  .collection('participants')
                  .orderBy('joinedAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SizedBox();
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final participants = snapshot.data!.docs;

                if (participants.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 48, color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 8),
                        Text('Esperando jugadores...', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final p = participants[index].data() as Map<String, dynamic>;
                    final isHost = p['uid'] == hostId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                           Container(
                            width: 32, height: 32,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFFF7E68F)]),
                            ),
                            child: const Icon(Icons.person, size: 20, color: Colors.black),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p['displayName'] ?? 'Jugador',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isHost)
                            const Icon(Icons.star, color: Color(0xFFD4AF37), size: 16),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea(String? chatRoomId) {
    if (chatRoomId == null) {
      return const Center(child: Text('Chat no disponible', style: TextStyle(color: Colors.white54)));
    }

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 16, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
           Container(
            padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.1))),
            ),
            child: Row(
              children: const [
                Icon(Icons.chat_bubble_outline, color: Color(0xFFD4AF37), size: 18),
                SizedBox(width: 8),
                Text(
                  'CHAT DEL LOBBY',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(widget.tournamentId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SizedBox();
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Di hola a todos 👋',
                      style: TextStyle(color: Colors.white.withOpacity(0.3)),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderId'] == FirebaseAuth.instance.currentUser?.uid;
                    
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe 
                              ? const Color(0xFFD4AF37) 
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                msg['senderName'] ?? 'Anon',
                                style: const TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontSize: 10, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            Text(
                              msg['content'] ?? '',
                              style: TextStyle(
                                color: isMe ? Colors.black : Colors.white,
                                fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Escribe aquí...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(chatRoomId),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFFD4AF37),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black, size: 18),
                    onPressed: () => _sendMessage(chatRoomId),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String chatRoomId) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await Provider.of<TournamentProvider>(context, listen: false)
          .sendMessage(widget.tournamentId, text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar mensaje: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildActionBar(bool isRegistered, bool canRegister, String status, bool isHost, int playerCount, String? activeTableId) {
    // Check for spectator role
    final clubProvider = Provider.of<ClubProvider>(context);
    final userRole = clubProvider.currentUserRole;
    final isSpectator = userRole == 'admin' || userRole == 'club' || userRole == 'seller' || isHost;

    if (status == 'RUNNING' && activeTableId != null) {
       return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: _buildStatusIndicator(status)),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: isRegistered
                  ? ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GameScreen(
                              roomId: activeTableId,
                              isTournamentMode: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('VOLVER A LA MESA'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GameScreen(
                              roomId: activeTableId,
                              isTournamentMode: true,
                              isSpectatorMode: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.remove_red_eye),
                      label: const Text('ESPECTAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                        shadowColor: const Color(0xFFD4AF37).withOpacity(0.5),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Status Indicator
          Expanded(
            child: _buildStatusIndicator(status),
          ),
          const SizedBox(width: 16),
          
          // Host Start Button
          if (isHost && (status == 'REGISTERING' || status == 'LATE_REG')) ...[
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (playerCount < 2) { // Changed min players to 2 for testing, normally 4
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mínimo se necesitan 2 jugadores para iniciar'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  _startTournament();
                },
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text('INICIAR TORNEO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: playerCount >= 2 ? Colors.redAccent : Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else if (canRegister) ...[
             // Player Action Button
            Expanded(
              flex: 2,
              child: isRegistered
                  ? ElevatedButton.icon(
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
                    )
                  : ElevatedButton.icon(
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
        ],
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

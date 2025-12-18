import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/tournament_provider.dart';

class TournamentLobbyScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentLobbyScreen({super.key, required this.tournamentId});

  @override
  State<TournamentLobbyScreen> createState() => _TournamentLobbyScreenState();
}

class _TournamentLobbyScreenState extends State<TournamentLobbyScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isRegistering = false;
  bool _isUnregistering = false;

  @override
  void dispose() {
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
                    // Tournament Header
                    _buildTournamentHeader(tournament),
                    
                    // Main Content Area
                    Expanded(
                      child: Row(
                        children: [
                          // Left Panel: Registered Players
                          Expanded(
                            flex: 1,
                            child: _buildPlayersList(registeredPlayerIds),
                          ),
                          
                          // Right Panel: Chat
                          Expanded(
                            flex: 2,
                            child: _buildChatArea(tournament['chatRoomId']),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Action Bar
                    _buildActionBar(isRegistered, canRegister, tournamentStatus, 
                        tournament['createdBy'] == currentUser?.uid, registeredPlayerIds.length),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTournamentHeader(Map<String, dynamic> tournament) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD4AF37).withOpacity(0.2),
            const Color(0xFFFFD700).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD4AF37),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            tournament['name'] ?? 'Torneo',
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip(
                Icons.attach_money,
                'Buy-in',
                '\$${tournament['buyIn']}',
                Colors.green,
              ),
              _buildStatChip(
                Icons.emoji_events,
                'Prize Pool',
                '\$${tournament['prizePool']}',
                const Color(0xFFD4AF37),
              ),
              _buildStatChip(
                Icons.people,
                'Jugadores',
                '${(tournament['registeredPlayerIds'] as List).length}/${tournament['estimatedPlayers']}',
                Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTournamentTypeBadge(tournament['type'], tournament['settings']),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTournamentTypeBadge(String type, Map<String, dynamic>? settings) {
    String emoji = '';
    String label = '';
    Color color = Colors.white;

    switch (type) {
      case 'FREEZEOUT':
        emoji = '🧊';
        label = 'Freezeout';
        color = Colors.cyan;
        break;
      case 'REBUY':
        emoji = '🔄';
        label = 'Rebuy';
        color = Colors.blue;
        break;
      case 'BOUNTY':
        emoji = '🥊';
        label = 'Bounty';
        color = Colors.orange;
        break;
      case 'TURBO':
        emoji = '⚡';
        label = 'Turbo';
        color = Colors.yellow;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (settings != null) ...[
            const SizedBox(width: 8),
            Text(
              '• ${settings['blindSpeed']}',
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayersList(List<String> playerIds) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, color: Color(0xFFD4AF37)),
                const SizedBox(width: 8),
                Text(
                  'Jugadores Inscritos (${playerIds.length})',
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: playerIds.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_add,
                          size: 64,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Aún no hay jugadores',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '¡Sé el primero en unirte!',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: playerIds.length,
                    itemBuilder: (context, index) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(playerIds[index])
                            .get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) {
                            return const SizedBox.shrink();
                          }

                          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                          final displayName = userData?['displayName'] ?? 'Jugador ${index + 1}';
                          final photoURL = userData?['photoURL'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                                    ),
                                  ),
                                  child: photoURL != null
                                      ? ClipOval(
                                          child: Image.network(
                                            photoURL,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.person, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (index == 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4AF37),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'HOST',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.1),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              children: const [
                Icon(Icons.chat, color: Color(0xFF00D4FF)),
                SizedBox(width: 8),
                Text('Chat del Lobby', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          // Messages List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return Center(
                    child: Text('¡Sé el primero en escribir!', style: TextStyle(color: Colors.white.withOpacity(0.3))),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF00D4FF).withOpacity(0.2) : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isMe ? const Color(0xFF00D4FF).withOpacity(0.5) : Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                msg['senderName'] ?? 'Unknown',
                                style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            Text(
                              msg['content'] ?? '',
                              style: const TextStyle(color: Colors.white),
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

          // Input Area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendMessage(chatRoomId),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _sendMessage(chatRoomId),
                  icon: const Icon(Icons.send, color: Color(0xFF00D4FF)),
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

  Widget _buildActionBar(bool isRegistered, bool canRegister, String status, bool isHost, int playerCount) {
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
                  if (playerCount < 8) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mínimo se necesitan 8 jugadores para iniciar el torneo'),
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
                  backgroundColor: playerCount >= 8 ? Colors.redAccent : Colors.grey[800],
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
                      label: const Text('Cancelar Inscripción'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
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
                                color: Colors.white,
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

    switch (status) {
      case 'REGISTERING':
        label = 'ABIERTO';
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'LATE_REG':
        label = 'REGISTRO TARDÍO';
        color = Colors.orange;
        icon = Icons.access_time;
        break;
      case 'RUNNING':
        label = 'EN CURSO';
        color = Colors.blue;
        icon = Icons.play_circle;
        break;
      case 'FINISHED':
        label = 'FINALIZADO';
        color = Colors.grey;
        icon = Icons.flag;
        break;
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/socket_service.dart';

class WaitingRoomView extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic>? roomState;
  final VoidCallback onStartGame;
  final VoidCallback? onCloseRoom;
  final String? userRole;
  final bool isHost;
  final bool isPublic;
  final bool isClubLeader;
  final String? currentUserId;
  final bool isTournament; // New flag

  const WaitingRoomView({
    super.key,
    required this.roomId,
    required this.roomState,
    required this.onStartGame,
    this.onCloseRoom,
    this.userRole,
    this.isHost = false,
    this.isPublic = true,
    this.isClubLeader = false,
    this.currentUserId,
    this.isTournament = false,
  });

  @override
  State<WaitingRoomView> createState() => _WaitingRoomViewState();
}

class _WaitingRoomViewState extends State<WaitingRoomView> {
  int? _autoStartSeconds;
  Timer? _localTimer;

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    super.dispose();
  }

  void _setupSocketListeners() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    socketService.socket.on('tournament_countdown', (data) {
      if (mounted) {
        setState(() {
          _autoStartSeconds = data['seconds'];
        });
        _startLocalCountdown();
      }
    });

    socketService.socket.on('countdown_cancelled', (_) {
      if (mounted) {
        setState(() {
          _autoStartSeconds = null;
        });
        _localTimer?.cancel();
      }
    });
  }

  void _startLocalCountdown() {
    _localTimer?.cancel();
    _localTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_autoStartSeconds != null && _autoStartSeconds! > 0) {
            _autoStartSeconds = _autoStartSeconds! - 1;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final players = (widget.roomState?['players'] as List?) ?? [];
    final playerCount = players.length;
    final maxPlayers = widget.roomState?['maxPlayers'] ?? 8;
    
    final showStartButton = widget.isHost && !widget.isTournament; // Hide start button for tournaments
    final canStartAction = playerCount >= 2;

    return SingleChildScrollView(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Room Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE94560), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.table_restaurant, color: Color(0xFFE94560), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Sala: ${widget.roomId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$playerCount / $maxPlayers Jugadores',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Players Grid
              Container(
                constraints: const BoxConstraints(
                  maxHeight: 400, 
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: players.isEmpty 
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: Text('Esperando jugadores...', style: TextStyle(color: Colors.white54))),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final name = player['name'] ?? 'Player';
                        final photoUrl = player['photoUrl'];
                        final playerId = player['id'];
                        
                        // Check if this player is the club leader
                        final isThisPlayerClubLeader = widget.isClubLeader && playerId == widget.currentUserId;
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isThisPlayerClubLeader 
                                  ? const Color(0xFFFFD700) 
                                  : const Color(0xFF30475E),
                              width: isThisPlayerClubLeader ? 3 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isThisPlayerClubLeader
                                    ? const Color(0xFFFFD700).withOpacity(0.5)
                                    : Colors.black.withOpacity(0.3),
                                blurRadius: isThisPlayerClubLeader ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: const Color(0xFF0F3460),
                                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                    child: photoUrl == null
                                        ? Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                                            style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF16213E), width: 2),
                                      ),
                                    ),
                                  ),
                                  // Crown badge for club leader
                                  if (isThisPlayerClubLeader)
                                    Positioned(
                                      top: -8,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFFFD700).withOpacity(0.6),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '👑',
                                                style: TextStyle(fontSize: 10),
                                              ),
                                              SizedBox(width: 2),
                                              Text(
                                                'OWNER',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              ),
              
              const SizedBox(height: 32),

            // Action Area
            if (showStartButton)
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        if (canStartAction)
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                      ],
                      gradient: canStartAction 
                          ? const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFE94560)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : null,
                    ),
                    child: ElevatedButton(
                      onPressed: canStartAction ? widget.onStartGame : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        disabledBackgroundColor: Colors.grey.shade800,
                      ),
                      child: Text(
                        canStartAction ? 'REPARTIR CARTAS' : 'ESPERANDO JUGADORES (${players.length}/2)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: canStartAction ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Close Room Button
                  TextButton.icon(
                    onPressed: () {
                      // Confirm Dialog
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Cerrar Sala'),
                          content: const Text('¿Estás seguro de que quieres cerrar la sala? Todos los jugadores serán desconectados y se devolverá el dinero.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                if (widget.onCloseRoom != null) widget.onCloseRoom!();
                              },
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Cerrar Sala'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    label: const Text(
                      'Cerrar Sala',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _autoStartSeconds != null ? Icons.timer : (widget.isClubLeader ? Icons.visibility : Icons.hourglass_empty), 
                      color: _autoStartSeconds != null ? const Color(0xFFFFD700) : (widget.isClubLeader ? const Color(0xFFFFD700) : Colors.white70),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _autoStartSeconds != null
                          ? 'EL TORNEO COMIENZA EN ${_autoStartSeconds}s'
                          : (widget.isClubLeader 
                              ? '👀 OBSERVANDO MESA' 
                              : (widget.isTournament 
                                  ? 'Esperando jugadores para iniciar (${players.length}/2)...' 
                                  : 'Esperando confirmación para iniciar...')),
                      style: TextStyle(
                        color: _autoStartSeconds != null ? const Color(0xFFFFD700) : (widget.isClubLeader ? const Color(0xFFFFD700) : Colors.white70),
                        fontSize: _autoStartSeconds != null ? 20 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

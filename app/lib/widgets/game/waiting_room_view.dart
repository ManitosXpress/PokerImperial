import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';

class WaitingRoomView extends StatelessWidget {
  final String roomId;
  final Map<String, dynamic>? roomState;
  final VoidCallback onStartGame;
  final String? userRole;
  final bool isHost;
  final bool isPublic;

  const WaitingRoomView({
    super.key,
    required this.roomId,
    required this.roomState,
    required this.onStartGame,
    this.userRole,
    this.isHost = false,
    this.isPublic = true,
  });

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final players = (roomState?['players'] as List?) ?? [];
    final playerCount = players.length;
    final maxPlayers = roomState?['maxPlayers'] ?? 8;
    
    // Debug logs
    print('🎮 WaitingRoomView - isHost: $isHost, playerCount: $playerCount, roomId: $roomId');
    print('🎮 WaitingRoomView - roomState keys: ${roomState?.keys.toList()}');
    print('🎮 WaitingRoomView - players: $players');
    
    // Logic: Host can always SEE the button, but it's disabled if < 2 players.
    // We remove the !isObserver check because the host might be an observer (Club Owner) 
    // but still needs to start the game.
    final showStartButton = isHost; 
    final canStartAction = playerCount >= 2;
    
    // Additional debug
    print('🎮 WaitingRoomView - showStartButton: $showStartButton, canStartAction: $canStartAction');

    return SingleChildScrollView(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 800), // Increased width for Grid
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
                      'Sala: $roomId',
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
                  maxHeight: 400, // Limit height to prevent overflow
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
                        crossAxisCount: 3, // 3 columns
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final name = player['name'] ?? 'Player';
                        final photoUrl = player['photoUrl']; // Assuming this field exists or is null
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF30475E)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Avatar
                              Stack(
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
                                  // Status Dot
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
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Name
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
                      : null, // No gradient if disabled
                ),
                child: ElevatedButton(
                  onPressed: canStartAction ? onStartGame : null,
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
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_empty, color: Colors.white70),
                    SizedBox(width: 12),
                    Text(
                      'Esperando confirmación para iniciar...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
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

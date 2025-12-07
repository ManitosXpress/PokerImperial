import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';

class WaitingRoomView extends StatelessWidget {
  final String roomId;
  final Map<String, dynamic>? roomState;
  final VoidCallback onStartGame;
  final String? userRole;
  final bool isHost;

  const WaitingRoomView({
    super.key,
    required this.roomId,
    required this.roomState,
    required this.onStartGame,
    this.userRole,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final playerCount = (roomState?['players'] as List?)?.length ?? 0;
    final maxPlayers = roomState?['maxPlayers'] ?? 8;
    // Determine if we should show the start mechanism
    // Only players can see start related UI (even if it's just status)
    // Club/Admin see Observer status
    final isObserver = userRole == 'club' || userRole == 'admin';
    final canStart = !isObserver && isHost && playerCount >= 4;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Room title
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE94560), width: 2),
              ),
              child: Column(
                children: [
                  const Icon(Icons.people, color: Color(0xFFE94560), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Sala: $roomId',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isObserver ? 'MODO OBSERVADOR' : '$playerCount / $maxPlayers Jugadores',
                    style: TextStyle(
                      color: isObserver ? Colors.amber : const Color(0xFFE94560),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Players list
            if (roomState != null && roomState!['players'] != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      languageProvider.getText('players_connected'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...(roomState!['players'] as List).map((player) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.person, color: Colors.white70),
                            const SizedBox(width: 12),
                            Text(
                              player['name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            
            const SizedBox(height: 32),

            // Status / Action Area
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: canStart ? Colors.green : Colors.white24, 
                  width: 2
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    canStart ? Icons.check_circle : Icons.info_outline, 
                    color: canStart ? Colors.green : Colors.white70
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      isObserver 
                          ? 'Esperando a que inicie la partida...'
                          : playerCount < 4 
                              ? 'Esperando jugadores (min 4)...'
                              : 'Esperando confirmación para iniciar...',
                      style: TextStyle(
                        color: canStart ? Colors.green : Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

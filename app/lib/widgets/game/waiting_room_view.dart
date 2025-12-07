import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';

class WaitingRoomView extends StatelessWidget {
  final String roomId;
  final Map<String, dynamic>? roomState;
  final VoidCallback onStartGame;

  const WaitingRoomView({
    super.key,
    required this.roomId,
    required this.roomState,
    required this.onStartGame,
  });

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

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
                  if (roomState != null && roomState!['players'] != null)
                    Text(
                      '${(roomState!['players'] as List).length} / ${roomState!['maxPlayers'] ?? 8} Jugadores',
                      style: const TextStyle(
                        color: Color(0xFFE94560),
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

            // Start button
            if (roomState == null || (roomState!['players'] != null && (roomState!['players'] as List).length >= 2))
              ElevatedButton.icon(
                onPressed: onStartGame,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: Text(languageProvider.getText('start_game')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Text(
                      languageProvider.getText('waiting_for_players'),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 16,
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

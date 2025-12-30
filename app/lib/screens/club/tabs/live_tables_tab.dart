import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../providers/club_provider.dart';
import '../../game_screen.dart';

import '../../../widgets/poker_loading_indicator.dart';

class LiveTablesTab extends StatelessWidget {
  final String clubId;

  const LiveTablesTab({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('poker_tables')
          .where('clubId', isEqualTo: clubId)
          .where('status', whereIn: ['waiting', 'active'])
          .where('isPrivate', isEqualTo: false)
          // Removed orderBy to avoid composite index requirement
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: PokerLoadingIndicator(
              statusText: 'Loading Tables...',
              color: Color(0xFFFFD700),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_restaurant, color: Colors.white.withOpacity(0.3), size: 64),
                const SizedBox(height: 16),
                const Text(
                  'No active tables',
                  style: TextStyle(color: Colors.white54, fontSize: 18),
                ),
              ],
            ),
          );
        }

        final tables = snapshot.data!.docs;
        final clubProvider = Provider.of<ClubProvider>(context, listen: false);
        final userRole = clubProvider.currentUserRole; // 'player', 'club', 'admin', 'seller'
        final canPlay = userRole == 'player' || userRole == null; // Default to player if null?

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index].data() as Map<String, dynamic>;
            final tableId = tables[index].id;
            final players = table['players'] as List? ?? [];
            final maxPlayers = table['maxPlayers'] ?? 9;
            final isWaiting = table['status'] == 'waiting';
            
            // Logic for button
            // If player: Join Lobby if waiting, Spectate if active (or maybe just spectate logic is handled by GameScreen)
            // If Club/Seller: Always Spectate
            
            final bool showJoinLobby = canPlay && isWaiting;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isWaiting ? const Color(0xFFFFD700).withOpacity(0.5) : Colors.white10,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isWaiting ? Colors.amber.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isWaiting ? Colors.amber : Colors.greenAccent,
                    ),
                  ),
                  child: Icon(
                    isWaiting ? Icons.hourglass_empty : Icons.casino,
                    color: isWaiting ? Colors.amber : Colors.greenAccent,
                  ),
                ),
                title: Text(
                  table['name'] ?? 'Unnamed Table',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Blinds: ${table['smallBlind']}/${table['bigBlind']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Text(
                          'Players: ${players.length}/$maxPlayers',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        if (isWaiting)
                          const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: Text(
                              '• WAITING',
                              style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    if (showJoinLobby) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameScreen(
                            roomId: tableId,
                            isSpectatorMode: false,
                          ),
                        ),
                      );
                    } else {
                      // Spectate mode
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameScreen(
                            roomId: tableId,
                            isSpectatorMode: true,
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: showJoinLobby ? const Color(0xFFFFD700) : Colors.blueGrey,
                    foregroundColor: showJoinLobby ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(showJoinLobby ? 'JOIN LOBBY' : 'SPECTATE'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

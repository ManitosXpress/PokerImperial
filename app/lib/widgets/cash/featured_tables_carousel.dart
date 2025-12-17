import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/table_lobby_screen.dart';

class FeaturedTablesCarousel extends StatelessWidget {
  const FeaturedTablesCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('poker_tables')
          .where('isPublic', isEqualTo: true)
          .where('status', whereIn: ['waiting', 'lobby', 'active'])
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final tables = snapshot.data!.docs;
        
        // Sort by "hotness" - prioritize tables with more players and activity
        final sortedTables = tables.toList()..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          
          final aPlayers = (aData['players'] as List?)?.length ?? 0;
          final bPlayers = (bData['players'] as List?)?.length ?? 0;
          
          // Prioritize by player count
          return bPlayers.compareTo(aPlayers);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Color(0xFFFF6B35), size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'MESAS DESTACADAS',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.85),
                itemCount: sortedTables.length > 3 ? 3 : sortedTables.length,
                itemBuilder: (context, index) {
                  final table = sortedTables[index].data() as Map<String, dynamic>;
                  final tableId = sortedTables[index].id;
                  final playerCount = (table['players'] as List?)?.length ?? 0;
                  final isHot = playerCount >= 4;

                  return _FeaturedTableCard(
                    tableId: tableId,
                    tableName: table['name'] ?? 'Mesa ${index + 1}',
                    smallBlind: table['smallBlind'] ?? 10,
                    bigBlind: table['bigBlind'] ?? 20,
                    playerCount: playerCount,
                    maxPlayers: table['maxPlayers'] ?? 8,
                    isHot: isHot,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeaturedTableCard extends StatelessWidget {
  final String tableId;
  final String tableName;
  final int smallBlind;
  final int bigBlind;
  final int playerCount;
  final int maxPlayers;
  final bool isHot;

  const _FeaturedTableCard({
    required this.tableId,
    required this.tableName,
    required this.smallBlind,
    required this.bigBlind,
    required this.playerCount,
    required this.maxPlayers,
    required this.isHot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isHot
              ? [
                  const Color(0xFFFF6B35).withOpacity(0.3),
                  const Color(0xFFE94560).withOpacity(0.2),
                ]
              : [
                  const Color(0xFF2A2A40),
                  const Color(0xFF1A1A2E),
                ],
        ),
        border: Border.all(
          color: isHot
              ? const Color(0xFFFF6B35).withOpacity(0.5)
              : const Color(0xFFFFD700).withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isHot
                ? const Color(0xFFFF6B35).withOpacity(0.3)
                : Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _joinTable(context),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Header with badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tableName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Color(0xFFFFD700),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isHot)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFE94560)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B35).withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.local_fire_department, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'HOT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                
                const Spacer(),
                
                // Info row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ciegas',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '\$$smallBlind/\$$bigBlind',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.people, color: Colors.white, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            '$playerCount/$maxPlayers',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Join button
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _joinTable(context),
                      borderRadius: BorderRadius.circular(16),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow, color: Colors.black, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'JUGAR YA',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _joinTable(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TableLobbyScreen(
          tableId: tableId,
          tableName: tableName,
        ),
      ),
    );
  }
}

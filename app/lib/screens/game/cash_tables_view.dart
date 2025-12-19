import 'package:flutter/material.dart';
import '../../widgets/imperial_currency.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../game_screen.dart';
import '../table_lobby_screen.dart';
import '../../services/socket_service.dart';
import 'package:provider/provider.dart';
import '../../widgets/cash/featured_tables_carousel.dart';
import '../../widgets/cash/blind_filters_chips.dart';

class CashTablesView extends StatefulWidget {
  final String? userRole;

  const CashTablesView({super.key, this.userRole});

  @override
  State<CashTablesView> createState() => _CashTablesViewState();
}

class _CashTablesViewState extends State<CashTablesView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _roomIdController = TextEditingController();
  BlindTier? _selectedTier;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _roomIdController.dispose();
    super.dispose();
  }

  void _joinByInput(BuildContext context) {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) return;
    
    // Navigate to Lobby
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TableLobbyScreen(
          tableId: roomId,
          tableName: 'Sala $roomId', // We don't have the name yet, but Lobby will fetch it
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0a0e27),
            Colors.black,
          ],
        ),
      ),
      child: Column(
        children: [
          // Featured Tables Carousel
          const FeaturedTablesCarousel(),
          
          // Blind Filters
          BlindFiltersChips(
            selectedTier: _selectedTier,
            onTierSelected: (tier) {
              setState(() {
                _selectedTier = tier;
              });
            },
          ),
          
          // Join by ID Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomIdController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ingresar ID de Sala...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _joinByInput(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('ENTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          // List of Tables
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('poker_tables')
                  .where('status', isEqualTo: 'active') // Should we include 'waiting'/'lobby'? User said "waiting" or "lobby".
                  // But the code previously used 'active'. 
                  // Let's check TableLobbyScreen logic. It checks for 'active' to go to game.
                  // If status is 'waiting', it stays in lobby.
                  // So we should probably fetch 'waiting' AND 'active' (if late join allowed) or just 'waiting'?
                  // User said: "status == 'waiting' o status == 'lobby'"
                  // Let's update the query. Firestore doesn't support OR in where clauses easily without 'in'.
                  .where('status', whereIn: ['waiting', 'lobby', 'active']) 
                  .where('isPublic', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.table_chart_outlined,
                          size: 80,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay mesas públicas activas',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final tables = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index].data() as Map<String, dynamic>;
                    final tableId = tables[index].id;

                    return _TableCard(
                      tableId: tableId,
                      tableName: table['name'] ?? 'Mesa $index',
                      smallBlind: table['smallBlind'] ?? 10,
                      bigBlind: table['bigBlind'] ?? 20,
                      minBuyIn: table['minBuyIn'] ?? 100,
                      maxBuyIn: table['maxBuyIn'] ?? 1000,
                      playerCount: (table['players'] as List?)?.length ?? 0,
                      maxPlayers: 8,
                      createdByName: table['createdByName'] ?? 'Club',
                      userRole: widget.userRole,
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
}

class _TableCard extends StatelessWidget {
  final String tableId;
  final String tableName;
  final int smallBlind;
  final int bigBlind;
  final int minBuyIn;
  final int maxBuyIn;
  final int playerCount;
  final int maxPlayers;
  final String createdByName;
  final String? userRole;

  const _TableCard({
    required this.tableId,
    required this.tableName,
    required this.smallBlind,
    required this.bigBlind,
    required this.minBuyIn,
    required this.maxBuyIn,
    required this.playerCount,
    required this.maxPlayers,
    required this.createdByName,
    required this.userRole,
  });

  bool get isHot => playerCount >= (maxPlayers * 0.5);
  bool get isVip => minBuyIn >= 1000;
  bool get isFull => playerCount >= maxPlayers;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1a1f3a),
            const Color(0xFF0f1425),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHot 
              ? const Color(0xFFFF6B35).withOpacity(0.5)
              : const Color(0xFFFFD700).withOpacity(0.3),
          width: isHot ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isHot
                ? const Color(0xFFFF6B35).withOpacity(0.2)
                : Colors.black.withOpacity(0.5),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isFull ? null : () => _joinTable(context),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tableName,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (isHot)
                          _Badge(
                            label: 'HOT',
                            icon: Icons.local_fire_department,
                            color: const Color(0xFFFF6B35),
                          ),
                        if (isVip)
                          _Badge(
                            label: 'VIP',
                            icon: Icons.star,
                            color: const Color(0xFFFFD700),
                          ),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Progress bar with count
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '$playerCount/$maxPlayers jugadores',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${((playerCount / maxPlayers) * 100).toInt()}%',
                          style: TextStyle(
                            color: isFull ? Colors.red : const Color(0xFFFFD700),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: playerCount / maxPlayers,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isFull 
                              ? Colors.red
                              : isHot 
                                  ? const Color(0xFFFF6B35)
                                  : const Color(0xFF00FF88),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 14),
                
                // Player avatars section
                if (playerCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlayerAvatarsRow(playerCount: playerCount),
                  ),
                
                // Info chips
                Row(
                  children: [
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.remove_red_eye,
                        label: 'Ciegas',
                        valueWidget: Row(
                          children: [
                            ImperialCurrency(amount: smallBlind, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), iconSize: 14,),
                            const Text('/', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            ImperialCurrency(amount: bigBlind, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), iconSize: 14,),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.attach_money,
                        label: 'Buy-In',
                        valueWidget: Row(
                          children: [
                            ImperialCurrency(amount: minBuyIn, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), iconSize: 14,),
                            const Text('-', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            ImperialCurrency(amount: maxBuyIn, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), iconSize: 14,),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Join button
                Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isFull
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                          ),
                    color: isFull ? Colors.grey.withOpacity(0.3) : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isFull
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.4),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isFull ? null : () => _joinTable(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isFull ? Icons.block : Icons.play_arrow,
                              color: isFull ? Colors.white38 : Colors.black,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isFull ? 'MESA LLENA' : 'JUGAR YA',
                              style: TextStyle(
                                color: isFull ? Colors.white38 : Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
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
    final isSpectator = userRole == 'club';

    if (isSpectator) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Entrando como Espectador...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎮 Uniéndose a la mesa...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      if (context.mounted) {
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
    });
  }
}

// Badge widget
class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.6), color.withOpacity(0.3)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Player avatars row
class _PlayerAvatarsRow extends StatelessWidget {
  final int playerCount;

  const _PlayerAvatarsRow({required this.playerCount});

  @override
  Widget build(BuildContext context) {
    final displayCount = playerCount > 5 ? 5 : playerCount;
    
    return Row(
      children: [
        for (int i = 0; i < displayCount; i++)
          Align(
            widthFactor: 0.6,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1a1f3a + i * 0x111111),
                    Color(0xFF0f1425 + i * 0x0a0a0a),
                  ],
                ),
                border: Border.all(color: const Color(0xFFFFD700), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.person,
                  color: Color(0xFFFFD700),
                  size: 16,
                ),
              ),
            ),
          ),
        if (playerCount > 5)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '+${playerCount - 5}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}


class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget valueWidget;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: Colors.white60),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            valueWidget,
          ],
        ),
      ),
    );
  }
}

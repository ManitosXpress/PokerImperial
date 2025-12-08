import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../game_screen.dart';
import '../table_lobby_screen.dart';
import '../../services/socket_service.dart';
import 'package:provider/provider.dart';

class CashTablesView extends StatefulWidget {
  final String? userRole;

  const CashTablesView({super.key, this.userRole});

  @override
  State<CashTablesView> createState() => _CashTablesViewState();
}

class _CashTablesViewState extends State<CashTablesView> {
  final TextEditingController _roomIdController = TextEditingController();

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
          // Join by ID Input
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _joinByInput(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _joinTable(context),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tableName,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: playerCount < maxPlayers
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: playerCount < maxPlayers
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people,
                            size: 16,
                            color: playerCount < maxPlayers
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$playerCount/$maxPlayers',
                            style: TextStyle(
                              color: playerCount < maxPlayers
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Blinds & Buy-In Info
                Row(
                  children: [
                    _InfoChip(
                      icon: Icons.remove_red_eye,
                      label: 'Ciegas',
                      value: '\$$smallBlind/\$$bigBlind',
                    ),
                    const SizedBox(width: 12),
                    _InfoChip(
                      icon: Icons.attach_money,
                      label: 'Buy-In',
                      value: '\$$minBuyIn-\$$maxBuyIn',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Creator Info
                Row(
                  children: [
                    const Icon(
                      Icons.verified,
                      size: 16,
                      color: Color(0xFFFFD700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Creada por $createdByName',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
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
      // Club owners spectate
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Entrando como Espectador...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      // Players join to play
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎮 Uniéndose a la mesa...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TableLobbyScreen(
            tableId: tableId,
            tableName: tableName,
          ),
        ),
      );
    });
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
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
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

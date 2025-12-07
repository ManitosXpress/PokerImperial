import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../widgets/poker_loading_indicator.dart';
import 'game_screen.dart';

class TableLobbyScreen extends StatefulWidget {
  final String tableId;
  final String tableName;

  const TableLobbyScreen({
    super.key,
    required this.tableId,
    required this.tableName,
  });

  @override
  State<TableLobbyScreen> createState() => _TableLobbyScreenState();
}

class _TableLobbyScreenState extends State<TableLobbyScreen> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.tableName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker3_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.black.withOpacity(0.8),
              ],
            ),
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('poker_tables')
                .doc(widget.tableId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: PokerLoadingIndicator(
                    statusText: 'Connecting to Lobby...',
                    color: Color(0xFFFFD700),
                  ),
                );
              }

              final tableData = snapshot.data!.data() as Map<String, dynamic>?;

              if (tableData == null) {
                return const Center(child: Text('Table not found', style: TextStyle(color: Colors.white)));
              }

              // Check status - if active, navigate to game
              if (tableData['status'] == 'active') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GameScreen(roomId: widget.tableId),
                    ),
                  );
                });
              }

              final players = List<Map<String, dynamic>>.from(tableData['players'] ?? []);
              final hostId = tableData['hostId'];
              final isHost = currentUser?.uid == hostId;

              return Column(
                children: [
                  const SizedBox(height: 100), // AppBar spacer
                  
                  // Status Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hourglass_empty, color: Color(0xFFFFD700), size: 20),
                        const SizedBox(width: 12),
                        Text(
                          isHost ? 'Esperando jugadores para iniciar...' : 'Esperando al anfitrión...',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Players Grid
                  Expanded(
                    child: players.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_outline, size: 64, color: Colors.white.withOpacity(0.1)),
                                const SizedBox(height: 16),
                                const Text(
                                  'La sala está vacía',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: players.length,
                            itemBuilder: (context, index) {
                              final player = players[index];
                              return Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: player['id'] == hostId ? Colors.amber : Colors.blueAccent,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (player['id'] == hostId ? Colors.amber : Colors.blueAccent).withOpacity(0.3),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 30,
                                      backgroundColor: Colors.black26,
                                      backgroundImage: player['photoUrl'] != null 
                                          ? NetworkImage(player['photoUrl']) 
                                          : null,
                                      child: player['photoUrl'] == null
                                          ? const Icon(Icons.person, color: Colors.white70)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    player['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (player['id'] == hostId)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'HOST',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                  ),

                  // Action Button (Host Only)
                  if (isHost)
                    Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isStarting ? null : () => _startGame(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: const Color(0xFFFFD700).withOpacity(0.5),
                          ),
                          child: _isStarting
                              ? const CircularProgressIndicator(color: Colors.black)
                              : const Text(
                                  'EMPEZAR JUEGO',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _startGame(BuildContext context) async {
    setState(() => _isStarting = true);
    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('startGameFunction').call({
        'tableId': widget.tableId,
      });
      // Navigation will be handled by the stream listener
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting game: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isStarting = false);
      }
    }
  }
}

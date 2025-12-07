import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../widgets/poker_loading_indicator.dart';
import '../providers/wallet_provider.dart';
import '../providers/club_provider.dart'; // Import ClubProvider
import '../services/credits_service.dart'; // Import CreditsService
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
  bool _isTogglingReady = false;
  bool _autoStartFailed = false; // Flag to prevent infinite retry loops (updated)
  Timer? _countdownTimer;
  int _countdownSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _joinTable();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdownSeconds = 5);
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          timer.cancel();
          _countdownTimer = null;
          // Auto-start game
          _startGame(context);
        }
      });
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) {
      setState(() => _countdownSeconds = 0);
    }
  }

  Future<void> _joinTable() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // 1. Check User Role (Prevent Club Owner/Seller from joining as player)
      String? role;
      try {
        final clubProvider = Provider.of<ClubProvider>(context, listen: false);
        role = clubProvider.currentUserRole;
        
        // If role is missing, fetch it quickly
        if (role == null) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
          if (userDoc.exists) {
            role = userDoc.data()?['role'];
          }
        }
      } catch (e) {
        print('Error fetching user role: $e');
        // Continue anyway, assume player role
      }

      // If user is club/seller/admin, they should NOT join as player
      if (role == 'club' || role == 'seller' || role == 'admin') {
        print('User is $role, joining as spectator only. Skipping player join.');
        return; // Do NOT add to players list, they are spectators
      }

      // 2. Verify table exists first (before transaction)
      final tableRef = FirebaseFirestore.instance.collection('poker_tables').doc(widget.tableId);
      final tableDoc = await tableRef.get();
      
      if (!tableDoc.exists) {
        throw Exception('La mesa no existe');
      }

      final tableData = tableDoc.data();
      if (tableData == null) {
        throw Exception('Datos de la mesa no disponibles');
      }

      // 3. Check Min Buy In BEFORE transaction (to avoid unnecessary transaction)
      final minBuyIn = ((tableData['minBuyIn'] ?? 0) as num).toDouble();
      if (minBuyIn > 0) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
          if (!userDoc.exists) {
            throw Exception('Usuario no encontrado en la base de datos');
          }
          
          final userBalance = ((userDoc.data()?['credit'] ?? 0) as num).toDouble();
          
          if (userBalance < minBuyIn) {
            throw Exception('Crédito insuficiente. Tienes: ${userBalance.toInt()}, Mínimo requerido: ${minBuyIn.toInt()}');
          }
        } catch (e) {
          // Re-throw credit errors
          rethrow;
        }
      }

      // 4. Now do the transaction to add player
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(tableRef);
        if (!snapshot.exists) {
          throw Exception('La mesa ya no existe');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final players = List<Map<String, dynamic>>.from(data['players'] ?? []);

        // Calculate buyInAmount again inside to be safe
        final buyInAmount = minBuyIn > 0 ? minBuyIn : 1000.0;

        // Check if already joined
        final existingPlayerIndex = players.indexWhere((p) => p['id'] == currentUser.uid);
        if (existingPlayerIndex != -1) {
          // If already joined but with 0 chips (bug fix), update chips
          final currentChips = (players[existingPlayerIndex]['chips'] ?? 0) as num;
          if (currentChips <= 0) {
             print('Fixing player with 0 chips: ${currentUser.uid}');
             players[existingPlayerIndex]['chips'] = buyInAmount.toInt();
             transaction.update(tableRef, {'players': players});
             return;
          }
          return; // Already joined correctly
        }

        // Check if full
        final maxPlayers = (data['maxPlayers'] ?? 9) as int;
        if (players.length >= maxPlayers) {
          throw Exception('Mesa llena');
        }

        // Add player with minBuyIn as initial chips
        print('Adding player ${currentUser.displayName} with $buyInAmount chips');
        
        players.add({
          'id': currentUser.uid,
          'name': currentUser.displayName ?? 'Jugador',
          'photoUrl': currentUser.photoURL,
          'chips': buyInAmount.toInt(),
          'joinedAt': DateTime.now().toIso8601String(),
        });

        transaction.update(tableRef, {'players': players});
      });
    } catch (e) {
      print('Error joining table: $e');
      if (mounted) {
        // Extract error message properly
        String errorMessage = 'Error al unirse';
        if (e is Exception) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        } else if (e.toString().isNotEmpty) {
          errorMessage = e.toString();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

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
                Colors.black.withOpacity(0.6),
                Colors.black.withOpacity(0.9),
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
                return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red)));
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: PokerLoadingIndicator(
                    statusText: 'Conectando al Lobby...',
                    color: Color(0xFFFFD700),
                  ),
                );
              }

              final tableData = snapshot.data!.data() as Map<String, dynamic>?;

              if (tableData == null) {
                return const Center(
                    child: Text('Mesa no encontrada',
                        style: TextStyle(color: Colors.white)));
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

              final players =
                  List<Map<String, dynamic>>.from(tableData['players'] ?? []);
              final readyPlayers =
                  List<String>.from(tableData['readyPlayers'] ?? []);
              final hostId = tableData['hostId'];
              final maxPlayers = tableData['maxPlayers'] ?? 9;
              final smallBlind = tableData['smallBlind'] ?? 0;
              final bigBlind = tableData['bigBlind'] ?? 0;
              
              final isHost = currentUser?.uid == hostId;
              final currentUserId = currentUser?.uid;
              final isMeReady = currentUserId != null && readyPlayers.contains(currentUserId);
              
              final canStartLogic = players.length >= 4;
              final allReady = canStartLogic && players.every((p) => readyPlayers.contains(p['id']));

              // Auto-start countdown when all 4 players are ready
              if (allReady && !_isStarting && _countdownSeconds == 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _startCountdown();
                });
              } else if (!allReady && _countdownSeconds > 0) {
                // Cancel countdown if someone unreadies
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _cancelCountdown();
                });
              }

              // Determine if current user is a Spectator/Host (not in player list)
              final bool isSpectator = !players.any((p) => p['id'] == currentUserId);

              return Column(
                children: [
                  const SizedBox(height: 100), // AppBar spacer

                  // Header: Blinds & Stats
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        if (isSpectator && isHost)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('MODO ANFITRIÓN (NO JUGADOR)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildInfoBadge(Icons.monetization_on, 'Blinds: $smallBlind/$bigBlind'),
                            const SizedBox(width: 16),
                            _buildInfoBadge(Icons.people, 'Jugadores: ${players.length}/$maxPlayers'),
                          ],
                        ),
                        const SizedBox(height: 12),
                         if (!canStartLogic)
                          const Text(
                            'Esperando mínimo 4 jugadores...',
                            style: TextStyle(color: Colors.amber, fontStyle: FontStyle.italic),
                          ),
                         if (allReady && _countdownSeconds > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer, color: Colors.green, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  'Iniciando en $_countdownSeconds segundos...',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(color: Colors.white24),

                  // Players Grid
                  Expanded(
                    child: players.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: players.length,
                            itemBuilder: (context, index) {
                              final player = players[index];
                              final isReady = readyPlayers.contains(player['id']);
                              
                              return _buildPlayerCard(player, isReady, hostId);
                            },
                          ),
                  ),

                  // Footer Action Area
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      border: Border(top: BorderSide(color: Colors.white12)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canStartLogic) ...[
                            if (isSpectator) ...[
                                // Host Controls when Spectating
                                if (isHost) ...[
                                   if (allReady)
                                     Column(
                                      children: [
                                        if (_autoStartFailed)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: ElevatedButton.icon(
                                              onPressed: _isStarting ? null : () => _startGame(context),
                                              icon: const Icon(Icons.refresh, color: Colors.white),
                                              label: const Text('REINTENTAR INICIO'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red, 
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                              ),
                                            ),
                                          )
                                        else if (_countdownSeconds > 0)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.green),
                                            ),
                                            child: Column(
                                              children: [
                                                const Icon(Icons.timer, color: Colors.green, size: 32),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Iniciando en $_countdownSeconds...',
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: _isStarting ? null : () => _startGame(context),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green, 
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                              ),
                                              child: _isStarting 
                                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                                  : const Text('INICIAR PARTIDA (TODOS LISTOS)'),
                                            ),
                                          ),
                                      ],
                                    )
                                   else
                                     Text(
                                      'Esperando que todos los jugadores den "Listo"... (${readyPlayers.length}/${players.length})',
                                      style: const TextStyle(color: Colors.amber),
                                      textAlign: TextAlign.center,
                                     )
                                ] else
                                  const Text(
                                    'Esperando inicio de partida...',
                                    style: TextStyle(color: Colors.white54),
                                  )
                            ] else ...[
                                // Player Controls
                                if (!isMeReady)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton.icon(
                                      onPressed: _isTogglingReady ? null : () => _toggleReady(context, widget.tableId, true),
                                      icon: const Icon(Icons.check_circle_outline, size: 28),
                                      label: const Text('ESTOY LISTO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFFD700),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.green, size: 32),
                                        const SizedBox(height: 8),
                                        if (_countdownSeconds > 0)
                                          Text(
                                            '¡TODOS LISTOS! Iniciando en $_countdownSeconds...',
                                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                                            textAlign: TextAlign.center,
                                          )
                                        else
                                          const Text('LISTO! ESPERANDO A OTROS...', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  
                                  // Cancel Ready Button (Small)
                                  if (isMeReady)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: TextButton(
                                        onPressed: _isTogglingReady ? null : () => _toggleReady(context, widget.tableId, false),
                                        child: const Text('Cancelar (No estoy listo)', style: TextStyle(color: Colors.white54)),
                                      ),
                                    ),
                            ],

                              // Host Force Start (If playing host)
                              if (isHost && !isSpectator && allReady)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _isStarting ? null : () => _startGame(context),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green, 
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                      ),
                                      child: _isStarting 
                                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                          : const Text('INICIAR PARTIDA AHORA'),
                                    ),
                                  ),
                                ),
                          ] else
                            const Text(
                              'Esperando más jugadores para habilitar el inicio...',
                              style: TextStyle(color: Colors.white38),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline,
              size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text('La sala está vacía',
              style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player, bool isReady, String? hostId) {
    final isHost = player['id'] == hostId;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isReady ? Colors.green : Colors.white10,
              width: isReady ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isReady ? Colors.green : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.black26,
                  backgroundImage: player['photoUrl'] != null
                      ? NetworkImage(player['photoUrl'])
                      : null,
                  child: player['photoUrl'] == null
                      ? const Icon(Icons.person, color: Colors.white70, size: 30)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              // Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  player['name'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              // Chips
              Text(
                '🪙 ${player['chips'] ?? 0}',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
              ),
            ],
          ),
        ),
        
        // Host Badge
        if (isHost)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('HOST', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
          
        // Ready Badge (Checkmark)
        if (isReady)
          const Positioned(
            bottom: 8,
            right: 8,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.green,
              child: Icon(Icons.check, color: Colors.white, size: 16),
            ),
          ),
      ],
    );
  }

  Future<void> _toggleReady(BuildContext context, String tableId, bool ready) async {
    setState(() => _isTogglingReady = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final tableRef = FirebaseFirestore.instance.collection('poker_tables').doc(tableId);
      
      await tableRef.update({
        'readyPlayers': ready ? FieldValue.arrayUnion([currentUser.uid]) : FieldValue.arrayRemove([currentUser.uid]),
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingReady = false);
    }
  }

  Future<void> _startGame(BuildContext context) async {
    _cancelCountdown();
    setState(() => _isStarting = true);
    
    // Debug info
    final currentUser = FirebaseAuth.instance.currentUser;
    print('Attempting to start game. User: ${currentUser?.uid}, Table: ${widget.tableId}');

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('startGameFunction').call({
        'tableId': widget.tableId,
      });
      // Navigation handled by stream
    } catch (e) {
      if (mounted) {
        print('Error starting game: $e');
        String errorMessage = e.toString();
        if (e is FirebaseFunctionsException) {
          errorMessage = '${e.code}: ${e.message}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar: $errorMessage'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() {
          _isStarting = false;
          _autoStartFailed = true; // Stop auto-retry
        });
      }
    }
  }
}

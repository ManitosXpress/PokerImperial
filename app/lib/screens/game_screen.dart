import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/socket_service.dart';
import '../providers/language_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/club_provider.dart';
import '../widgets/poker_card.dart';
import '../widgets/player_seat.dart';
import '../utils/responsive_utils.dart';
import '../widgets/chip_stack.dart';
import '../widgets/game_wallet_dialog.dart';
import '../game_controllers/practice_game_controller.dart';
import '../widgets/game/betting_dialog.dart';
import 'table_lobby_screen.dart';

import '../widgets/game/victory_overlay.dart';
import '../widgets/game/action_controls.dart';
import '../widgets/game/rebuy_dialog.dart'; // Import RebuyDialog
import '../widgets/game/wallet_badge.dart'; // Import WalletBadge

class GameScreen extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic>? initialGameState;
  final bool isPracticeMode;
  final bool isSpectatorMode;
  final bool isTournamentMode;
  final String? clubOwnerId;
  final String? currentUserId;

  const GameScreen({
    super.key,
    required this.roomId,
    this.initialGameState,
    this.isPracticeMode = false,
    this.isSpectatorMode = false,
    this.isTournamentMode = false,
    this.clubOwnerId,
    this.currentUserId,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Map<String, dynamic>? gameState;
  Map<String, dynamic>? roomState;
  bool _startConfirmationShown = false;
  bool _isJoining = false; 
  Timer? _retryJoinTimer;
  bool _socketReady = false; // Track socket connection state

  // Practice Mode Controller
  PracticeGameController? _practiceController;
  final String _localPlayerId = 'local-player';

  // Victory screen state
  bool _showVictoryScreen = false;
  Map<String, dynamic>? _winnerData;

  // Turn Timer
  Timer? _turnTimer;
  int _secondsRemaining = 10;
  
  // Rebuy Dialog State
  bool _isRebuyDialogShowing = false;
  
  // Club Leader Mode
  bool get isClubLeader => widget.currentUserId != null && 
                           widget.clubOwnerId != null && 
                           widget.currentUserId == widget.clubOwnerId;

  @override
  void initState() {
    super.initState();

    if (widget.initialGameState != null) {
      gameState = widget.initialGameState;
    }

    if (widget.isPracticeMode) {
      _initPracticeMode();
    } else {
      _initOnlineMode();
    }
  }

  void _initPracticeMode() {
    _practiceController = PracticeGameController(
      humanPlayerId: _localPlayerId,
      humanPlayerName: 'You',
      onStateChange: (newState) {
        if (mounted) {
          setState(() {
            gameState = newState;
            if (newState['status'] == 'finished' &&
                newState['winners'] != null) {
              _showVictoryScreen = true;
              _winnerData = newState['winners'];
            }
          });
          _checkTurnTimer();
        }
      },
    );
  }

  void _initOnlineMode() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    final clubProvider = Provider.of<ClubProvider>(context, listen: false);

    final userRole = clubProvider.currentUserRole;
    final isSpectatorRole = userRole == 'club' || userRole == 'seller' || userRole == 'admin';
    
    // FIX: Treat Admin/Club/Seller as Spectator even if widget.isSpectatorMode is false
    final shouldJoinAsSpectator = widget.isSpectatorMode || isSpectatorRole;
    
    if (shouldJoinAsSpectator) {
      setState(() => _isJoining = true);
      
      try {
        await socketService.connect();
        final connected = await socketService.waitForConnection();
        
        if (mounted && connected) {
          _setupSocketListeners(socketService);
          _attemptJoinSpectator();
          setState(() => _socketReady = true);
        } else if (mounted) {
          setState(() => _isJoining = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se pudo conectar al servidor'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Error connecting to socket: $e');
        if (mounted) {
          setState(() => _isJoining = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de conexión: ${e.toString()}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else if (user != null) {
      setState(() => _isJoining = true);
      
      try {
        await socketService.connect();
        final connected = await socketService.waitForConnection();
        
        if (mounted && connected) {
          _setupSocketListeners(socketService);
          
          if (user != null) {
            _attemptJoinOrCreate(user);
          }
          
          setState(() => _socketReady = true);
        } else if (mounted) {
          setState(() => _isJoining = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se pudo conectar al servidor'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Error connecting to socket: $e');
        if (mounted) {
          setState(() => _isJoining = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de conexión: ${e.toString()}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      // This should only happen if user is null and not spectator?
      print('User not logged in and not spectator, cannot join.');
    }
  }

  void _setupSocketListeners(SocketService socketService) {
    // FIX: Synchronous check for already connected socket
    if (socketService.socket.connected) {
      print('🔌 Socket already connected (Synchronous Check).');
      if (widget.isSpectatorMode && mounted) {
        print('🔓 Force unlocking loading screen for Spectator/Admin (Synchronous)');
        setState(() {
          _isJoining = false;
          _socketReady = true;
        });
      }
    }

    socketService.socket.on('connect', (_) {
      print('✅ Socket connected (GameScreen)');
      // FIX: Force unlock for spectators immediately upon connection
      if (widget.isSpectatorMode && mounted) {
        print('🔓 Force unlocking loading screen for Spectator/Admin');
        setState(() {
          _isJoining = false;
          _socketReady = true;
        });
      }
    });

    socketService.socket.on('spectator_joined', (data) {
       print('👀 spectator_joined received: $data');
       if (mounted) {
         setState(() {
           _isJoining = false;
           _socketReady = true;
           
           // --- CRITICAL FIX: Hydrate players from gameState.activePlayers ---
           if (data != null && data['gameState'] != null && data['gameState']['activePlayers'] != null) {
             final serverPlayers = data['gameState']['activePlayers'] as List;
             
             // Build roomState with properly mapped players
             roomState = {
               ...Map<String, dynamic>.from(data),
               'players': serverPlayers.map((p) {
                 // Map server player format to expected roomState player format
                 return {
                   'id': p['oddsId'] ?? p['oddsid'] ?? p['id'] ?? '',
                   'oddsId': p['oddsId'] ?? p['oddsid'] ?? p['id'] ?? '',
                   'oddsid': p['oddsId'] ?? p['oddsid'] ?? p['id'] ?? '', // Support both casing
                   'name': p['name'] ?? p['displayName'] ?? 'Player',
                   'chips': p['chips'] ?? p['buyIn'] ?? 0,
                   'isReady': p['isReady'] ?? true,
                   'isHost': p['isHost'] ?? false,
                 };
               }).toList(),
               // Preserve other important fields from gameState
               'hostId': data['gameState']['hostId'] ?? data['hostId'],
               'maxPlayers': data['gameState']['maxPlayers'] ?? data['maxPlayers'] ?? 8,
               'smallBlind': data['gameState']['smallBlind'] ?? data['smallBlind'] ?? 10,
               'bigBlind': data['gameState']['bigBlind'] ?? data['bigBlind'] ?? 20,
             };
             
             print('✅ Lista de jugadores hidratada para Admin/Spectator: ${(roomState!['players'] as List).length} jugadores');
           } else {
             // Fallback: just use the received data if structure is different
             roomState = data;
             print('⚠️ spectator_joined: No activePlayers found, using raw data');
           }
         });
         _retryJoinTimer?.cancel();
       }
    });

    socketService.socket.on('player_joined', (data) {
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_created', (data) {
      print('🔵 room_created received: $data');
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_joined', (data) {
      print('🟢 room_joined received: $data');
      if (mounted) {
        setState(() {
          roomState = data;
          _isJoining = false;
        });
        _retryJoinTimer?.cancel();
      }
    });

    socketService.socket.on('game_started', (data) {
      print('🎮 GAME_STARTED received!');
      if (mounted) {
        setState(() {
          roomState = null;
          gameState = data;
        });
        _checkTurnTimer();
      }
    });

    socketService.socket.on('game_update', (data) {
      if (mounted) _updateState(data);
    });

    socketService.socket.on('hand_winner', (data) {
      if (mounted) {
        setState(() {
          // Actualizar el estado del juego con las cartas y handRank de todos los jugadores
          if (data['gameState'] != null) {
            final updatedGameState = Map<String, dynamic>.from(data['gameState']);
            
            // Establecer el estado a showdown para mostrar todas las cartas
            updatedGameState['stage'] = 'showdown';
            updatedGameState['status'] = 'finished';
            
            // Actualizar los jugadores con sus cartas y handRank del evento hand_winner
            if (data['players'] != null && updatedGameState['players'] != null) {
              final playersFromEvent = data['players'] as List;
              final playersInState = updatedGameState['players'] as List;
              
              // Crear un mapa de jugadores del evento para acceso rápido
              final playersMap = <String, Map<String, dynamic>>{};
              for (var player in playersFromEvent) {
                playersMap[player['id']] = player;
              }
              
              // Actualizar cada jugador en el estado con sus cartas y handRank
              for (int i = 0; i < playersInState.length; i++) {
                final playerId = playersInState[i]['id'];
                if (playersMap.containsKey(playerId)) {
                  final playerData = playersMap[playerId]!;
                  playersInState[i] = {
                    ...playersInState[i],
                    'hand': playerData['hand'],
                    'handRank': playerData['handDescription'],
                  };
                }
              }
            }
            
            // Actualizar winners en el estado del juego
            if (data['winner'] != null) {
              final winnerId = data['winner']['id'];
              updatedGameState['winners'] = {
                'winners': [
                  <String, dynamic>{
                    'playerId': winnerId,
                    'amount': data['winner']['amount'] ?? 0,
                  }
                ]
              };
            } else if (data['winners'] != null) {
              // Múltiples ganadores (split pot)
              final winnersList = (data['winners'] as List).map<Map<String, dynamic>>((w) => 
                <String, dynamic>{
                  'playerId': w['id'],
                  'amount': w['amount'] ?? 0,
                }
              ).toList();
              updatedGameState['winners'] = {
                'winners': winnersList,
              };
            }
            
            gameState = updatedGameState;
          }
          
          // Asegurar que winnerData tenga toda la información necesaria
          // Incluir gameState para que VictoryOverlay pueda verificar winners
          final enhancedWinnerData = Map<String, dynamic>.from(data);
          if (gameState != null) {
            enhancedWinnerData['gameState'] = gameState;
          }
          
          _showVictoryScreen = true;
          _winnerData = enhancedWinnerData;
        });
        Future.delayed(const Duration(milliseconds: 5000), () {
          if (mounted) {
            setState(() {
              _showVictoryScreen = false;
              _winnerData = null;
            });
          }
        });
      }
    });

    // --- NEW: System Events Listeners ---
    socketService.socket.on('player_needs_rebuy', (data) {
       final myId = socketService.socketId;
       if (data['playerId'] == myId) {
          _showRebuyDialog(data['timeout'] ?? 30);
       }
    });

    socketService.socket.on('error', (error) {
       if (error.toString().contains('kicked')) {
          _handleKicked(error.toString());
       }
    });
    
    // Listen for room closing or forcing disconnect
    socketService.socket.on('room_closed', (data) {
       _handleRoomClosed(data['reason']);
    });

    socketService.socket.on('player_left', (data) {
       // Check if I was kicked (sometimes server sends player_left with my ID)
       // But 'error' usually handles the kick message
       if (mounted) {
          // If we are in waiting room, update state
          if (roomState != null) {
              // Usually roomState update comes via player_left with room data
              setState(() => roomState = data);
          }
       }
    });
  }
  
  void _showRebuyDialog(int timeoutSeconds) {
    if (_isRebuyDialogShowing) return;
    _isRebuyDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RebuyDialog(
        timeoutSeconds: timeoutSeconds,
        onRebuy: (amount) {
           final socketService = Provider.of<SocketService>(context, listen: false);
           socketService.topUp(widget.roomId, amount.toDouble(), 
              onSuccess: (newAmount) {
                 Navigator.pop(context); // Close dialog
                 _isRebuyDialogShowing = false;
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recarga exitosa! Volviendo al juego...'), backgroundColor: Colors.green)
                 );
                 // WalletProvider updates automatically via streams from Firestore
              },
              onError: (err) {
                 // Close loading state in dialog? 
                 // Actually the dialog handles its own state, but we need to tell it to stop loading or show error.
                 // For simplicity, we pop and show snackbar, user can try again if the event re-fires?
                 // But event might not re-fire.
                 Navigator.pop(context); 
                 _isRebuyDialogShowing = false;
                 
                 ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red)
                 );
                 
                 // If failed, we are likely still in WAITING_FOR_REBUY state, 
                 // so we might need to re-trigger dialog?
                 // Or we just let them sit there until kick?
                 // Ideally, dialog should handle error internally. 
                 // But `RebuyDialog` is simple.
              }
           );
        },
        onLeave: () {
           Navigator.pop(context);
           _leaveGame();
        },
      ),
    ).then((_) {
       _isRebuyDialogShowing = false;
    });
  }
  
  void _handleKicked(String reason) {
     if (_isRebuyDialogShowing) {
        Navigator.of(context).pop(); // Close dialog if open
     }
     
     showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
           title: const Text('Expulsado'),
           content: Text(reason),
           actions: [
              TextButton(
                 onPressed: () {
                    Navigator.of(ctx).pop();
                    _leaveGame();
                 }, 
                 child: const Text('OK')
              )
           ],
        )
     );
  }
  
  void _handleRoomClosed(String? reason) async {
     if (_isRebuyDialogShowing) {
        Navigator.of(context).pop();
     }
     
     // CRÍTICO: Llamar a la Cloud Function para procesar la liquidación
     // Esto garantiza que solo se ejecute UNA VEZ y con el algoritmo correcto
     try {
        await FirebaseFunctions.instance.httpsCallable('closeTableAndCashOutFunction').call({
           'tableId': widget.roomId,
        });
        print('✅ Liquidación procesada por Cloud Function para mesa ${widget.roomId}');
     } catch (e) {
        print('❌ Error al llamar a closeTableAndCashOutFunction: $e');
        // Continuar de todas formas para que el usuario pueda salir
     }
     
     showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
           title: const Text('Mesa Cerrada'),
           content: Text(reason ?? 'La partida ha terminado.'),
           actions: [
              TextButton(
                 onPressed: () {
                    Navigator.of(ctx).pop();
                    _leaveGame();
                 }, 
                 child: const Text('Volver al Lobby')
              )
           ],
        )
     );
  }
  
  void _leaveGame() {
     final socketService = Provider.of<SocketService>(context, listen: false);
     socketService.disconnect();
     socketService.clearCurrentRoom(); // Clear active room ref
     
     // Pop until lobby
     Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _attemptJoinOrCreate(User user) async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    // Check if we are Host in Firestore
    bool isHostInFirestore = false;
    try {
       final tableDoc = await FirebaseFirestore.instance.collection('poker_tables').doc(widget.roomId).get();
       if (tableDoc.exists) {
          final data = tableDoc.data();
          if (data != null && data['hostId'] == user.uid) {
             isHostInFirestore = true;
          }
       }
    } catch(e) {
       print('Error checking host status: $e');
    }

    void tryJoin() {
       print('Attempting to join room ${widget.roomId}...');
       socketService.joinRoom(
          widget.roomId, 
          user.displayName ?? 'Player',
          onSuccess: (roomId) {
             print('Joined room $roomId on socket');
          },
          onError: (err) {
            print('Socket Join Error: $err');
            String errorMsg = err.toString();
            
            if (errorMsg.contains('Room not found')) {
                if (isHostInFirestore) {
                    print('Room not found, creating as Host...');
                    socketService.createRoom(
                        user.displayName ?? 'Player',
                        roomId: widget.roomId,
                        onSuccess: (newRoomId) {
                           print('Created room $newRoomId on socket as Host');
                        },
                        onError: (createErr) {
                           print('Error creating room: $createErr');
                           _scheduleRetry(user);
                        }
                    );
                } else {
                    print('Room not found, waiting for Host to create...');
                    _scheduleRetry(user);
                }
                return;
            } else if (errorMsg.contains('Room already exists')) {
                 _scheduleRetry(user);
            } else {
                 if (mounted && !widget.isSpectatorMode) {
                    if (errorMsg.contains('Insufficient balance') || errorMsg.contains('Crédito insuficiente')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $errorMsg'), backgroundColor: Colors.red),
                        );
                        setState(() => _isJoining = false);
                        return; 
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $errorMsg'), backgroundColor: Colors.red),
                    );
                 }
                 _scheduleRetry(user);
            }
          }
        );
    }
    
    tryJoin();
  }

  void _scheduleRetry(User user) {
     _retryJoinTimer?.cancel();
     _retryJoinTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
           _attemptJoinOrCreate(user);
        }
     });
  }

  void _attemptJoinSpectator() {
     final socketService = Provider.of<SocketService>(context, listen: false);
     final user = FirebaseAuth.instance.currentUser;
     print('Attempting to join room ${widget.roomId} as SPECTATOR (via joinRoom)...');
     
     // Use joinRoom with isSpectator: true to leverage the backend fix
     socketService.joinRoom(
        widget.roomId,
        user?.displayName ?? 'Spectator',
        isSpectator: true,
        onSuccess: (roomId) {
           print('Joined room $roomId as spectator');
           if (mounted) setState(() => _isJoining = false);
        },
        onError: (err) {
           print('Spectator Join Error: $err');
           _scheduleRetrySpectator();
        }
     );
  }

  void _scheduleRetrySpectator() {
     _retryJoinTimer?.cancel();
     _retryJoinTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
           _attemptJoinSpectator();
        }
     });
  }

  @override
  void dispose() {
    _practiceController?.dispose();
    _stopTurnTimer();
    _retryJoinTimer?.cancel();

    if (!widget.isPracticeMode) {
      try {
        final socketService = Provider.of<SocketService>(context, listen: false);
        socketService.socket.off('player_joined');
        socketService.socket.off('room_created');
        socketService.socket.off('room_joined');
        socketService.socket.off('game_started');
        socketService.socket.off('game_update');
        socketService.socket.off('hand_winner');
        socketService.socket.off('player_needs_rebuy');
        socketService.socket.off('room_closed');
        socketService.socket.off('player_left');
        socketService.socket.off('error');
      } catch (e) {
        // Socket service might be disposed already
      }
    }

    super.dispose();
  }

  void _updateState(dynamic data) {
    if (data == null) return;
    setState(() => gameState = data);
    _checkTurnTimer();
  }

  void _checkTurnTimer() {
    if (gameState == null) {
      _stopTurnTimer();
      return;
    }
    
    try {
      final socketService = Provider.of<SocketService>(context, listen: false);
      final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;

      // Check if I am in the game
      bool isPlayerInGame = false;
      if (gameState != null && gameState!['players'] != null) {
         final players = gameState!['players'] as List;
         isPlayerInGame = players.any((p) => p['id'] == myId);
      }

      if (widget.isSpectatorMode || !isPlayerInGame) {
        _stopTurnTimer();
        return;
      }

      if (gameState!['currentTurn'] == myId) {
        if (_turnTimer == null || !_turnTimer!.isActive) {
          _startTurnTimer();
        }
      } else {
        _stopTurnTimer();
      }
    } catch(e) {
      print('Error in checkTurnTimer: $e');
    }
  }

  void _startTurnTimer() {
    _stopTurnTimer();
    setState(() => _secondsRemaining = 10);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _handleTimeout();
          }
        });
      }
    });
  }

  void _stopTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
  }

  void _handleTimeout() {
    _stopTurnTimer();
    if (gameState == null) return;
    
    final int currentBet = gameState!['currentBet'] ?? 0;
    final socketService = Provider.of<SocketService>(context, listen: false);
    final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    
    final players = gameState!['players'] as List?;
    if (players == null) return;

    final myPlayerIndex = players.indexWhere((p) => p['id'] == myId);
    if (myPlayerIndex == -1) return;
    
    final myPlayer = players[myPlayerIndex];
    final int myCurrentBet = myPlayer['currentBet'] ?? 0;

    if (currentBet <= myCurrentBet) {
      _sendAction('check');
    } else {
      _sendAction('fold');
    }
  }

  void _sendAction(String action, [int amount = 0]) {
    if (widget.isPracticeMode) {
      _practiceController?.handleAction(_localPlayerId, action, amount);
    } else {
      final socketService = Provider.of<SocketService>(context, listen: false);
      
      // Guard: Don't send actions if spectator
      final myId = socketService.socketId;
      bool isPlayerInGame = false;
      if (gameState != null && gameState!['players'] != null) {
         final players = gameState!['players'] as List;
         isPlayerInGame = players.any((p) => p['id'] == myId);
      }
      
      if (widget.isSpectatorMode || !isPlayerInGame) {
         print('⛔ Blocked action $action from spectator/non-player');
         return;
      }

      print('🎲 Sending game_action: roomId=${widget.roomId}, action=$action, amount=$amount');
      socketService.socket.emit('game_action',
          {'roomId': widget.roomId, 'action': action, 'amount': amount});
      print('📤 game_action emitted');
    }
  }

  void _showCustomBetDialog() {
    if (gameState == null) return;

    final socketService = Provider.of<SocketService>(context, listen: false);
    final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    
    final players = gameState!['players'] as List?;
    if (players == null) return;

    final myPlayerIndex = players.indexWhere((p) => p['id'] == myId);
    if (myPlayerIndex == -1) return;
    
    final myPlayer = players[myPlayerIndex];

    final int myChips = myPlayer['chips'] ?? 0;
    final int currentBet = gameState!['currentBet'] ?? 0;
    final int myCurrentBet = myPlayer['currentBet'] ?? 0;
    final int minBet = gameState!['minBet'] ?? (currentBet + 20);
    final int pot = gameState!['pot'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => BettingDialog(
        currentBet: currentBet,
        myChips: myChips,
        myCurrentBet: myCurrentBet,
        pot: pot,
        minBet: minBet,
        onBet: (amount) => _sendAction('bet', amount),
      ),
    );
  }

  void _startGame() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.socket.emit('start_game', {'roomId': widget.roomId});
    print('🎮 Emitted start_game event for room ${widget.roomId}');
  }

  @override
  Widget build(BuildContext context) {
    // ... (Keep existing build method exactly as is)
    // For brevity, I will assume the tool handles replacement correctly if I provide the whole file content.
    // However, the file is long. I will copy the build method content.
    // NOTE: To avoid risk of truncation or error in the build method copy-paste,
    // I will return the full file content including the build method from previous read.
    // Please assume the build method is unchanged from the read file, just wrapped in the new class structure.
    
    final socketService = Provider.of<SocketService>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final clubProvider = Provider.of<ClubProvider>(context);
    final user = FirebaseAuth.instance.currentUser;

    final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    final userRole = clubProvider.currentUserRole ?? 'player';
    
    bool isTurn = false;
    if (gameState != null && gameState!['currentTurn'] != null) {
      isTurn = gameState!['currentTurn'] == myId;
    }

    // Dynamic Spectator Detection
    bool isPlayerInGame = false;
    if (gameState != null && gameState!['players'] != null) {
      final players = gameState!['players'] as List;
      isPlayerInGame = players.any((p) => p['id'] == myId);
    }
    
    // Effective Spectator Mode: Explicitly set OR implicitly detected (not in players list)
    final bool effectiveSpectatorMode = widget.isSpectatorMode || (gameState != null && !isPlayerInGame);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${languageProvider.getText('room')}: ${widget.roomId}'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.account_balance_wallet,
                  color: Color(0xFFffd700)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => GameWalletDialog(roomId: widget.roomId),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              icon: Text(
                languageProvider.currentLocale.languageCode == 'en'
                    ? '🇺🇸'
                    : '🇪🇸',
                style: const TextStyle(fontSize: 24),
              ),
              onPressed: () => languageProvider.toggleLanguage(),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker2_background.jpg'),
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
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
          child: gameState == null
              ? Builder(
                  builder: (context) {
                    // Si es modo torneo, saltamos la sala de espera y mostramos un loader
                    // mientras llega el estado del juego (game_started)
                    if (widget.isTournamentMode) {
                       return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                               CircularProgressIndicator(color: Color(0xFFD4AF37)),
                               SizedBox(height: 16),
                               Text('Conectando a la mesa del torneo...', style: TextStyle(color: Colors.white))
                            ],
                          )
                       );
                    }
                    
                    // Show loading screen while socket is connecting
                    if (!_socketReady && !widget.isPracticeMode) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFD4AF37)),
                            SizedBox(height: 16),
                            Text(
                              'Conectando al servidor...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    bool isHost = false;
                    bool isPublic = true;
                    
                    final currentRoomState = roomState;
                    if (currentRoomState != null) {
                      final socketHostId = currentRoomState['hostId'];
                      if (user != null && socketHostId != null) {
                        isHost = socketHostId.toString() == user.uid.toString();
                      }
                      final socketIsPublic = currentRoomState['isPublic'];
                      if (socketIsPublic != null) {
                        isPublic = socketIsPublic as bool? ?? true;
                      }
                    }
                    
                    
                    // Mesa VIP style waiting room
                    final players = (currentRoomState?['players'] as List?) ?? [];
                    final maxPlayers = currentRoomState?['maxPlayers'] ?? 8;
                    final smallBlind = currentRoomState?['smallBlind'] ?? 10;
                    final bigBlind = currentRoomState?['bigBlind'] ?? 20;
                    
                    return Column(
                      children: [
                        const SizedBox(height: 100),
                        
                        // Header: Blinds & Stats (MesaVIP style)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Blinds Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 16),
                                        const SizedBox(width: 8),
                                        Text('Blinds: $smallBlind/$bigBlind', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Players Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.people, color: Color(0xFFFFD700), size: 16),
                                        const SizedBox(width: 8),
                                        Text('Jugadores: ${players.length}/$maxPlayers', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (players.length < 2)
                                const Text(
                                  'Esperando mínimo 2 jugadores...',
                                  style: TextStyle(color: Colors.amber, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                        
                        const Divider(color: Colors.white24),
                        
                        // Players Grid
                        Expanded(
                          child: players.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.person_outline, size: 64, color: Colors.white.withOpacity(0.1)),
                                      const SizedBox(height: 16),
                                      const Text('La sala está vacía', style: TextStyle(color: Colors.white38)),
                                    ],
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(24),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.75,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: players.length,
                                  itemBuilder: (context, index) {
                                    final player = players[index];
                                    final playerName = player['name'] ?? 'Player';
                                    final photoUrl = player['photoUrl'];
                                    final playerChips = player['chips'] ?? 1000;
                                    final isPlayerHost = player['id'] == currentRoomState?['hostId'];
                                    
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white10, width: 1),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CircleAvatar(
                                                radius: 30,
                                                backgroundColor: Colors.black26,
                                                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                                child: photoUrl == null ? const Icon(Icons.person, color: Colors.white70, size: 30) : null,
                                              ),
                                              const SizedBox(height: 8),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                                child: Text(
                                                  playerName,
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                              Text(
                                                '🪙 $playerChips',
                                                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isPlayerHost)
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
                                      ],
                                    );
                                  },
                                ),
                        ),
                        
                        // Footer with Start Button
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            border: Border(top: BorderSide(color: Colors.white12)),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              children: [
                                // Show START GAME button if user has authority
                                // User can start if: Host (jugador) OR Admin/Club (espectador)
                                if (isHost || userRole == 'admin' || userRole == 'club')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: players.length >= 2 ? _startGame : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFD4AF37), // Gold
                                          foregroundColor: Colors.black,
                                          disabledBackgroundColor: Colors.grey[700],
                                          disabledForegroundColor: Colors.grey[500],
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: players.length >= 2 ? 8 : 2,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.play_arrow,
                                              color: players.length >= 2 ? Colors.black : Colors.grey[500],
                                              size: 28,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'INICIAR PARTIDA',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.2,
                                                color: players.length >= 2 ? Colors.black : Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                // Info message
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.hourglass_empty, color: Colors.white70),
                                    const SizedBox(width: 12),
                                    Text(
                                      (isHost || userRole == 'admin' || userRole == 'club')
                                          ? (players.length >= 2 ? 'Todo listo! Presiona para iniciar' : 'Esperando mínimo 2 jugadores...')
                                          : 'Esperando a que el host inicie la partida...',
                                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Stack(
                  children: [
                    // Table
                    Positioned(
                      top: ResponsiveUtils.screenHeight(context) * (ResponsiveUtils.screenWidth(context) < 600 ? 0.35 : 0.4) -
                          ((ResponsiveUtils.screenWidth(context) < 600 ? ResponsiveUtils.screenHeight(context) * 0.45 : ResponsiveUtils.screenHeight(context) * 0.55) / 2),
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Builder(
                          builder: (context) {
                            double screenW =
                                ResponsiveUtils.screenWidth(context);
                            double screenH =
                                ResponsiveUtils.screenHeight(context);
                            bool isMobile = screenW < 600;

                            double tableWidth =
                                isMobile ? screenW * 0.65 : screenW * 0.9;
                            double tableHeight =
                                isMobile ? screenH * 0.60 : screenH * 0.55;

                            if (tableWidth / tableHeight > 2.0) {
                              tableWidth = tableHeight * 2.0;
                            }

                            return Container(
                              width: tableWidth,
                              height: tableHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(150),
                                border: Border.all(
                                    color: const Color(0xFF3E2723),
                                    width: isMobile
                                        ? 15
                                        : 25), // Thinner rail on mobile
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(
                                        0xFFFFF8E1), // Light center (Spotlight)
                                    Color(0xFF5D4037), // Darker edge (Vignette)
                                  ],
                                  stops: [0.2, 1.0],
                                  center: Alignment.center,
                                  radius: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.9),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // Racetrack / Thin Line
                                  Positioned.fill(
                                    child: Container(
                                      margin:
                                          EdgeInsets.all(isMobile ? 10 : 15),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(130),
                                        border: Border.all(
                                            color: const Color(0xFF1C1C1C),
                                            width: 2), // Black Inner Line
                                      ),
                                    ),
                                  ),
                                  // Table Logo (Background)
                                  Center(
                                    child: Opacity(
                                      opacity:
                                          0.5, // Increased opacity as requested
                                      child: Image.asset(
                                        'assets/images/table_logo_imperial.png',
                                        width: tableWidth *
                                            (isMobile
                                                ? 0.5
                                                : 0.4), // Larger logo on mobile
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  // Community Cards
                                  if (gameState!['communityCards'] != null &&
                                      (gameState!['communityCards'] as List)
                                          .isNotEmpty)
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          border: Border.all(
                                              color: Colors.white10, width: 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children:
                                              (gameState!['communityCards']
                                                      as List)
                                                  .map((card) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4.0),
                                              child: PokerCard(
                                                cardCode: card.toString(),
                                                width: ResponsiveUtils.scale(
                                                    context,
                                                    isMobile
                                                        ? 50
                                                        : 45), // Larger cards on mobile
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),

                                  // Pot
                                  Positioned(
                                    top: tableHeight * 0.25,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: const Color(0xFFFFD700)
                                                  .withOpacity(0.5)),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'POT',
                                              style: TextStyle(
                                                color: Color(0xFFFFD700),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Image.asset(
                                                    'assets/images/coin.png',
                                                    width: 16,
                                                    height: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${gameState!['pot'] ?? 0}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Players
                    if (gameState!['players'] != null)
                      ...((gameState!['players'] as List)
                          .asMap()
                          .entries
                          .map((entry) {
                        final playersList = gameState!['players'] as List;
                        final myIndex =
                            playersList.indexWhere((p) => p['id'] == myId);
                        // If I am not in the game (spectator), offset is 0 (neutral view)
                        final int offset = myIndex != -1 ? myIndex : 0;

                        int index = entry.key;
                        Map<String, dynamic> player = entry.value;
                        int totalPlayers = playersList.length;
                        int visualIndex =
                            (index - offset + totalPlayers) % totalPlayers;

                        double screenW = ResponsiveUtils.screenWidth(context);
                        double screenH = ResponsiveUtils.screenHeight(context);
                        bool isMobile = screenW < 600;

                        double tableH =
                            isMobile ? screenH * 0.60 : screenH * 0.55;
                        double tableW =
                            isMobile ? screenW * 0.65 : screenW * 0.9;
                        if (tableW / tableH > 2.0) {
                          tableW = tableH * 2.0;
                        }

                        final double centerX = screenW / 2;
                        final double centerY = screenH * (isMobile ? 0.38 : 0.4);

                        double angleStep = 2 * math.pi / totalPlayers;
                        double startAngle = math.pi / 2;
                        double angle = startAngle + (visualIndex * angleStep);

                        final rX = tableW / 2 +
                            ResponsiveUtils.scale(
                                context, isMobile ? 15 : 45); // Tighter radius
                        final rY = tableH / 2 +
                            ResponsiveUtils.scale(context, isMobile ? 15 : 25);

                        final x = centerX + (rX * math.cos(angle)) - 40;
                        final y = centerY + (rY * math.sin(angle)) - 45;

                        bool isActive =
                            player['id'] == gameState!['currentTurn'];
                        bool isFolded = player['isFolded'] ?? false;
                        bool isMe = player['id'] == myId;
                        bool isDealer = player['id'] == gameState!['dealerId'];

                        List<String>? cards;
                        final bool isShowdown =
                            (gameState!['status'] == 'finished' ||
                                gameState!['stage'] == 'showdown');

                        if (isMe && !isFolded) {
                          final handList = player['hand'] as List?;
                          cards = handList?.map((e) => e.toString()).toList();
                        } else if (!isFolded && isShowdown) {
                          final handList = player['hand'] as List?;
                          cards = handList?.map((e) => e.toString()).toList();
                        }

                        String? handRank;
                        bool isWinner = false;
                        if (isShowdown && !isFolded) {
                          handRank = player['handRank'] as String?;
                          final winners = gameState?['winners'];
                          if (winners != null && winners['winners'] != null) {
                            final winnersList = winners['winners'] as List;
                            isWinner = winnersList
                                .any((w) => w['playerId'] == player['id']);
                          }
                        }

                        final betX =
                            centerX + ((rX - (isMobile ? 35 : 90)) * math.cos(angle)) - 10;
                        final betY =
                            centerY + ((rY - (isMobile ? 35 : 90)) * math.sin(angle)) - 20;

                        double finalY = y;
                        if (isMe) {
                          finalY = ResponsiveUtils.screenHeight(context) -
                              ResponsiveUtils.scaleHeight(
                                  context, isMobile ? 240 : 280);
                        }

                        return Stack(
                          children: [
                            Positioned(
                              left: isMe
                                  ? (ResponsiveUtils.screenWidth(context) / 2) -
                                      40
                                  : x,
                              top: finalY,
                              child: PlayerSeat(
                                name: player['name'],
                                chips: (player['chips'] is int) ? player['chips'] : int.tryParse(player['chips'].toString()) ?? 0,
                                isActive: isActive,
                                isMe: isMe,
                                isDealer: isDealer,
                                isFolded: isFolded,
                                cards: cards,
                                handRank: handRank,
                                isWinner: isWinner,
                              ),
                            ),
                            if (player['currentBet'] > 0)
                              Positioned(
                                left: betX,
                                top: betY,
                                child: Column(
                                  children: [
                                    ChipStack(amount: player['currentBet']),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${player['currentBet']}',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isMobile ? 12 : 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }).toList()),

                    // Top Right Credits - Premium Wallet Badge
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: WalletBadge(),
                    ),

                    // Action Controls (Refactored Widget)
                    // Always render ActionControls, it handles spectator mode internally
                    ActionControls(
                      isTurn: isTurn,
                      isSpectatorMode: effectiveSpectatorMode,
                      currentBet: gameState?['currentBet'] ?? 0,
                      myCurrentBet: () {
                        final players = gameState?['players'] as List?;
                        if (players == null) return 0;
                        final idx = players.indexWhere((p) => p['id'] == myId);
                        return idx >= 0 ? (players[idx]['currentBet'] ?? 0) : 0;
                      }(),
                      secondsRemaining: _secondsRemaining,
                      onAction: _sendAction,
                      onShowBetDialog: _showCustomBetDialog,
                    ),

                    // Victory Screen Overlay (Refactored Widget)
                    if (_showVictoryScreen && _winnerData != null)
                      VictoryOverlay(
                        winnerData: _winnerData!,
                        onContinue: widget.isPracticeMode
                            ? () {
                                _practiceController?.startNextHand();
                                setState(() {
                                  _showVictoryScreen = false;
                                  _winnerData = null;
                                });
                              }
                            : null,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

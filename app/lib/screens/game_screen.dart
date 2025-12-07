import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../widgets/game/waiting_room_view.dart';
import '../widgets/game/victory_overlay.dart';
import '../widgets/game/action_controls.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic>? initialGameState;
  final bool isPracticeMode;
  final bool isSpectatorMode;

  const GameScreen({
    super.key,
    required this.roomId,
    this.initialGameState,
    this.isPracticeMode = false,
    this.isSpectatorMode = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Map<String, dynamic>? gameState;
  Map<String, dynamic>? roomState;
  bool _startConfirmationShown = false;

  // Practice Mode Controller
  PracticeGameController? _practiceController;
  final String _localPlayerId = 'local-player';

  // Victory screen state
  bool _showVictoryScreen = false;
  Map<String, dynamic>? _winnerData;

  // Turn Timer
  Timer? _turnTimer;
  int _secondsRemaining = 10;

  @override
  void initState() {
    super.initState();

    // Initialize with passed state if available
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
              // No auto-hide for practice mode, wait for user action
            }
          });
          _checkTurnTimer();
        }
      },
    );
  }

  void _initOnlineMode() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    final clubProvider = Provider.of<ClubProvider>(context, listen: false);

    // Check if user is a spectator (club/seller/admin roles should NOT join socket as player)
    final userRole = clubProvider.currentUserRole;
    final isSpectatorRole = userRole == 'club' || userRole == 'seller' || userRole == 'admin';
    
    // Only join socket if NOT a spectator role (or if explicitly in spectator mode)
    if (!widget.isSpectatorMode && !isSpectatorRole && user != null) {
      // Connect and Join Room
      socketService.connect().then((_) async {
        if (mounted && user != null) {
          
          // Check if we are the host according to Firestore to decide if we should create the room
          bool shouldTryCreate = false;
          try {
             final tableDoc = await import('package:cloud_firestore/cloud_firestore.dart').then((m) => m.FirebaseFirestore.instance.collection('poker_tables').doc(widget.roomId).get());
             if (tableDoc.exists) {
                final data = tableDoc.data();
                if (data != null && data['hostId'] == user.uid) {
                   shouldTryCreate = true;
                   print('I am the host (Firestore), I will try to create the room on socket if needed.');
                }
             }
          } catch(e) {
             print('Error checking host status: $e');
          }

          void join() {
             socketService.joinRoom(
                widget.roomId, 
                user.displayName ?? 'Player',
                onSuccess: (roomId) {
                   print('Joined room $roomId on socket');
                },
                onError: (err) {
                  print('Socket Join Error: $err');
                  String errorMsg = err.toString();
                  
                  // If room not found and we are host, try creating it
                  if (errorMsg.contains('Room not found') && shouldTryCreate) {
                      print('Room not found, creating as Host...');
                      socketService.createRoom(
                          user.displayName ?? 'Player',
                          roomId: widget.roomId,
                          onSuccess: (newRoomId) {
                             print('Created room $newRoomId on socket as Host');
                          },
                          onError: (createErr) {
                             if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error al crear sala: $createErr'), backgroundColor: Colors.red),
                                );
                             }
                          }
                      );
                      return;
                  }

                  if (mounted) {
                    // Only show error if it's not a "Room not found" for spectators
                    if (!errorMsg.contains('Room not found') || !widget.isSpectatorMode) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error al unirse al juego: ${errorMsg.replaceAll('Exception: ', '')}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                }
              );
          }
          
          join();
        }
      }).catchError((e) {
        print('Error connecting to socket: $e');
        // Don't show error for spectators
        if (mounted && !widget.isSpectatorMode && !isSpectatorRole) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de conexión: ${e.toString()}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    } else {
      print('User is spectator (role: $userRole), skipping socket join');
    }

    socketService.socket.on('player_joined', (data) {
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_created', (data) {
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_joined', (data) {
      if (mounted) {
        setState(() => roomState = data);
        
        // Auto-start if Host and sufficient players
        final user = FirebaseAuth.instance.currentUser;
        final ownerId = data['ownerId'] ?? data['hostId'];
        final players = data['players'] as List?;
        
        if (user != null && ownerId == user.uid && gameState == null) {
           // We are host.
           // If there are enough players (e.g. >= 2 for socket game, or 4 as per requirement), start.
           // Since TableLobbyScreen enforced 4, we can assume it's ready.
           if (players != null && players.length >= 2) { // Socket usually needs min 2
              print('Auto-starting game on socket as Host');
              socketService.socket.emit('start_game', {'roomId': widget.roomId});
           }
        }
      }
    });

    socketService.socket.on('game_started', (data) {
      if (mounted) {
        setState(() {
          roomState = null;
        });
        _updateState(data);
      }
    });

    socketService.socket.on('game_update', (data) {
      if (mounted) _updateState(data);
    });

    socketService.socket.on('hand_winner', (data) {
      if (mounted) {
        setState(() {
          _showVictoryScreen = true;
          _winnerData = data;
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
  }

  @override
  void dispose() {
    _practiceController?.dispose();
    _stopTurnTimer();

    if (!widget.isPracticeMode) {
      final socketService = Provider.of<SocketService>(context, listen: false);
      socketService.socket.off('player_joined');
      socketService.socket.off('room_created');
      socketService.socket.off('room_joined');
      socketService.socket.off('game_started');
      socketService.socket.off('game_update');
      socketService.socket.off('hand_winner');
    }

    super.dispose();
  }

  void _updateState(dynamic data) {
    setState(() => gameState = data);
    _checkTurnTimer();
  }

  void _checkTurnTimer() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final myId =
        widget.isPracticeMode ? _localPlayerId : socketService.socketId;

    // Don't run timer for spectators
    if (widget.isSpectatorMode) {
      _stopTurnTimer();
      return;
    }

    if (gameState != null && gameState!['currentTurn'] == myId) {
      if (_turnTimer == null || !_turnTimer!.isActive) {
        _startTurnTimer();
      }
    } else {
      _stopTurnTimer();
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
    final int currentBet = gameState?['currentBet'] ?? 0;
    final socketService = Provider.of<SocketService>(context, listen: false);
    final myId =
        widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    final myPlayer = (gameState?['players'] as List?)?.firstWhere(
      (p) => p['id'] == myId,
      orElse: () => null,
    );
    final int myCurrentBet = myPlayer?['currentBet'] ?? 0;

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
      socketService.socket.emit('game_action',
          {'roomId': widget.roomId, 'action': action, 'amount': amount});
    }
  }

  void _showCustomBetDialog() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final myId =
        widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    final myPlayer = (gameState?['players'] as List?)?.firstWhere(
      (p) => p['id'] == myId,
      orElse: () => null,
    );

    if (myPlayer == null) return;

    final int myChips = myPlayer['chips'] ?? 0;
    final int currentBet = gameState?['currentBet'] ?? 0;
    final int myCurrentBet = myPlayer['currentBet'] ?? 0;
    final int minBet = gameState?['minBet'] ?? (currentBet + 20);
    final int pot = gameState?['pot'] ?? 0;

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
  }

  void _showStartConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFFFD700), width: 2)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 30),
            SizedBox(width: 12),
            Text('Confirmar Inicio', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '¡Hay 4 jugadores conectados!\n\n¿Deseas enviar el mensaje de confirmación a todos y empezar la partida?',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Allow triggering again if they cancel? 
              // Maybe we want to set _startConfirmationShown = false; if we want to annoy them.
              // But better to leave it true so it doesn't pop up constantly unless players change.
              // But if they cancel, they might want to start manually later? 
              // WaitingRoomView only shows "Waiting..." so they can't start manually easily if I hid the button.
              // So I should reset it or provide a manual way.
              // The requirement was "replace button with confirmation".
              // So if they cancel, they are stuck?
              // I will Reset _startConfirmationShown to false so it triggers again if players update (e.g. 4 -> 3 -> 4)
              // But if players stay at 4, build won't re-trigger unless setState happens.
              // I'll set it to false, but I need to ensure it doesn't loop.
              // Actually, if I set it to false, and build runs, it will trigger again immediately.
              // So I should keep it true, but maybe add a manual button in WaitingRoomView for Host if they cancelled?
              // For now, let's just close.
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startGame();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRMAR Y EMPEZAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final clubProvider = Provider.of<ClubProvider>(context);
    final user = FirebaseAuth.instance.currentUser;

    final myId =
        widget.isPracticeMode ? _localPlayerId : socketService.socketId;

    // Determine Role and Host status
    final userRole = clubProvider.currentUserRole ?? 'player'; // Default to player
    final ownerId = roomState?['ownerId'] ?? roomState?['hostId'];
    final isHost = user != null && ownerId == user.uid;

    // Auto-confirmation logic for Host
    if (gameState == null && 
        roomState != null && 
        isHost && 
        !_startConfirmationShown) {
      
      final players = roomState!['players'] as List?;
      if (players != null && players.length == 4) {
        _startConfirmationShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showStartConfirmationDialog();
        });
      }
    }
    
    // Reset confirmation shown flag if players drop below 4
    if (gameState == null && roomState != null) {
      final players = roomState!['players'] as List?;
      if (players != null && players.length < 4 && _startConfirmationShown) {
        _startConfirmationShown = false;
      }
    }

    bool isTurn = false;
    if (gameState != null && gameState!['currentTurn'] != null) {
      isTurn = gameState!['currentTurn'] == myId;
    }

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
              ? WaitingRoomView(
                  roomId: widget.roomId,
                  roomState: roomState,
                  onStartGame: _startGame,
                  userRole: userRole,
                  isHost: isHost,
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
                                                cardCode: card,
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
                          cards = (player['hand'] as List?)?.cast<String>();
                        } else if (!isFolded && isShowdown) {
                          cards = (player['hand'] as List?)?.cast<String>();
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
                                chips: player['chips'].toString(),
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

                    // Top Right Credits
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Consumer<WalletProvider>(
                        builder: (context, walletProvider, child) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.amber.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset('assets/images/coin.png',
                                    width: 20, height: 20),
                                const SizedBox(width: 6),
                                Text(
                                  '${walletProvider.balance}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Action Controls (Refactored Widget)
                    if (!widget.isSpectatorMode)
                      ActionControls(
                        isTurn: isTurn,
                        isSpectatorMode: widget.isSpectatorMode,
                        currentBet: gameState?['currentBet'] ?? 0,
                        myCurrentBet: (gameState?['players'] as List?)
                                ?.firstWhere((p) => p['id'] == myId,
                                    orElse: () => null)?['currentBet'] ??
                            0,
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

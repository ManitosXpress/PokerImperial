import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added import
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
  bool _isJoining = false; // To track join status
  Timer? _retryJoinTimer;

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
      setState(() => _isJoining = true);
      
      socketService.connect().then((_) async {
        if (mounted) {
          // Listeners MUST be registered after connection is established
          _setupSocketListeners(socketService);
          
          if (user != null) {
            _attemptJoinOrCreate(user);
          }
        }
      }).catchError((e) {
        print('Error connecting to socket: $e');
        if (mounted) {
          setState(() => _isJoining = false);
           if (!widget.isSpectatorMode) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error de conexión: ${e.toString()}'),
                  backgroundColor: Colors.orange,
                ),
              );
           }
        }
      });
    } else {
      print('User is spectator (role: $userRole), skipping socket join');
    }
  }

  void _setupSocketListeners(SocketService socketService) {
    // Listeners
    socketService.socket.on('player_joined', (data) {
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_created', (data) {
      print('🔵 room_created received: $data');
      print('🔵 hostId: ${data['hostId']}, isPublic: ${data['isPublic']}');
      if (mounted) setState(() => roomState = data);
    });

    socketService.socket.on('room_joined', (data) {
      print('🟢 room_joined received: $data');
      print('🟢 hostId: ${data['hostId']}, isPublic: ${data['isPublic']}');
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
      print('🃏 Players: ${data['players']?.length}');
      print('🃏 Community Cards: ${data['communityCards']}');
      print('🃏 Current Turn: ${data['currentTurn']}');
      print('🃏 Round: ${data['round']}');
      print('🃏 Full data: $data');
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
            
            // If room not found
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
                           // Retry join after delay if create failed (maybe race condition)
                           _scheduleRetry(user);
                        }
                    );
                } else {
                    // Not host, wait for host to create it
                    print('Room not found, waiting for Host to create...');
                    _scheduleRetry(user);
                }
                return;
            } else if (errorMsg.contains('Room already exists')) {
                 // Should join then
                 _scheduleRetry(user);
            } else {
                 // Other errors
                 if (mounted && !widget.isSpectatorMode) {
                    // Check for insufficient balance
                    if (errorMsg.contains('Insufficient balance') || errorMsg.contains('Crédito insuficiente')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $errorMsg'), backgroundColor: Colors.red),
                        );
                        setState(() => _isJoining = false);
                        return; // Do not retry
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
      } catch (e) {
        // Socket service might be disposed already
      }
    }

    super.dispose();
  }

  void _updateState(dynamic data) {
    if (data == null) return; // Guard clause
    setState(() => gameState = data);
    _checkTurnTimer();
  }

  void _checkTurnTimer() {
    // ... existing timer code ...
    // Guard against nulls
    if (gameState == null) {
      _stopTurnTimer();
      return;
    }
    
    try {
      final socketService = Provider.of<SocketService>(context, listen: false);
      final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;

      if (widget.isSpectatorMode) {
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
    // Guard checks
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
      socketService.socket.emit('game_action',
          {'roomId': widget.roomId, 'action': action, 'amount': amount});
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
    // Emit start_game via socket ONLY (no Firestore for multiplayer)
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.socket.emit('start_game', {'roomId': widget.roomId});
    print('🎮 Emitted start_game event for room ${widget.roomId}');
  }

  // ... (Removed _showStartConfirmationDialog and auto-confirm logic as user requested automatic server-side start) ...

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
              ? Builder(
                  builder: (context) {
                    // Calculate isHost from socket roomState ONLY (no Firestore for multiplayer)
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
                      print('🎯 Socket: isHost=$isHost, isPublic=$isPublic, hostId=$socketHostId, myUid=${user?.uid}');
                    }
                    
                    return WaitingRoomView(
                      roomId: widget.roomId,
                      roomState: currentRoomState,
                      onStartGame: _startGame,
                      userRole: userRole,
                      isHost: isHost,
                      isPublic: isPublic,
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

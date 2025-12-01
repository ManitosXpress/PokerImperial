  import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../services/socket_service.dart';
import '../providers/language_provider.dart';
import '../providers/wallet_provider.dart';
import '../widgets/poker_card.dart';
import '../widgets/player_seat.dart';
import '../utils/responsive_utils.dart';
import '../widgets/chip_stack.dart';
import '../widgets/game_wallet_dialog.dart';
import '../game_controllers/practice_game_controller.dart'; // Import local controller

class GameScreen extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic>? initialGameState;
  final bool isPracticeMode; // Add flag
  
  const GameScreen({
    super.key, 
    required this.roomId,
    this.initialGameState,
    this.isPracticeMode = false, // Default to false
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? gameState;
  Map<String, dynamic>? roomState;
  List<dynamic> players = [];
  bool _isActionMenuExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Practice Mode Controller
  PracticeGameController? _practiceController;
  final String _localPlayerId = 'local-player';
  
  // Victory screen state
  bool _showVictoryScreen = false;
  Map<String, dynamic>? _winnerData;

  @override
  void initState() {
    super.initState();
    
    // Initialize with passed state if available
    if (widget.initialGameState != null) {
      gameState = widget.initialGameState;
    }
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    if (widget.isPracticeMode) {
      _initPracticeMode();
    } else {
      _initOnlineMode();
    }
  }

  void _initPracticeMode() {
    // Initialize local controller
    _practiceController = PracticeGameController(
      humanPlayerId: _localPlayerId,
      humanPlayerName: 'You', // Could get from AuthProvider
      onStateChange: (newState) {
        if (mounted) {
          setState(() {
            gameState = newState;
            
            // Check for winners to show victory screen
            if (newState['status'] == 'finished' && newState['winners'] != null) {
              _showVictoryScreen = true;
              _winnerData = newState['winners'];
              
              Future.delayed(const Duration(milliseconds: 4500), () {
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
      },
    );
  }

  void _initOnlineMode() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    // Listen for room updates (player joins/leaves)
    socketService.socket.on('player_joined', (data) {
      if (mounted) setState(() => roomState = data);
    });
    
    socketService.socket.on('room_created', (data) {
      if (mounted) setState(() => roomState = data);
    });
    
    socketService.socket.on('room_joined', (data) {
      if (mounted) setState(() => roomState = data);
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
        
        Future.delayed(const Duration(milliseconds: 4500), () {
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
    _animationController.dispose();
    _practiceController?.dispose();
    
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

  void _toggleActionMenu() {
    setState(() {
      _isActionMenuExpanded = !_isActionMenuExpanded;
      if (_isActionMenuExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _updateState(dynamic data) {
    setState(() => gameState = data);
  }

  void _sendAction(String action, [int amount = 0]) {
    if (widget.isPracticeMode) {
      _practiceController?.handleAction(_localPlayerId, action, amount);
    } else {
      final socketService = Provider.of<SocketService>(context, listen: false);
      socketService.socket.emit('game_action', {
        'roomId': widget.roomId,
        'action': action,
        'amount': amount
      });
    }
    _toggleActionMenu(); // Close menu after action
  }

  void _showCustomBetDialog() {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;
    final myPlayer = (gameState?['players'] as List?)?.firstWhere(
      (p) => p['id'] == myId,
      orElse: () => null,
    );
    
    if (myPlayer == null) return;
    
    final int myChips = myPlayer['chips'] ?? 0;
    final int currentBet = gameState?['currentBet'] ?? 0;
    final int myCurrentBet = myPlayer['currentBet'] ?? 0;
    final int minBet = gameState?['minBet'] ?? (currentBet + 20);
    final int maxBet = myCurrentBet + myChips;
    
    double sliderValue = minBet.toDouble();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(languageProvider.getText('custom_bet')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${languageProvider.getText('enter_amount')}: ${sliderValue.toInt()}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    value: sliderValue,
                    min: minBet.toDouble(),
                    max: maxBet.toDouble(),
                    divisions: ((maxBet - minBet) / 10).ceil(),
                    label: sliderValue.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        sliderValue = value;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${languageProvider.getText('min')}: $minBet'),
                      Text('${languageProvider.getText('max')}: $maxBet'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Preset buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      if (minBet <= maxBet)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              sliderValue = minBet.toDouble();
                            });
                          },
                          child: Text('${languageProvider.getText('min')}'),
                        ),
                      if ((currentBet * 2) <= maxBet)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              sliderValue = (currentBet * 2).toDouble();
                            });
                          },
                          child: const Text('2x'),
                        ),
                      if ((currentBet * 3) <= maxBet)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              sliderValue = (currentBet * 3).toDouble();
                            });
                          },
                          child: const Text('3x'),
                        ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            sliderValue = maxBet.toDouble();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                        ),
                        child: Text(languageProvider.getText('all_in')),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _sendAction('bet', sliderValue.toInt());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: Text(languageProvider.getText('raise')),
                ),
              ],
            );
          },
        );
      },
    );
    _toggleActionMenu(); // Close action menu
  }

  void _startGame() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.socket.emit('start_game', {'roomId': widget.roomId});
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;

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
              icon: const Icon(Icons.account_balance_wallet, color: Color(0xFFffd700)),
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
                languageProvider.currentLocale.languageCode == 'en' ? '🇺🇸' : '🇪🇸',
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
              ? Center(
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
                            'Sala: ${widget.roomId}',
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
                        onPressed: _startGame,
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
            )

          : Stack(
              children: [
                // Table
                Positioned(
                  // Move table up: Center at 40% of screen height instead of 50%
                  top: ResponsiveUtils.screenHeight(context) * 0.4 - (ResponsiveUtils.screenHeight(context) * 0.55 / 2),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        // Constrain table aspect ratio (e.g., max 2.2:1)
                        double screenW = ResponsiveUtils.screenWidth(context);
                        double screenH = ResponsiveUtils.screenHeight(context);
                        
                        double tableWidth = screenW * 0.9;
                        double tableHeight = screenH * 0.55;
                        
                        // If table is too wide relative to height, constrain width
                        if (tableWidth / tableHeight > 2.0) {
                          tableWidth = tableHeight * 2.0;
                        }
                        
                        return Container(
                          width: tableWidth,
                          height: tableHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(150),
                            border: Border.all(color: const Color(0xFF3E2723), width: 25), // Dark Wood Rail
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFFFFF8E1), // Light center (Spotlight)
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
                                  margin: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(130),
                                    border: Border.all(color: const Color(0xFF1C1C1C), width: 2), // Black Inner Line
                                  ),
                                ),
                              ),
                              // Table Logo (Background)
                              Center(
                                child: Opacity(
                                  opacity: 0.25, // Reduced opacity for "printed on felt" look
                                  child: Image.asset(
                                    'assets/images/table.png',
                                    width: tableWidth * 0.4, // Adjust size relative to table
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'POT: ${gameState!['pot']}',
                                      style: TextStyle(
                                        color: const Color(0xFF1C1C1C), // Black Text
                                        fontWeight: FontWeight.bold,
                                        fontSize: ResponsiveUtils.fontSize(context, 18),
                                        shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                                      ),
                                    ),
                                    SizedBox(height: ResponsiveUtils.scaleHeight(context, 15)),
                                    if (gameState!['communityCards'] != null && (gameState!['communityCards'] as List).isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: (gameState!['communityCards'] as List).map<Widget>((card) {
                                          return Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: PokerCard(
                                              cardCode: card.toString(), 
                                              // Use unified scale for consistency
                                              width: ResponsiveUtils.scale(context, 55) 
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                  ],
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
                  ...((gameState!['players'] as List).asMap().entries.map((entry) {
                     final playersList = gameState!['players'] as List;
                     final myId = widget.isPracticeMode ? _localPlayerId : socketService.socketId;
                     final myIndex = playersList.indexWhere((p) => p['id'] == myId);
                     final int offset = myIndex != -1 ? myIndex : 0;
                     
                     int index = entry.key;
                     Map<String, dynamic> player = entry.value;
                     int totalPlayers = playersList.length;
                     int visualIndex = (index - offset + totalPlayers) % totalPlayers;
                     
                     // Re-calculate table dimensions for player positioning
                     double screenW = ResponsiveUtils.screenWidth(context);
                     double screenH = ResponsiveUtils.screenHeight(context);
                     double tableH = screenH * 0.55;
                     double tableW = screenW * 0.9;
                     if (tableW / tableH > 2.0) {
                       tableW = tableH * 2.0;
                     }
                     
                     final double centerX = screenW / 2;
                     final double centerY = screenH * 0.4; // Match table center (moved up)
                     
                     double angleStep = 2 * math.pi / totalPlayers;
                     double startAngle = math.pi / 2;
                     double angle = startAngle + (visualIndex * angleStep);
                     
                     // Radius for player seats - relative to actual table size
                     final rX = tableW / 2 + ResponsiveUtils.scale(context, 45);
                     // Reduced vertical radius to pull top player down (closer to table)
                     final rY = tableH / 2 + ResponsiveUtils.scale(context, 25);
                     
                     final x = centerX + (rX * math.cos(angle)) - 40; 
                     final y = centerY + (rY * math.sin(angle)) - 45;

                     bool isActive = player['id'] == gameState!['currentTurn'];
                     bool isFolded = player['isFolded'] ?? false;
                     bool isMe = player['id'] == myId;
                     bool isDealer = player['id'] == gameState!['dealerId'];
                     
                     
                     // Show cards
                     List<String>? cards;
                     final bool isShowdown = (gameState!['status'] == 'finished' || gameState!['stage'] == 'showdown');
                     
                     if (isMe && !isFolded) {
                        // Always show my cards if not folded
                        cards = (player['hand'] as List?)?.cast<String>();
                     } else if (!isFolded && isShowdown) {
                        // At showdown, show all active cards
                        cards = (player['hand'] as List?)?.cast<String>();
                     }
                     
                     
                     // Get hand rank if available (at showdown)
                     String? handRank;
                     bool isWinner = false;
                     if (isShowdown && !isFolded) {
                       handRank = player['handRank'] as String?;
                       
                       // Check if this player is a winner
                       final winners = gameState?['winners'];
                       if (winners != null && winners['winners'] != null) {
                         final winnersList = winners['winners'] as List;
                         isWinner = winnersList.any((w) => w['playerId'] == player['id']);
                       }
                     }

                     // Calculate bet position
                     final betX = centerX + ((rX - 90) * math.cos(angle)) - 10;
                     final betY = centerY + ((rY - 90) * math.sin(angle)) - 20;

                     // Adjust "Me" player position to avoid cutoff
                     double finalY = y;
                     if (isMe) {
                       // Position fixed at bottom, moved up significantly to ensure visibility
                       // CardHeight (~100) + AvatarHeight (~80) + Padding
                       finalY = ResponsiveUtils.screenHeight(context) - ResponsiveUtils.scaleHeight(context, 280); 
                     }

                     return Stack(
                       children: [
                         Positioned(
                           left: isMe ? (ResponsiveUtils.screenWidth(context) / 2) - 40 : x,
                           top: finalY,
                           child: PlayerSeat(
                             name: player['name'], 
                             chips: player['chips'].toString(),
                             isActive: isActive,
                             isMe: isMe,
                             isDealer: isDealer,
                             isFolded: isFolded,
                             cards: cards,
                             handRank: handRank, // Pass hand rank
                             isWinner: isWinner, // Pass winner flag

                           ),
                         ),
                         // Bet Chips
                         if (player['currentBet'] > 0)
                           Positioned(
                             left: betX,
                             top: betY,
                             child: Column(
                               children: [
                                 ChipStack(amount: player['currentBet']),
                                 const SizedBox(height: 2),
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                   decoration: BoxDecoration(
                                     color: Colors.black54,
                                     borderRadius: BorderRadius.circular(4),
                                   ),
                                   child: Text(
                                     '${player['currentBet']}',
                                     style: const TextStyle(color: Colors.white, fontSize: 10),
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
                  child: Consumer<WalletProvider>( // Use Consumer for updates
                    builder: (context, walletProvider, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/coin.png', width: 20, height: 20),
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

                // Expandable Action Menu (Bottom Left)
                if (isTurn) ...[
                  // Custom Bet button (3rd button)
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Positioned(
                        bottom: 30 + (70 * _animation.value * 3), // Bet button
                        left: 30,
                        child: Opacity(
                          opacity: _animation.value,
                          child: ScaleTransition(
                            scale: _animation,
                            child: FloatingActionButton.extended(
                              onPressed: _showCustomBetDialog,
                              backgroundColor: Colors.green,
                              icon: const Icon(Icons.add_circle),
                              label: Text(
                                languageProvider.getText('raise'),
                                style: const TextStyle(fontWeight: FontWeight.bold)
                              ),
                              heroTag: 'bet',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Call/Check button (2nd button)
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      // Determine if we should check or call based on current bet
                      final int currentBet = gameState?['currentBet'] ?? 0;
                      final myId = widget.isPracticeMode ? _localPlayerId : Provider.of<SocketService>(context, listen: false).socketId;
                      final myPlayer = (gameState?['players'] as List?)?.firstWhere(
                        (p) => p['id'] == myId,
                        orElse: () => null,
                      );
                      final int myCurrentBet = myPlayer?['currentBet'] ?? 0;
                      final bool needToCall = currentBet > myCurrentBet;
                      
                      return Positioned(
                        bottom: 30 + (70 * _animation.value * 2), // Check/Call button
                        left: 30,
                        child: Opacity(
                          opacity: _animation.value,
                          child: ScaleTransition(
                            scale: _animation,
                            child: FloatingActionButton.extended(
                              onPressed: () => _sendAction(needToCall ? 'call' : 'check'),
                              backgroundColor: Colors.blue,
                              icon: Icon(needToCall ? Icons.call_made : Icons.check_circle_outline),
                              label: Text(
                                needToCall ? '${languageProvider.getText('call')} ${currentBet - myCurrentBet}' : languageProvider.getText('check'),
                                style: const TextStyle(fontWeight: FontWeight.bold)
                              ),
                              heroTag: 'call_check',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Fold button (1st button)
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Positioned(
                        bottom: 30 + (70 * _animation.value * 1), // Fold button
                        left: 30,
                        child: Opacity(
                          opacity: _animation.value,
                          child: ScaleTransition(
                            scale: _animation,
                            child: FloatingActionButton.extended(
                              onPressed: () => _sendAction('fold'),
                              backgroundColor: Colors.red,
                              icon: const Icon(Icons.close),
                              label: Text(languageProvider.getText('fold'), style: const TextStyle(fontWeight: FontWeight.bold)),
                              heroTag: 'fold',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Main toggle button
                  Positioned(
                    bottom: 30,
                    left: 30,
                    child: FloatingActionButton(
                      onPressed: _toggleActionMenu,
                      backgroundColor: _isActionMenuExpanded ? Colors.grey[700] : Colors.amber,
                      heroTag: 'menu_toggle',
                      child: AnimatedRotation(
                        turns: _isActionMenuExpanded ? 0.125 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: const Icon(Icons.casino, size: 28),
                      ),
                    ),
                  ),
                ],
                
                // Victory Screen Overlay
                if (_showVictoryScreen && _winnerData != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.85),
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 600),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            final myId = Provider.of<SocketService>(context, listen: false).socketId;
                            final bool iWon = _winnerData!['split'] == true || 
                                              _winnerData!['winner']?['id'] == myId;
                            
                            return Transform.scale(
                              scale: value,
                              child: Opacity(
                                opacity: value,
                                child: Container(
                                  padding: const EdgeInsets.all(40),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: iWon ? [
                                        Colors.amber.shade700,
                                        Colors.amber.shade400,
                                        Colors.yellow.shade300,
                                      ] : [
                                        Colors.red.shade900,
                                        Colors.red.shade700,
                                        Colors.orange.shade800,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (iWon ? Colors.amber : Colors.red).withOpacity(0.6),
                                        blurRadius: 40,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Icon
                                      Icon(
                                        iWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                                        size: 80,
                                        color: iWon ? Colors.brown.shade800 : Colors.white,
                                      ),
                                      const SizedBox(height: 20),
                                      
                                      // Winner/Loser Text
                                      Text(
                                        iWon 
                                          ? (_winnerData!['split'] == true ? languageProvider.getText('tie') : languageProvider.getText('winner'))
                                          : languageProvider.getText('loser'),
                                        style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                          color: iWon ? Colors.brown.shade900 : Colors.white,
                                          shadows: [
                                            Shadow(
                                              color: iWon ? Colors.yellow.shade100 : Colors.black,
                                              blurRadius: 10,
                                              offset: const Offset(2, 2),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      
                                      const SizedBox(height: 10),
                                      
                                      // Winner name if not me
                                      if (!iWon && _winnerData!['winner'] != null)
                                        Text(
                                          '${_winnerData!['winner']['name']} ${languageProvider.getText('wins')}',
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.white.withOpacity(0.9),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      
                                      // Hand description (poker hand type)
                                      if (_winnerData!['winner']?['handDescription'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: iWon 
                                                ? Colors.brown.shade900.withOpacity(0.5)
                                                : Colors.black.withOpacity(0.5),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: iWon ? Colors.amber : Colors.white38,
                                                width: 2,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.emoji_events_outlined,
                                                  color: iWon ? Colors.amber : Colors.white70,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  languageProvider.translateHand(_winnerData!['winner']['handDescription']),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: iWon ? Colors.amber : Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      
                                      const SizedBox(height: 20),
                                      
                                      // Amount Won/Lost
                                      if (_winnerData!['winner']?['amount'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: iWon ? Colors.brown.shade800 : Colors.black.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  color: iWon ? Colors.amber : Colors.grey,
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  'C',
                                                  style: TextStyle(
                                                    color: iWon ? Colors.black : Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${iWon ? "+" : "-"}${_winnerData!['winner']['amount']}',
                                                style: TextStyle(
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.bold,
                                                  color: iWon ? Colors.amber : Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      
                                      const SizedBox(height: 30),
                                      
                                      // Show all players' cards
                                      if (_winnerData!['players'] != null)
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                languageProvider.getText('player_cards'),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              ...(_winnerData!['players'] as List).map((player) {
                                                final isMe = player['id'] == myId;
                                                final isFolded = player['isFolded'] == true;
                                                
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 12),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      SizedBox(
                                                        width: 100,
                                                        child: Text(
                                                          player['name'],
                                                          style: TextStyle(
                                                            color: isMe ? Colors.amber : Colors.white,
                                                            fontSize: 14,
                                                            fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                                          ),
                                                          textAlign: TextAlign.right,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      if (isFolded)
                                                        Text(
                                                          '(${languageProvider.getText('fold')})',
                                                          style: const TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 14,
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        )
                                                      else if (player['hand'] != null)
                                                        Row(
                                                          children: (player['hand'] as List).map<Widget>((card) {
                                                            return Padding(
                                                              padding: const EdgeInsets.only(right: 4),
                                                              child: PokerCard(cardCode: card, width: 35),
                                                            );
                                                          }).toList(),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        ),
                                      
                                      const SizedBox(height: 20),
                                      
                                      // Next hand info
                                      Text(
                                        languageProvider.getText('next_hand'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: iWon ? Colors.brown.shade700 : Colors.white.withOpacity(0.8),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 20),
                                      
                                      // Buttons
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                            icon: const Icon(Icons.exit_to_app),
                                            label: Text(languageProvider.getText('exit')),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.brown.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _showVictoryScreen = false;
                                              });
                                            },
                                            icon: const Icon(Icons.check_circle),
                                            label: Text(languageProvider.getText('continue')),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ),
      ),
      floatingActionButton: (widget.isPracticeMode && gameState?['status'] == 'finished')
          ? FloatingActionButton.extended(
              onPressed: () {
                _practiceController?.startNextHand();
              },
              backgroundColor: const Color(0xFFFFD700),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: Text(
                languageProvider.getText('continue') ?? 'Continuar',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

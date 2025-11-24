import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../services/socket_service.dart';
import '../widgets/poker_card.dart';
import '../widgets/player_seat.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? gameState;
  Map<String, dynamic>? roomState;  // Track room info before game starts
  List<dynamic> players = [];
  bool _isActionMenuExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Victory screen state
  bool _showVictoryScreen = false;
  Map<String, dynamic>? _winnerData;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    // Listen for room updates (player joins/leaves)
    socketService.socket.on('player_joined', (data) {
      setState(() {
        roomState = data;
      });
    });
    
    socketService.socket.on('room_created', (data) {
      setState(() {
        roomState = data;
      });
    });
    
    socketService.socket.on('room_joined', (data) {
      setState(() {
        roomState = data;
      });
    });
    
    socketService.socket.on('game_started', (data) {
      _updateState(data);
    });
    
    socketService.socket.on('game_update', (data) {
      _updateState(data);
    });
    
    socketService.socket.on('hand_winner', (data) {
      setState(() {
        _showVictoryScreen = true;
        _winnerData = data;
      });
      
      // Auto-hide victory screen after 4.5 seconds (before auto-restart)
      Future.delayed(const Duration(milliseconds: 4500), () {
        if (mounted) {
          setState(() {
            _showVictoryScreen = false;
            _winnerData = null;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
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
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.socket.emit('game_action', {
      'roomId': widget.roomId,
      'action': action,
      'amount': amount
    });
    _toggleActionMenu(); // Close menu after action
  }

  void _startGame() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.socket.emit('start_game', {'roomId': widget.roomId});
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    
    bool isTurn = false;
    if (gameState != null && gameState!['currentTurn'] != null) {
      isTurn = gameState!['currentTurn'] == socketService.socketId;
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text('Room: ${widget.roomId}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: gameState == null
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
                              '${(roomState!['players'] as List).length} / 4 Jugadores',
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
                            const Text(
                              'Jugadores Conectados:',
                              style: TextStyle(
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
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE94560),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          player['name'][0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      player['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  ],
                                ),
                              );
                            }).toList(),
                            
                            // Empty slots
                            if (roomState!['players'] != null)
                              ...List.generate(
                                4 - (roomState!['players'] as List).length,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.person_outline, color: Colors.white38),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Esperando jugador...',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 32),
                    
                    // Start button
                    if (roomState != null && (roomState!['players'] as List).length >= 2)
                      ElevatedButton.icon(
                        onPressed: _startGame,
                        icon: const Icon(Icons.play_arrow, size: 28),
                        label: const Text('INICIAR JUEGO'),
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
                              'Se necesitan al menos 2 jugadores',
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
                  top: MediaQuery.of(context).size.height * 0.4 - (MediaQuery.of(context).size.height * 0.5 / 2),
                  left: MediaQuery.of(context).size.width / 2 - (MediaQuery.of(context).size.width * 0.8 / 2),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.height * 0.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF35654D),
                      borderRadius: BorderRadius.circular(150),
                      border: Border.all(color: const Color(0xFF4E342E), width: 15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'POT: ${gameState!['pot']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: (gameState!['communityCards'] as List).map<Widget>((card) {
                                  return Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: PokerCard(cardCode: card, width: 40),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Players
                if (gameState!['players'] != null)
                  ...((gameState!['players'] as List).asMap().entries.map((entry) {
                     final playersList = gameState!['players'] as List;
                     final myId = socketService.socketId;
                     final myIndex = playersList.indexWhere((p) => p['id'] == myId);
                     final int offset = myIndex != -1 ? myIndex : 0;
                     
                     int index = entry.key;
                     Map<String, dynamic> player = entry.value;
                     int totalPlayers = playersList.length;
                     int visualIndex = (index - offset + totalPlayers) % totalPlayers;
                     
                     final double w = MediaQuery.of(context).size.width * 0.8;
                     final double h = MediaQuery.of(context).size.height * 0.5;
                     final double centerX = MediaQuery.of(context).size.width / 2;
                     final double centerY = MediaQuery.of(context).size.height * 0.4;
                     
                     double angleStep = 2 * math.pi / totalPlayers;
                     double startAngle = math.pi / 2;
                     double angle = startAngle + (visualIndex * angleStep);
                     
                     final rX = w / 2 + 35;
                     final rY = h / 2 + 35;
                     final x = centerX + (rX * math.cos(angle)) - 30; 
                     final y = centerY + (rY * math.sin(angle)) - 30;

                     bool isActive = player['id'] == gameState!['currentTurn'];
                     bool isFolded = player['isFolded'] ?? false;
                     bool isMe = player['id'] == myId;
                     bool isDealer = player['id'] == gameState!['dealerId'];
                     
                     List<String>? cards;
                     if (isMe && !isFolded) {
                        cards = (player['hand'] as List?)?.cast<String>();
                     }

                     return Positioned(
                       left: x,
                       top: y,
                       child: PlayerSeat(
                         name: player['name'], 
                         chips: player['chips'].toString(),
                         isActive: isActive,
                         isMe: isMe,
                         isDealer: isDealer,
                         isFolded: isFolded,
                         cards: cards,
                       ),
                     );
                  }).toList()),

                // Expandable Action Menu (Bottom Left)
                if (isTurn) ...[
                  // Action buttons that expand
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      // Determine bet amount (current bet + reasonable raise)
                      final int currentBet = gameState?['currentBet'] ?? 0;
                      final int raiseAmount = currentBet + 50;
                      
                      return Positioned(
                        bottom: 30 + (70 * _animation.value * 3), // Bet button
                        left: 30,
                        child: Opacity(
                          opacity: _animation.value,
                          child: ScaleTransition(
                            scale: _animation,
                            child: FloatingActionButton.extended(
                              onPressed: () => _sendAction('bet', raiseAmount),
                              backgroundColor: Colors.green,
                              icon: const Icon(Icons.add_circle),
                              label: Text('Bet $raiseAmount', style: const TextStyle(fontWeight: FontWeight.bold)),
                              heroTag: 'bet',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      // Determine if we should check or call based on current bet
                      final int currentBet = gameState?['currentBet'] ?? 0;
                      final myId = Provider.of<SocketService>(context, listen: false).socketId;
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
                              icon: const Icon(Icons.check_circle),
                              label: Text(
                                needToCall ? 'Call ${currentBet - myCurrentBet}' : 'Check',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              heroTag: 'check',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Positioned(
                        bottom: 30 + (70 * _animation.value), // Fold button
                        left: 30,
                        child: Opacity(
                          opacity: _animation.value,
                          child: ScaleTransition(
                            scale: _animation,
                            child: FloatingActionButton.extended(
                              onPressed: () => _sendAction('fold'),
                              backgroundColor: Colors.red,
                              icon: const Icon(Icons.cancel),
                              label: const Text('Fold', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                          ? (_winnerData!['split'] == true ? '¡EMPATE!' : '¡GANASTE!')
                                          : '¡PERDISTE!',
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
                                          '${_winnerData!['winner']['name']} gana',
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.white.withOpacity(0.9),
                                            fontStyle: FontStyle.italic,
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
                                              const Text(
                                                'Cartas de los Jugadores:',
                                                style: TextStyle(
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
                                                        const Text(
                                                          '(Fold)',
                                                          style: TextStyle(
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
                                        'Próxima mano en breve...',
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
                                            label: const Text('Salir'),
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
                                            label: const Text('Continuar'),
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
    );
  }
}

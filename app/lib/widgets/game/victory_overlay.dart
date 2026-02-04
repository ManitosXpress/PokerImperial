import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import '../../providers/language_provider.dart';
import '../../services/socket_service.dart';
import '../../widgets/poker_card.dart';

class VictoryOverlay extends StatefulWidget {
  final Map<String, dynamic> winnerData;
  final VoidCallback? onContinue;

  const VictoryOverlay({
    super.key,
    required this.winnerData,
    this.onContinue,
  });

  @override
  State<VictoryOverlay> createState() => _VictoryOverlayState();
}

class _VictoryOverlayState extends State<VictoryOverlay> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    
    // Setup Confetti
    _confettiController = ConfettiController(duration: const Duration(seconds: 10));
    
    // Setup Entrance Animation
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    
    _animController.forward();
    
    // Auto-play confetti if applicable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPlayConfetti();
    });
    
    // Auto-close timer based on displayTime from server
    if (widget.winnerData['displayTime'] != null) {
       Future.delayed(Duration(milliseconds: widget.winnerData['displayTime']), () {
          if (mounted) {
             // Let the parent handle the unmount via state change,
             // or we can animate out here.
          }
       });
    }
  }

  void _checkAndPlayConfetti() {
    final myId = Provider.of<SocketService>(context, listen: false).socketId;
    bool iWon = _checkIfIWon(myId);
    
    if (iWon) {
      _confettiController.play();
    }
  }
  
  bool _checkIfIWon(String? myId) {
    if (widget.winnerData['split'] == true) return true;
    
    final winner = widget.winnerData['winner'];
    if (winner != null) {
      return winner['id'] == myId || winner['uid'] == myId; // Check UID too
    }
    
    final winners = widget.winnerData['winners'] as List?;
    if (winners != null) {
      return winners.any((w) => w['id'] == myId || w['uid'] == myId);
    }
    
    return false;
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final languageProvider = Provider.of<LanguageProvider>(context);
    final myId = Provider.of<SocketService>(context, listen: false).socketId;
    final iWon = _checkIfIWon(myId);
    
    // Winner Info
    final winnerName = widget.winnerData['winner']?['name'] ?? 'Winner';
    final amount = widget.winnerData['winner']?['amount'] ?? 0;
    final handDesc = widget.winnerData['winningMsg'] ?? widget.winnerData['winner']?['handDescription'] ?? '';
    
    // Winning Cards
    List<String> validCards = [];
    if (widget.winnerData['revealHands'] != null) {
       // If revealHands is present (map), try to find the winner's hand
       final winnerId = widget.winnerData['winner']?['id'];
       final handsMap = widget.winnerData['revealHands'] as Map?;
       if (winnerId != null && handsMap != null) {
          final handData = handsMap[winnerId];
          if (handData != null && handData['hand'] != null) {
             validCards = List<String>.from(handData['hand'].map((c) => c.toString()));
          }
       }
    }

    return Stack(
      children: [
        // 1. Semi-transparent dark background
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.7),
          ),
        ),
        
        // 2. Confetti (Top Center)
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: true, 
            colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
          ),
        ),

        // 3. Main Content
        Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iWon 
                      ? [const Color(0xFF1E3C72), const Color(0xFF2A5298)] // Victory Blue
                      : [const Color(0xFF232526), const Color(0xFF414345)], // Defeat Grey
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: iWon ? Colors.amber : Colors.white24,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (iWon ? Colors.blue : Colors.black).withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon & Title
                    Icon(
                      iWon ? Icons.emoji_events : Icons.sentiment_neutral,
                      size: 64,
                      color: iWon ? Colors.amber : Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      iWon 
                        ? (widget.winnerData['split'] == true ? 'SPLIT POT!' : 'VICTORY!')
                        : (widget.winnerData['split'] == true ? 'SPLIT POT' : 'DEFEAT'),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: iWon ? Colors.white : Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Winner Name & Amount
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Column(
                        children: [
                          Text(
                            winnerName,
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '+$amount Chips',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (handDesc.isNotEmpty)
                             Text(
                               handDesc,
                               style: const TextStyle(
                                 color: Colors.white60,
                                 fontSize: 14,
                                 fontStyle: FontStyle.italic,
                               ),
                             ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    
                    // Revealed Cards
                    if (validCards.isNotEmpty) ...[
                      const Text(
                        'WINNING HAND',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: validCards.map((cardCode) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: PokerCard(
                                cardCode: cardCode,
                                width: 50, // Smaller cards for overlay
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Continue Button (Only for Practice Mode or if provided)
                    if (widget.onContinue != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            languageProvider.getText('continue').toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

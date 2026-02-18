import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/socket_service.dart';
import '../../utils/responsive_utils.dart';
import '../poker_card.dart';

class VictoryOverlay extends StatefulWidget {
  final Map<String, dynamic> winnerData;
  final VoidCallback onDismiss;

  const VictoryOverlay({
    Key? key,
    required this.winnerData,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<VictoryOverlay> createState() => _VictoryOverlayState();
}

class _VictoryOverlayState extends State<VictoryOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  
  // Animation for amount counting
  int _displayedAmount = 0;
  int _targetAmount = 0;

  @override
  void initState() {
    super.initState();
    
    // Parse winner data
    _parseWinnerData();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // Start entrance animation
    _controller.forward();
    
    // Start number counting animation
    _animateCount();

    // Auto-dismiss after 4.5 seconds
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  void _parseWinnerData() {
    // Handle both single winner and multiple winners structure
    // We'll show the main winner or the first one in the list
    if (widget.winnerData['winners'] != null && (widget.winnerData['winners'] as List).isNotEmpty) {
       final mainWinner = (widget.winnerData['winners'] as List)[0];
       _targetAmount = mainWinner['amount'] ?? 0;
    } else if (widget.winnerData['winner'] != null) {
       _targetAmount = widget.winnerData['winner']['amount'] ?? 0;
    } else {
       // Fallback or legacy
       _targetAmount = widget.winnerData['amount'] ?? 0;
    }
  }

  void _animateCount() {
    // Simple linear interpolation for number counting
    final duration = const Duration(milliseconds: 1500);
    final steps = 60;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final increment = _targetAmount / steps;
    
    int currentStep = 0;
    
    Future.doWhile(() async {
      await Future.delayed(Duration(milliseconds: stepDuration));
      if (!mounted) return false;
      
      currentStep++;
      setState(() {
        if (currentStep >= steps) {
          _displayedAmount = _targetAmount;
        } else {
          _displayedAmount = (increment * currentStep).toInt();
        }
      });
      
      return currentStep < steps;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Extract Hand Name
    String handName = "VICTORIA";
    List<String> validCards = [];
    
    // Try to get hand name and cards from winners array
    if (widget.winnerData['winners'] != null && (widget.winnerData['winners'] as List).isNotEmpty) {
       final mainWinner = (widget.winnerData['winners'] as List)[0];
       handName = mainWinner['handDescription'] ?? mainWinner['handName'] ?? "VICTORIA";
       
       if (mainWinner['winningCards'] != null) {
         // ✅ FIX: Robust parsing for winning cards (Handle Objects vs Strings)
         validCards = (mainWinner['winningCards'] as List).map((e) {
            String str = e.toString();
            
            // 1. Clean code
            if (str.length <= 3 && !str.contains('{') && !str.contains('value')) {
                if (str.startsWith('10')) return str.replaceFirst('10', 't');
                return str;
            }

            // 2. Dynamic Object
            try {
                dynamic d = e;
                if (d['value'] != null && d['suit'] != null) {
                   final val = d['value']?.toString() ?? '';
                   final suit = d['suit']?.toString() ?? '';
                   return '$val$suit';
                }
            } catch (err) {}

            // 3. Regex
            if (str.contains('value') && str.contains('suit')) {
                 final valueMatch = RegExp(r'value:\s*([a-zA-Z0-9]+)').firstMatch(str);
                 final suitMatch = RegExp(r'suit:\s*([a-zA-Z0-9]+)').firstMatch(str);
                 if (valueMatch != null && suitMatch != null) {
                    final val = valueMatch.group(1) ?? '';
                    final suit = suitMatch.group(1) ?? '';
                    return '$val$suit';
                 }
            }
            return '';
         }).where((e) => e.isNotEmpty).toList();
       }
    } 
    // Fallback validation for combination
    else if (widget.winnerData['combination'] != null) {
       handName = widget.winnerData['combination'];
    }
    
    // If we only have hand description but no cards in winner object, try to get from allHands or gameState
    if (validCards.isEmpty && widget.winnerData['gameState'] != null) {
        // Logic to try to find cards if not explicitly sent in 'winningCards'
        // But assumed backend sends 'winningCards' as per plan
    }

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Backdrop Blur (Glassmorphism)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
              child: Container(
                color: Colors.black.withOpacity(0.3), // Slight dim
              ),
            ),
            
            // 2. Main Content Container
            FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: ResponsiveUtils.screenWidth(context) * 0.85,
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.black.withOpacity(0.85), 
                        const Color(0xFF1A1A1A).withOpacity(0.95),
                        Colors.amber.withOpacity(0.15)
                      ]
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withOpacity(0.8), // Gold border
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // HEADER
                      // HEADER
                      Builder(
                        builder: (context) {
                          // Determine if I am the winner
                          final socketService = Provider.of<SocketService>(context, listen: false);
                          // Try to find my ID. 
                          // NOTE: In a pure widget we might not want to depend on Provider if not passed, 
                          // but here we need context. 
                          // Ideally pass 'isMe' or 'myId' as prop.
                          // Fallback: Check if we can find user ID from Auth
                          final myId = FirebaseAuth.instance.currentUser?.uid ?? socketService.socketId;
                          
                          bool isMeWinner = false;
                          String winnerName = "JUGADOR";

                          if (widget.winnerData['winners'] != null && (widget.winnerData['winners'] as List).isNotEmpty) {
                             final mainWinner = (widget.winnerData['winners'] as List)[0];
                             // Check ID or UID
                             if (mainWinner['id'] == myId || mainWinner['uid'] == myId) {
                               isMeWinner = true;
                             }
                             winnerName = mainWinner['name'] ?? "JUGADOR";
                          } else if (widget.winnerData['winner'] != null) {
                             final w = widget.winnerData['winner'];
                             if (w['id'] == myId || w['uid'] == myId) isMeWinner = true;
                             winnerName = w['name'] ?? "JUGADOR";
                          }

                          // Custom Text & Color
                          String titleText = isMeWinner ? "¡HAS GANADO!" : "¡$winnerName GANA!";
                          List<Color> gradientColors = isMeWinner 
                              ? [const Color(0xFFD4AF37), const Color(0xFFFFF8DC), const Color(0xFFD4AF37)] // Gold
                              : [const Color(0xFFB0BEC5), const Color(0xFFECEFF1), const Color(0xFFB0BEC5)]; // Silver/Grey for others
                          
                          if (!isMeWinner) {
                            // Maybe Red for loss? Or just neutral?
                            // User said: "a los que perdieron que salga que perdieron"
                            // "You Lost" might be too harsh? "Winner: X" is standard.
                            // But user specifically asked for "que salga que perdieron".
                            // Let's change title to "HAS PERDIDO" if not winner?
                            // Or standard "X GANA" + "Has perdido" subtitle?
                            // Start with "X GANA" as main title, looks professional.
                            // Let's add a subtitle "Mala suerte esta vez" or similar?
                            // Or just change title if user insisted.
                            // "HAS PERDIDO" is huge. 
                            // Let's stick to "X GANA" for now as it describes the event "Winner Announcement".
                            // Wait, user said: "el mensaje de ganador le sale a todos ... solo al ganador le tiene q aprecer, a los que perdieron que salga que perdieron"
                            // Means: Winner sees "WINNER", Losers see "YOU LOST".
                            // Okay, let's do:
                            titleText = isMeWinner ? "¡HAS GANADO!" : "¡HAS PERDIDO!";
                            if (!isMeWinner) {
                               gradientColors = [const Color(0xFFEF5350), const Color(0xFFFFCDD2), const Color(0xFFEF5350)]; // Red
                            }
                          }

                          return Column(
                            children: [
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: gradientColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: Text(
                                    titleText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: Colors.white,
                                      fontFamily: 'Cinzel',
                                    ),
                                  ),
                                ),
                                if (!isMeWinner)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      "Ganador: $winnerName",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  )
                            ]
                          );
                        }
                      ),
                      
                      const SizedBox(height: 10),
                      Divider(color: const Color(0xFFD4AF37).withOpacity(0.5), thickness: 1, indent: 40, endIndent: 40),
                      const SizedBox(height: 15),

                      // HAND NAME
                      Text(
                        handName.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      
                      const SizedBox(height: 25),

                      // CARDS ROW
                      if (validCards.isNotEmpty)
                        SizedBox(
                          height: 80, // Height for scaled cards
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: validCards.map((cardCode) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Transform.scale(
                                  scale: 0.9,
                                  child: PokerCard(
                                    cardCode: cardCode,
                                    width: 60,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      const SizedBox(height: 25),

                      // AMOUNT
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars, color: Color(0xFFD4AF37), size: 28),
                            const SizedBox(width: 10),
                            Text(
                              "\$ $_displayedAmount",
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Color(0xAA000000),
                                    offset: Offset(2, 2),
                                    blurRadius: 4,
                                  )
                                ]
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

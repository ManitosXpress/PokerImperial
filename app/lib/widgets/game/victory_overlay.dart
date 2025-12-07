import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/socket_service.dart';

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
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;
  bool _showMessage = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
    ]).animate(_controller);

    _controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _showMessage = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final myId = Provider.of<SocketService>(context, listen: false).socketId;
    final bool iWon = widget.winnerData['split'] == true || 
                      widget.winnerData['winner']?['id'] == myId;

    return Stack(
      children: [
        // Transient Result Message (Centered)
        if (_showMessage)
          Positioned.fill(
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _opacityAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: iWon ? Colors.amber : Colors.red,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (iWon ? Colors.amber : Colors.red).withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              iWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                              size: 60,
                              color: iWon ? Colors.amber : Colors.redAccent,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              iWon 
                                ? (widget.winnerData['split'] == true ? languageProvider.getText('tie') : languageProvider.getText('winner'))
                                : languageProvider.getText('loser'),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: iWon ? Colors.amber : Colors.red,
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
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

        // Persistent Winner Info (Top Center)
        Positioned(
          top: 100, // Below the pot/community cards usually
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.winnerData['winner']?['name'] ?? 'Unknown'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.winnerData['winner']?['handDescription'] != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• ${languageProvider.translateHand(widget.winnerData['winner']['handDescription'])}',
                      style: TextStyle(color: Colors.amber.shade200),
                    ),
                  ],
                  if (widget.winnerData['winner']?['amount'] != null) ...[
                     const SizedBox(width: 8),
                     Text(
                       '+${widget.winnerData['winner']['amount']}',
                       style: const TextStyle(
                         color: Colors.greenAccent,
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Continue Button (Bottom Right)
        if (widget.onContinue != null)
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: widget.onContinue,
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                languageProvider.getText('continue'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

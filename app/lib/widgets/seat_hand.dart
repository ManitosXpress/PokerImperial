import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'poker_card.dart';
import 'card_back.dart';

class SeatHand extends StatefulWidget {
  final List<dynamic>? visibleCards; // Changed to dynamic to handle nulls
  final int cardCount;
  final bool isFolded;
  final double cardWidth;
  final bool isWinner;
  final bool isMe; // <-- NEW: Flag to indicate player's own hand
  final List<String>? winningCards; // <-- NEW: Specific cards to highlight

  const SeatHand({
    super.key,
    this.visibleCards,
    this.cardCount = 2,
    this.isFolded = false,
    required this.cardWidth,
    this.isWinner = false,
    this.isMe = false, // <-- NEW
    this.winningCards, // <-- NEW
  });

  @override
  State<SeatHand> createState() => _SeatHandState();
}

class _SeatHandState extends State<SeatHand> with TickerProviderStateMixin {
  late List<AnimationController> _flipControllers;
  late List<Animation<double>> _flipAnimations;
  bool _initialized = false;
  // ... (controllers init remains same)

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }
  
  void _initializeControllers() {
    _flipControllers = List.generate(
      widget.cardCount,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );

    _flipAnimations = _flipControllers.map((controller) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // If cards are already visible on init OR if this is the player's own hand, show immediately
    if (widget.isMe || (widget.visibleCards != null && widget.visibleCards!.isNotEmpty)) {
      for (var controller in _flipControllers) {
        controller.value = 1.0;
      }
    }
    
    _initialized = true;
  }

  @override
  void didUpdateWidget(SeatHand oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if we transitioned from hidden to visible (Reveal Event)
    // But ONLY animate if this is NOT the player's own hand
    if (!widget.isMe && oldWidget.visibleCards == null && widget.visibleCards != null) {
      _triggerSequentialReveal();
    } else if (widget.isMe && oldWidget.visibleCards == null && widget.visibleCards != null) {
      // For player's own hand, show immediately without animation
      for (var controller in _flipControllers) {
        controller.value = 1.0;
      }
    }
    
    // Handle case where card count changes
    if (oldWidget.cardCount != widget.cardCount) {
      _disposeControllers();
      _initializeControllers();
    }
  }

  void _triggerSequentialReveal() async {
    for (var controller in _flipControllers) {
      controller.value = 0.0;
    }
    for (int i = 0; i < _flipControllers.length; i++) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _flipControllers[i].forward();
    }
  }

  void _disposeControllers() {
    for (var controller in _flipControllers) {
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFolded && widget.visibleCards == null) {
      return const SizedBox.shrink(); 
    }

    final double cardHeight = widget.cardWidth * 1.4;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: widget.isWinner ? const EdgeInsets.all(4) : EdgeInsets.zero,
      decoration: widget.isWinner
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD700), width: 2), // Reduced width slightly
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      height: cardHeight + (widget.isWinner ? 8 : 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.cardCount, (index) {
          // Determine the card code if available
          String? cardCode;
          if (widget.visibleCards != null && index < widget.visibleCards!.length) {
            // SAFE ACCESS: Check if element is null or not a string
            final dynamic card = widget.visibleCards![index];
            if (card is String) {
              cardCode = card;
            }
          }

          // Check if this specific card is part of the winning hand
          bool isWinningCard = false;
          if (cardCode != null && widget.winningCards != null) {
             isWinningCard = widget.winningCards!.contains(cardCode);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: AnimatedBuilder(
              animation: _flipAnimations[index],
              builder: (context, child) {
                
                final double value = _flipAnimations[index].value;
                final bool isFaceUp = value >= 0.5;
                final double rotation = value * math.pi;

                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective
                    ..rotateY(rotation),
                  alignment: Alignment.center,
                  child: isFaceUp
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi), // Mirror back to normal
                          child: cardCode != null 
                              ? Container(
                                  decoration: isWinningCard 
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFFD700), width: 3), // Strong Gold Border
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFD700).withOpacity(0.8),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      )
                                    : null,
                                  child: PokerCard(cardCode: cardCode, width: widget.cardWidth)
                                )
                              : SizedBox(width: widget.cardWidth, height: cardHeight),
                        )
                      : CardBack(width: widget.cardWidth, height: cardHeight),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}

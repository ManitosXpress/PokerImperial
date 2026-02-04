import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../poker_card.dart';
import '../card_back.dart';
import '../../utils/responsive_utils.dart';

/// ANIMATED: Renders community cards with sequential flip animation
class CommunityCardsWidget extends StatefulWidget {
  final List<dynamic>? communityCards;
  final bool isMobile;

  const CommunityCardsWidget({
    super.key,
    this.communityCards,
    this.isMobile = false,
  });

  @override
  State<CommunityCardsWidget> createState() => _CommunityCardsWidgetState();
}

class _CommunityCardsWidgetState extends State<CommunityCardsWidget> with TickerProviderStateMixin {
  final List<AnimationController> _flipControllers = [];
  final List<Animation<double>> _flipAnimations = [];
  int _previousCardCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    // 🔥 FIX: Trigger animations immediately on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateAllCards();
    });
  }
  
  void _animateAllCards() async {
    for (int i = 0; i < _flipControllers.length; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted && i < _flipControllers.length) {
        _flipControllers[i].forward();
      }
    }
  }

  void _initializeControllers() {
    final cardCount = widget.communityCards?.length ?? 0;
    
    // Create controllers for each card
    for (int i = 0; i < cardCount; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      _flipControllers.add(controller);
      _flipAnimations.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        ),
      );
    }

    _previousCardCount = cardCount;
  }

  @override
  void didUpdateWidget(CommunityCardsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCount = oldWidget.communityCards?.length ?? 0;
    final newCount = widget.communityCards?.length ?? 0;

    // If new cards were added, animate them
    if (newCount > oldCount) {
      _handleNewCards(oldCount, newCount);
    } else if (newCount < oldCount) {
      // If cards were removed (new hand), reset
      _resetControllers();
    }
  }

  void _handleNewCards(int oldCount, int newCount) async {
    // Add new controllers for new cards
    for (int i = oldCount; i < newCount; i++) {
      if (i >= _flipControllers.length) {
        final controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        );
        _flipControllers.add(controller);
        _flipAnimations.add(
          Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeInOut),
          ),
        );
      }
    }

    // Animate new cards one by one
    for (int i = oldCount; i < newCount; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && i < _flipControllers.length) {
        _flipControllers[i].forward();
      }
    }
  }

  void _resetControllers() {
    for (var controller in _flipControllers) {
      controller.dispose();
    }
    _flipControllers.clear();
    _flipAnimations.clear();
    _initializeControllers();
  }

  @override
  void dispose() {
    for (var controller in _flipControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SAFETY: Handle null or empty community cards
    if (widget.communityCards == null || widget.communityCards!.isEmpty) {
      return const SizedBox.shrink();
    }

    try {
      final cardWidth = ResponsiveUtils.scale(context, widget.isMobile ? 50 : 45);
      final cardHeight = cardWidth * 1.4;

      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.communityCards!.length, (index) {
              final card = widget.communityCards![index];
              
              // SAFETY: Handle potential null cards
              if (card == null) return const SizedBox.shrink();

              // Ensure we have a controller for this card
              if (index >= _flipControllers.length) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: AnimatedBuilder(
                  animation: _flipAnimations[index],
                  builder: (context, child) {
                    final double value = _flipAnimations[index].value;
                    final bool isFaceUp = value >= 0.5;
                    final double rotation = value * math.pi;

                    return Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(rotation),
                      alignment: Alignment.center,
                      child: isFaceUp
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: PokerCard(
                                cardCode: card.toString(),
                                width: cardWidth,
                              ),
                            )
                          : CardBack(width: cardWidth, height: cardHeight),
                    );
                  },
                ),
              );
            }),
          ),
        ),
      );
    } catch (e) {
      print('⚠️ Error rendering community cards: $e');
      return const SizedBox.shrink();
    }
  }
}

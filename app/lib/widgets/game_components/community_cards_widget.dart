import 'package:flutter/material.dart';
import '../poker_card.dart';
import '../../utils/responsive_utils.dart';

/// CRASH-PROOF: Renders community cards with full null safety
/// Handles null, empty, and partial community cards scenarios
class CommunityCardsWidget extends StatelessWidget {
  final List<dynamic>? communityCards;
  final bool isMobile;

  const CommunityCardsWidget({
    super.key,
    this.communityCards,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    // SAFETY: Handle null or empty community cards
    if (communityCards == null || communityCards!.isEmpty) {
      return const SizedBox.shrink(); // Render nothing if no cards
    }

    try {
      final cardWidth = ResponsiveUtils.scale(context, isMobile ? 50 : 45);

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
            children: communityCards!.map((card) {
              // SAFETY: Handle potential null cards in the list
              if (card == null) return const SizedBox.shrink();
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: PokerCard(
                  cardCode: card.toString(),
                  width: cardWidth,
                ),
              );
            }).toList(),
          ),
        ),
      );
    } catch (e) {
      // CRASH-PROOF: If anything goes wrong, show nothing instead of crashing
      print('⚠️ Error rendering community cards: $e');
      return const SizedBox.shrink();
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'poker_card.dart';
import 'imperial_currency.dart';

import '../utils/responsive_utils.dart';

class PlayerSeat extends StatelessWidget {
  final String name;
  final int chips; // Changed from String to int
  final bool isMe;
  final bool isActive;
  final bool isDealer;
  final bool isFolded;
  final List<String>? cards;
  final String? handRank; // Add hand rank for showdown
  final bool isWinner; // Highlight winner
  final int? currentBet; // Added for bet amount bubble

  const PlayerSeat({
    super.key,
    required this.name,
    required this.chips, // Changed from String to int
    this.isMe = false,
    this.isActive = true,
    this.isDealer = false,
    this.isFolded = false,
    this.cards,
    this.handRank,
    this.isWinner = false,
    this.currentBet, // Added
  });



// ... (inside PlayerSeat class)

  @override
  Widget build(BuildContext context) {
    // Use unified scale for consistent aspect ratios
    // Larger avatar for "Me" player
    final double avatarSize = ResponsiveUtils.scale(context, isMe ? 65 : 45); 
    
    // Balanced card size for "Me" - wider as requested
    final double cardWidth = ResponsiveUtils.scale(context, isMe ? 70 : 28);
    // Ensure height matches PokerCard aspect ratio (1.4) to prevent clipping
    final double cardHeight = cardWidth * 1.4;

    final bool isMobile = MediaQuery.of(context).size.width < 600; // Determine if it's a mobile device

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cards
        if (cards != null && cards!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: isWinner ? const EdgeInsets.all(4) : EdgeInsets.zero,
            decoration: isWinner
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFD700), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  )
                : null,
            height: cardHeight + (isWinner ? 8 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: cards!.map((c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: PokerCard(cardCode: c, width: cardWidth),
              )).toList(),
            ),
          ),
        
        // Hand Rank (shown at showdown)
        if (handRank != null && handRank!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isWinner ? const Color(0xFFFFD700) : Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD700), width: isWinner ? 2 : 1),
              boxShadow: isWinner
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              handRank!,
              style: TextStyle(
                color: isWinner ? Colors.black : const Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        
        // Avatar + Info Pill
        SizedBox(
          width: avatarSize * 2.0, // More width for the pill
          height: avatarSize + 30,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // Avatar Circle
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2A2A2A),
                  border: Border.all(
                    color: isActive ? const Color(0xFFFFD700) : Colors.grey.shade800,
                    width: isActive ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: isFolded
                      ? const Icon(Icons.close, color: Colors.white54)
                      : Text(
                          name.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: avatarSize * 0.4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              // Dealer Button
              if (isDealer)
                Positioned(
                  top: 0,
                  right: (avatarSize * 1.5 - avatarSize) / 2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'D',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ),

              // Bet Amount Bubble
              if (currentBet != null && currentBet! > 0)
                Positioned(
                  top: -10, // Adjusted to prevent overlap
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                    ),
                    child: ImperialCurrency(
                      amount: currentBet!,
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      iconSize: 12,
                    ),
                  ),
                ),
              
              // Info Pill (Name + Chips)
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isMe ? const Color(0xFFFFD700) : Colors.white10,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Player Stack
                      ImperialCurrency(
                        amount: chips,
                        style: TextStyle(
                          color: isMe ? const Color(0xFFFFD700) : Colors.white,
                          fontSize: isMobile ? 10 : 11, // Adjusted font size for consistency
                          fontWeight: FontWeight.bold,
                        ),
                        iconSize: isMobile ? 10 : 11, // Adjusted icon size for consistency
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

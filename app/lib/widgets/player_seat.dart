import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'poker_card.dart';
import 'seat_hand.dart';
import 'imperial_currency.dart';

import '../utils/responsive_utils.dart';

class PlayerSeat extends StatelessWidget {
  final String name;
  final int chips; // Changed from String to int
  final bool isMe;
  final bool isActive;
  final bool isDealer;
  final bool isFolded;
  final List<dynamic>? cards; // Changed to dynamic to handle [null, null]
  final String? handRank; // Add hand rank for showdown
  final bool isWinner; // Highlight winner
  final List<String>? winningCards; // <-- NEW: Specific cards to highlight
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
    this.winningCards, // <-- NEW
    this.currentBet, // Added
  });

  @override
  Widget build(BuildContext context) {
    // Determine if it's a mobile device FIRST so it can be used in calculations
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    // ✅ Responsive scaling based on screen size to prevent UI overlap
    final screenHeight = MediaQuery.of(context).size.height;
    final scaleFactor = (screenHeight / 800).clamp(0.8, 1.2); // Base reference: 800px
    
    // Use unified scale for consistent aspect ratios
    // Larger avatar for "Me" player - REDUCED by 15% as requested for small screens
    final double avatarSize = ResponsiveUtils.scale(context, isMe ? (isMobile ? 55 : 65) : 45) * scaleFactor; 
    
    // Balanced card size for "Me" - wider as requested
    final double cardWidth = ResponsiveUtils.scale(context, isMe ? 70 : 28);
    // Ensure height matches PokerCard aspect ratio (1.4) to prevent clipping
    final double cardHeight = cardWidth * 1.4;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cards
        SeatHand(
          visibleCards: cards,
          cardCount: 2, // Default for Hold'em
          isFolded: isFolded,
          cardWidth: cardWidth,
          isWinner: isWinner,
          isMe: isMe,
          winningCards: winningCards, // <-- NEW: Pass winning cards
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
          // 📱 FIX: Increased height on mobile to allow aggressive bottom padding
          height: avatarSize + (isMobile ? 45 : 30),
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
                  // ✅ NEON GREEN TURN INDICATOR
                  border: Border.all(
                    color: isActive 
                        ? (isMe ? const Color(0xFF39FF14) : const Color(0xFFFFD700)) // Neon Green for ME, Gold for others
                        : Colors.grey.shade800,
                    width: isActive ? (isMe ? 4 : 3) : 2, // Thicker border for ME
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
                // 📱 FIX: Aggressive bottom padding for mobile to avoid screen edge clipping
                bottom: isMobile ? 12 : 0,
                child: Container(
                  // ✅ Responsive padding based on screen height
                  padding: EdgeInsets.symmetric(
                    horizontal: (screenHeight * 0.012).clamp(8.0, 14.0),
                    vertical: (screenHeight * 0.005).clamp(3.0, 6.0),
                  ),
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
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

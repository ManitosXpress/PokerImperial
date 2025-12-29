import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../player_seat.dart';
import '../chip_stack.dart';
import '../../utils/responsive_utils.dart';

class PlayersSeatGrid extends StatelessWidget {
  final List<dynamic>? players;
  final String? myId;
  final String? currentTurn;
  final String? dealerId;
  final Map<String, dynamic>? winners;
  final double tableWidth;
  final double tableHeight;
  final double screenWidth;
  final double screenHeight;
  final bool isMobile;

  const PlayersSeatGrid({
    super.key,
    required this.players,
    required this.myId,
    this.currentTurn,
    this.dealerId,
    this.winners,
    required this.tableWidth,
    required this.tableHeight,
    required this.screenWidth,
    required this.screenHeight,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    if (players == null || players!.isEmpty) return const SizedBox.shrink();

    // 1. Calculate Center & Radius
    final double centerX = screenWidth / 2;
    // Adjust centerY slightly up to account for bottom controls space
    final double centerY = screenHeight * (isMobile ? 0.38 : 0.4); 

    return Stack(
      children: players!.asMap().entries.map((entry) {
        int index = entry.key;
        Map<String, dynamic> player = entry.value;

        // 2. Circular Positioning Logic
        final playersList = players!;
        final myIndex = playersList.indexWhere((p) => p['id'] == myId);
        final int offset = myIndex != -1 ? myIndex : 0;
        int totalPlayers = playersList.length;
        
        // Rotate so "Me" is always at bottom center
        int visualIndex = (index - offset + totalPlayers) % totalPlayers;

        double angleStep = 2 * math.pi / totalPlayers;
        double startAngle = math.pi / 2; // Bottom (90 degrees)
        double angle = startAngle + (visualIndex * angleStep);

        // Define elliptical radius based on table size + padding
        final rX = tableWidth / 2 + ResponsiveUtils.scale(context, isMobile ? 15 : 45);
        final rY = tableHeight / 2 + ResponsiveUtils.scale(context, isMobile ? 15 : 25);

        // Player Position
        final x = centerX + (rX * math.cos(angle)) - 40; // -40 centers the seat (80px width)
        final y = centerY + (rY * math.sin(angle)) - 45; // -45 centers the seat (90px height)

        // Special override for "Me" (Force to bottom center safe area)
        final bool isMe = player['id'] == myId;
        double finalY = y;
        if (isMe) {
          finalY = screenHeight - ResponsiveUtils.scaleHeight(context, isMobile ? 160 : 180); 
        }

        // 3. Data Extraction (Safe Parsing)
        bool isActive = player['id'] == currentTurn;
        bool isFolded = player['isFolded'] ?? false;
        bool isDealer = player['id'] == dealerId;
        bool isWinner = false; // Add winner logic if needed based on `winners` map

        // 4. RESTORE CARD VISIBILITY LOGIC
        List<String>? cards;
        if (isMe && player['hand'] != null) {
          // My Cards
          cards = (player['hand'] as List).map((e) => e.toString()).toList();
        } else if (!isFolded && player['hand'] != null && (player['hand'] as List).isNotEmpty) {
           // Showdown / Open Cards
           cards = (player['hand'] as List).map((e) => e.toString()).toList();
        }

        // 5. Bet Position (Slightly inward from player)
        final betRx = rX - (isMobile ? 50 : 80);
        final betRy = rY - (isMobile ? 40 : 60);
        final betX = centerX + (betRx * math.cos(angle)) - 10;
        final betY = centerY + (betRy * math.sin(angle)) - 20;

        // Force My Bet Position above my cards
        double finalBetX = betX;
        double finalBetY = betY;
        if (isMe) {
           finalBetX = centerX - 10;
           finalBetY = finalY - 50;
        }

        return Stack(
          children: [
            // A. THE SEAT
            Positioned(
              left: isMe ? (screenWidth / 2) - 40 : x,
              top: finalY,
              child: PlayerSeat(
                name: player['name'] ?? 'Unknown',
                chips: (player['chips'] is int) 
                    ? player['chips'] 
                    : int.tryParse(player['chips']?.toString() ?? '0') ?? 0,
                isActive: isActive,
                isMe: isMe,
                isDealer: isDealer,
                isFolded: isFolded,
                cards: cards, // Pass the parsed cards!
                handRank: player['handRank'],
                isWinner: isWinner,
              ),
            ),

            // B. THE BET (CHIPS) - Only if amount > 0
            if ((player['currentBet'] ?? 0) > 0)
              Positioned(
                left: finalBetX,
                top: finalBetY,
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
                        style: TextStyle(color: Colors.white, fontSize: isMobile ? 12 : 10),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}

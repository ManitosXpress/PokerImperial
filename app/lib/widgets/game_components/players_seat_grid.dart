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

    final double centerX = screenWidth / 2;
    // Move center slightly up to leave space for controls at bottom
    final double centerY = screenHeight * (isMobile ? 0.40 : 0.45); 

    return Stack(
      children: players!.asMap().entries.map((entry) {
        int index = entry.key;
        Map<String, dynamic> player = entry.value;

        // --- 1. CIRCULAR POSITIONING ---
        final playersList = players!;
        final myIndex = playersList.indexWhere((p) => p['id'].toString() == myId.toString());
        final int offset = myIndex != -1 ? myIndex : 0;
        int totalPlayers = playersList.length;
        
        // Rotate visual index so "Me" is always at bottom (index 0 visual)
        int visualIndex = (index - offset + totalPlayers) % totalPlayers;

        // Angle Logic: Start from 90 degrees (Bottom)
        double angleStep = 2 * math.pi / totalPlayers;
        double startAngle = math.pi / 2; 
        double angle = startAngle + (visualIndex * angleStep);

        // Elliptical Radius
        final rX = tableWidth / 2 + (isMobile ? 30 : 60);
        final rY = tableHeight / 2 + (isMobile ? 30 : 40);

        final playerX = centerX + (rX * math.cos(angle)) - 40; // Center the 80px seat
        final playerY = centerY + (rY * math.sin(angle)) - 45; // Center the 90px seat

        // Override "Me" Position to be perfectly centered at bottom
        final bool isMe = player['id'].toString() == myId.toString();
        double finalX = playerX;
        double finalY = playerY;
        
        if (isMe) {
          finalX = centerX - 40; // Perfect center
          finalY = screenHeight - (isMobile ? 140 : 180); // Fixed from bottom
        }

        // --- 2. DATA PREPARATION ---
        bool isActive = player['id'] == currentTurn;
        bool isFolded = player['isFolded'] ?? false;
        bool isDealer = player['id'] == dealerId;
        
        // --- 3. CARD VISIBILITY LOGIC (CRITICAL FIX) ---
        List<String>? cardsToRender;
        if (player['hand'] != null && (player['hand'] as List).isNotEmpty) {
           // Show cards if it's ME or if the hand is revealed (Showdown/FaceUp)
           // You can add a 'showCards' flag from backend if needed
           if (isMe || !isFolded /* Add showdown check here if needed */) {
             cardsToRender = (player['hand'] as List).map((e) => e.toString()).toList();
           }
        }

        // --- 4. BET POSITIONING (VECTOR MATH) ---
        // Calculate point 30% towards the center from the player
        double betX = finalX + (centerX - finalX - 40) * 0.30; 
        double betY = finalY + (centerY - finalY - 45) * 0.30;
        
        // Force my bet to be right above my cards
        if (isMe) {
           betX = centerX - 20; // Slightly centered
           betY = finalY - 60;
        }

        int currentBet = int.tryParse(player['currentBet']?.toString() ?? '0') ?? 0;

        return Stack(
          children: [
            // LAYER A: The Player Seat
            Positioned(
              left: finalX,
              top: finalY,
              child: PlayerSeat(
                name: player['name'] ?? 'Unknown',
                chips: player['chips'] ?? 0,
                isActive: isActive,
                isMe: isMe,
                isDealer: isDealer,
                isFolded: isFolded,
                cards: cardsToRender, // <--- PASSING CARDS HERE
                handRank: player['handRank'],
              ),
            ),

            // LAYER B: The Bet Chips (Only if > 0)
            if (currentBet > 0)
              Positioned(
                left: betX,
                top: betY,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChipStack(amount: currentBet, size: 25), // Smaller chips for bets
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                      ),
                      child: Text(
                        '$currentBet',
                        style: const TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 10
                        ),
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

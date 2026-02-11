import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart'; // ✅ Import for robust UID check
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
  final String stage; // <-- NEW: Receive game stage

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
    this.stage = 'waiting', // Default
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
        
        // ✅ CRITICAL FIX: Robust "Me" detection using Socket ID OR Firebase UID
        // This ensures table rotation works even if Socket ID changed (reconnection)
        final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
        
        final myIndex = playersList.indexWhere((p) => 
            p['id'].toString() == myId.toString() || 
            (currentUserUid != null && p['uid'] == currentUserUid)
        );
        
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
        final bool isMe = player['id'].toString() == myId.toString() || 
                          (currentUserUid != null && player['uid'] == currentUserUid);
                          
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
        
        // --- 3. CARD VISIBILITY LOGIC (UPDATED WITH SHOWDOWN REVEAL) ---
        // 🔐 SECURITY: Only show cards if:
        // 1. It is ME
        // 2. OR state is SHOWDOWN / FINISHED
        // 3. OR the player has revealed them (e.g. winner)
        bool shouldShowCards = isMe;
        
        if (stage.toLowerCase() == 'showdown' || stage.toLowerCase() == 'finished') {
             shouldShowCards = true;
        }

        List<String>? cardsToRender;
        if (shouldShowCards && player['hand'] != null && (player['hand'] as List).isNotEmpty) {
           // Show cards if allowed
           cardsToRender = (player['hand'] as List).map((e) => e.toString()).toList();
        } else if (!isMe && !isFolded && player['hand'] != null) {
           // If not allowed to see face, but player has cards (not folded), 
           // we still pass NULL to SeatHand so it renders CARD BACKS
           // The logic here is:
           // If cardsToRender is NULL, SeatHand checks isFolded.
           // If isFolded=false and cardsToRender=null, SeatHand returns SizedBox/Empty?
           // WAIT! SeatHand logic:
           // if (widget.isFolded && widget.visibleCards == null) return SizedBox.shrink();
           // if (visibleCards == null) ... it tries to render based on cardCount.
           // Actually SeatHand uses `widget.cardCount` to generate list.
           
           // If I pass null, SeatHand will look for visibleCards. If null, it checks `cardCode`.
           // `cardCode` will be null.
           // `isFaceUp` logic in SeatHand: `isFaceUp` depends on animation mostly.
           // BUT render: `isFaceUp ? ... (cardCode != null ? PokerCard : SizedBox) : CardBack`.
           
           // So if I pass null for `cardsToRender`, `cardCode` is null.
           // If `isFaceUp` is true, it renders SizedBox (invisible space).
           // If `isFaceUp` is false, it renders CardBack.
           
           // We want CardBacks for bots/opponents.
           // So `cardsToRender` should be null.
           // And we rely on SeatHand to show CardBacks.
           // Default state of SeatHand is face down (isFaceUp=false) unless I force it.
           // SeatHand uses `_flipControllers` to flip.
           
           // So, logic:
           // IF shouldShowCards -> pass List. SeatHand will flip up.
           // IF NOT shouldShowCards -> pass null. SeatHand will stay face down (CardBack).
           cardsToRender = null;
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

        // --- 5. WINNER LOGIC ---
        bool isWinner = false;
        List<String>? playerWinningCards;
        
        if (winners != null && winners!['winners'] != null) {
           final winnersList = winners!['winners'] as List;
           final winnerData = winnersList.firstWhere(
              (w) => w['playerId'] == player['id'] || w['uid'] == player['uid'], 
              orElse: () => null
           );
           
           if (winnerData != null) {
              isWinner = true;
              // Winner automatically shows cards too
              if (winnerData['winningCards'] != null) {
                 playerWinningCards = (winnerData['winningCards'] as List).map((e) => e.toString()).toList();
              }
              // Force show cards for winner even if stage weirdness (though winners implies finished)
              if (player['hand'] != null) {
                 cardsToRender = (player['hand'] as List).map((e) => e.toString()).toList();
              }
           }
        }

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
                cards: cardsToRender, // <--- NOW SAFE

                handRank: player['handRank'],
                isWinner: isWinner,
                winningCards: playerWinningCards, // <--- PASS WINNING CARDS
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

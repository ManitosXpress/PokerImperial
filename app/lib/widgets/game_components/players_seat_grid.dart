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
        bool shouldShowCards = isMe;
        
        if (stage.toLowerCase() == 'showdown' || stage.toLowerCase() == 'finished') {
             shouldShowCards = true;
        }

        List<String>? cardsToRender;
        if (shouldShowCards && player['hand'] != null && (player['hand'] as List).isNotEmpty) {
           // Show cards if allowed
           // ✅ FIX: Handle both String codes (e.g. "Ah") and Object representations (from pokersolver)
           cardsToRender = (player['hand'] as List).map((e) {
             String str = e.toString();
             
             // 1. Check if it's already a clean code like "Ah" or "10d"
             // Typically length 2 or 3
             if (str.length <= 3 && !str.contains('{') && !str.contains('value')) {
                // Normalize 10 -> t just in case
                if (str.startsWith('10')) return str.replaceFirst('10', 't');
                return str;
             }

             // 2. Dynamic Object Access (If it's a Map/JS Object)
             try {
                dynamic d = e;
                if (d['value'] != null && d['suit'] != null) {
                   final val = d['value']?.toString() ?? '';
                   final suit = d['suit']?.toString() ?? '';
                   return '$val$suit'; // Result: "9d"
                }
             } catch (err) {
                // Not a map-like object
             }

             // 3. Regex Parsing for Stringified Objects
             // Format: "{value: 9, suit: d, ...}"
             if (str.contains('value') && str.contains('suit')) {
                 // value: 9 (or value: T), suit: d
                 // Regex to capture value and suit
                 // Look for "value: X" and "suit: Y"
                 // Flexible regex for different formats
                 final valueMatch = RegExp(r'value:\s*([a-zA-Z0-9]+)').firstMatch(str);
                 final suitMatch = RegExp(r'suit:\s*([a-zA-Z0-9]+)').firstMatch(str);

                 if (valueMatch != null && suitMatch != null) {
                    final val = valueMatch.group(1) ?? '';
                    final suit = suitMatch.group(1) ?? '';
                    return '$val$suit';
                 }
             }

             // 4. Fallback
             print('⚠️ [PlayersSeatGrid] Failed to parse card: $e');
             return 'card_back'; 
           }).toList();
        } else if (!isMe && !isFolded && player['hand'] != null) {
           cardsToRender = null;
        }

        // 🐞 DEBUG LOGS
        if (stage.toLowerCase() == 'showdown' || stage.toLowerCase() == 'finished') {
            print('🔍 [DEBUG] Player ${player['name']} (Me: $isMe) Stage: $stage');
            print('   - Raw Hand: ${player['hand']}');
            print('   - Should Show: $shouldShowCards');
            print('   - Cards Rendered: $cardsToRender');
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

        // --- 5. WINNER LOGIC & LOCALIZATION ---
        bool isWinner = false;
        List<String>? playerWinningCards;
        String? displayHandRank = player['handRank'];

        // 🇪🇸 LOCALIZATION: Translate Hand Rank to Spanish
        if (displayHandRank != null) {
          if (displayHandRank.contains('High Card')) displayHandRank = 'Carta Alta';
          else if (displayHandRank.contains('Pair') && !displayHandRank.contains('Two')) displayHandRank = 'Pareja';
          else if (displayHandRank.contains('Two Pair')) displayHandRank = 'Doble Pareja';
          else if (displayHandRank.contains('Three of a Kind')) displayHandRank = 'Trío';
          else if (displayHandRank.contains('Straight') && !displayHandRank.contains('Flush')) displayHandRank = 'Escalera';
          else if (displayHandRank.contains('Flush') && !displayHandRank.contains('Straight')) displayHandRank = 'Color';
          else if (displayHandRank.contains('Full House')) displayHandRank = 'Full House';
          else if (displayHandRank.contains('Four of a Kind')) displayHandRank = 'Póker';
          else if (displayHandRank.contains('Straight Flush')) displayHandRank = 'Escalera de Color';
          else if (displayHandRank.contains('Royal Flush')) displayHandRank = 'Escalera Real';
        }
        
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
                 // ✅ FIX: Apply same robust parsing to winning cards
                 playerWinningCards = (winnerData['winningCards'] as List).map((e) {
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
                    return ''; // Skip invalid
                 }).where((e) => e.isNotEmpty).toList();
              }
              // Force show cards for winner even if stage weirdness (though winners implies finished)
              if (player['hand'] != null) {
                 // Duplicate parsing logic for safety
                 cardsToRender = (player['hand'] as List).map((e) {
                     String str = e.toString();
                     if (str.length <= 3 && !str.contains('{') && !str.contains('value')) {
                        if (str.startsWith('10')) return str.replaceFirst('10', 't');
                        return str;
                     }
                     try {
                        dynamic d = e;
                        if (d['value'] != null && d['suit'] != null) {
                           final val = d['value']?.toString() ?? '';
                           final suit = d['suit']?.toString() ?? '';
                           return '$val$suit';
                        }
                     } catch (err) {}
                     if (str.contains('value') && str.contains('suit')) {
                         final valueMatch = RegExp(r'value:\s*([a-zA-Z0-9]+)').firstMatch(str);
                         final suitMatch = RegExp(r'suit:\s*([a-zA-Z0-9]+)').firstMatch(str);
                         if (valueMatch != null && suitMatch != null) {
                            final val = valueMatch.group(1) ?? '';
                            final suit = suitMatch.group(1) ?? '';
                            return '$val$suit';
                         }
                     }
                     return 'card_back';
                 }).toList();
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

import 'dart:math';
import 'types.dart';

class BotAI {
  static final Random _random = Random();

  static String generateName() {
    const names = [
      'Alex', 'Sam', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Jamie',
      'Dakota', 'Cameron', 'Quinn', 'Avery', 'Reese', 'Peyton', 'Skyler'
    ];
    return '${names[_random.nextInt(names.length)]} (Bot)';
  }

  static Future<Map<String, dynamic>> decideAction(
    Player bot, 
    GameState gameState,
  ) async {
    // Simulate thinking time
    final delay = 1000 + _random.nextInt(2000); // 1-3 seconds
    await Future.delayed(Duration(milliseconds: delay));

    // Basic logic
    final currentBet = gameState.currentBet;
    final callAmount = currentBet - bot.currentBet;
    final potOdds = callAmount / (gameState.pot + callAmount);
    
    // Simple hand strength (random for now as we don't have full evaluator in AI yet)
    // In a real implementation, we'd use HandEvaluator to get a score 0-100
    double handStrength = _random.nextDouble(); 
    
    // Adjust strength based on hole cards (simple heuristic)
    if (bot.hand.isNotEmpty) {
      final card1 = bot.hand[0];
      final card2 = bot.hand[1];
      // Check for pairs
      if (card1[0] == card2[0]) handStrength += 0.3;
      // Check for high cards
      if ('AKQJ10'.contains(card1[0])) handStrength += 0.1;
      if ('AKQJ10'.contains(card2[0])) handStrength += 0.1;
    }

    // Decision logic
    String action = 'fold';
    int amount = 0;

    if (callAmount == 0) {
      // Can check
      if (handStrength > 0.7) {
        action = 'bet';
        amount = gameState.minBet;
      } else {
        action = 'check';
      }
    } else {
      // Facing a bet
      if (handStrength > 0.8) {
        action = 'raise';
        amount = currentBet * 2;
      } else if (handStrength > 0.4 || callAmount < (bot.chips * 0.05)) {
        action = 'call';
      } else {
        action = 'fold';
      }
    }
    
    // Validation
    if (action == 'raise' && amount > bot.chips) {
      action = 'allin';
      amount = bot.chips;
    }
    if (action == 'call' && callAmount > bot.chips) {
      action = 'allin';
      amount = bot.chips;
    }
    if (action == 'bet' && amount > bot.chips) {
      action = 'allin';
      amount = bot.chips;
    }

    return {
      'action': action,
      'amount': amount,
    };
  }
}

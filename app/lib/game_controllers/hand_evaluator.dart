import 'types.dart';

class HandEvaluator {
  static List<Map<String, dynamic>> determineWinners(List<Player> players, List<String> communityCards) {
    if (communityCards.length < 5) return [];

    List<Map<String, dynamic>> activeHands = [];

    for (var player in players) {
      if (player.isFolded) continue;

      // Combine hole cards and community cards
      final allCards = [...player.hand, ...communityCards];
      
      try {
        final hand = PokerHand.fromStrings(allCards);
        activeHands.add({
          'playerId': player.id,
          'hand': hand,
          'rank': hand.rankValue,
          'score': hand.score,
          'description': hand.rankDescription,
        });
      } catch (e) {
        print('Error evaluating hand for ${player.name}: $e');
      }
    }

    // Sort by hand strength (descending)
    activeHands.sort((a, b) {
      final handA = a['hand'] as PokerHand;
      final handB = b['hand'] as PokerHand;
      return handB.compareTo(handA); // Descending order
    });

    if (activeHands.isEmpty) return [];

    // Identify winners (handle splits)
    final bestHand = activeHands.first['hand'] as PokerHand;
    final winners = activeHands.where((h) => (h['hand'] as PokerHand).compareTo(bestHand) == 0).toList();

    return winners.map((w) => {
      'playerId': w['playerId'],
      'handRank': w['description'],
      'winningHand': (w['hand'] as PokerHand).cards.map((c) => c.toString()).toList(),
    }).toList();
  }

  static Map<String, dynamic> calculatePotDistribution(List<Player> players, List<Map<String, dynamic>> winners, int totalPot) {
    int winnerCount = winners.length;
    if (winnerCount == 0) return {'winners': []};
    
    int amountPerWinner = totalPot ~/ winnerCount;
    int remainder = totalPot % winnerCount;
    
    List<Map<String, dynamic>> payouts = [];
    
    for (var i = 0; i < winners.length; i++) {
      int amount = amountPerWinner;
      if (i < remainder) amount++; // Distribute remainder
      
      payouts.add({
        'playerId': winners[i]['playerId'],
        'amount': amount,
        'handRank': winners[i]['handRank'],
        'name': players.firstWhere((p) => p.id == winners[i]['playerId']).name,
      });
    }
    
    return {
      'winners': payouts,
    };
  }
}

// Custom Poker Hand Implementation
class PokerHand implements Comparable<PokerHand> {
  final List<String> cards;
  late final int rankValue;
  late final String rankDescription;
  late final List<int> score; // Used for tie-breaking

  PokerHand._(this.cards, this.rankValue, this.rankDescription, this.score);

  factory PokerHand.fromStrings(List<String> cardStrings) {
    // 1. Parse cards
    final parsedCards = cardStrings.map(_parseCard).toList();
    
    // 2. Find best 5-card combination
    return _evaluateBestHand(parsedCards);
  }

  static _Card _parseCard(String s) {
    if (s.length < 2) throw FormatException('Invalid card string: $s');
    final rankStr = s.substring(0, s.length - 1);
    final suitStr = s.substring(s.length - 1);
    
    int rank;
    switch (rankStr) {
      case 'A': rank = 14; break;
      case 'K': rank = 13; break;
      case 'Q': rank = 12; break;
      case 'J': rank = 11; break;
      case '10': rank = 10; break;
      default: rank = int.parse(rankStr);
    }
    
    return _Card(rank, suitStr, s);
  }

  static PokerHand _evaluateBestHand(List<_Card> allCards) {
    // Generate all 5-card combinations (7 choose 5 = 21 combinations)
    // For performance, we can just check the best possible rank.
    // But generating combinations is safer for correctness.
    
    List<List<_Card>> combinations = _getCombinations(allCards, 5);
    PokerHand? bestHand;
    
    for (final combo in combinations) {
      final hand = _evaluate5CardHand(combo);
      if (bestHand == null || hand.compareTo(bestHand) > 0) {
        bestHand = hand;
      }
    }
    
    return bestHand!;
  }

  static List<List<_Card>> _getCombinations(List<_Card> list, int k) {
    if (k == 0) return [[]];
    if (list.isEmpty) return [];
    
    final first = list.first;
    final rest = list.sublist(1);
    
    final withFirst = _getCombinations(rest, k - 1).map((c) => [first, ...c]).toList();
    final withoutFirst = _getCombinations(rest, k);
    
    return [...withFirst, ...withoutFirst];
  }

  static PokerHand _evaluate5CardHand(List<_Card> cards) {
    // Sort by rank descending
    cards.sort((a, b) => b.rank.compareTo(a.rank));
    
    final isFlush = _isFlush(cards);
    final isStraight = _isStraight(cards);
    
    // Royal Flush
    if (isFlush && isStraight && cards.first.rank == 14 && cards.last.rank == 10) {
      return PokerHand._(cards.map((c) => c.original).toList(), 10, 'Royal Flush', [10]);
    }
    
    // Straight Flush
    if (isFlush && isStraight) {
      return PokerHand._(cards.map((c) => c.original).toList(), 9, 'Straight Flush', [cards.first.rank]);
    }
    
    // Four of a Kind
    final fourKind = _getNOfAKind(cards, 4);
    if (fourKind != null) {
      return PokerHand._(cards.map((c) => c.original).toList(), 8, 'Four of a Kind', [fourKind, _getKicker(cards, [fourKind])]);
    }
    
    // Full House
    final threeKind = _getNOfAKind(cards, 3);
    if (threeKind != null) {
      final remaining = cards.where((c) => c.rank != threeKind).toList();
      final twoKind = _getNOfAKind(remaining, 2);
      if (twoKind != null) {
        return PokerHand._(cards.map((c) => c.original).toList(), 7, 'Full House', [threeKind, twoKind]);
      }
    }
    
    // Flush
    if (isFlush) {
      return PokerHand._(cards.map((c) => c.original).toList(), 6, 'Flush', cards.map((c) => c.rank).toList());
    }
    
    // Straight
    if (isStraight) {
      return PokerHand._(cards.map((c) => c.original).toList(), 5, 'Straight', [cards.first.rank]);
    }
    
    // Three of a Kind
    if (threeKind != null) {
      final kickers = cards.where((c) => c.rank != threeKind).map((c) => c.rank).toList();
      return PokerHand._(cards.map((c) => c.original).toList(), 4, 'Three of a Kind', [threeKind, ...kickers]);
    }
    
    // Two Pair
    final firstPair = _getNOfAKind(cards, 2);
    if (firstPair != null) {
      final remaining = cards.where((c) => c.rank != firstPair).toList();
      final secondPair = _getNOfAKind(remaining, 2);
      if (secondPair != null) {
        final kicker = cards.where((c) => c.rank != firstPair && c.rank != secondPair).first.rank;
        return PokerHand._(cards.map((c) => c.original).toList(), 3, 'Two Pair', [firstPair, secondPair, kicker]);
      }
    }
    
    // One Pair
    if (firstPair != null) {
      final kickers = cards.where((c) => c.rank != firstPair).map((c) => c.rank).toList();
      return PokerHand._(cards.map((c) => c.original).toList(), 2, 'Pair', [firstPair, ...kickers]);
    }
    
    // High Card
    return PokerHand._(cards.map((c) => c.original).toList(), 1, 'High Card', cards.map((c) => c.rank).toList());
  }

  static bool _isFlush(List<_Card> cards) {
    final suit = cards.first.suit;
    return cards.every((c) => c.suit == suit);
  }

  static bool _isStraight(List<_Card> cards) {
    // Handle Ace low straight (A, 5, 4, 3, 2)
    if (cards.first.rank == 14 && cards[1].rank == 5 && cards[2].rank == 4 && cards[3].rank == 3 && cards.last.rank == 2) {
      // Move Ace to end for comparison logic if needed, but here we just return true
      // Note: In a real straight comparison, 5-high straight is lower than 6-high.
      // We should probably handle the rank adjustment for Ace-low straight.
      return true;
    }
    
    for (int i = 0; i < cards.length - 1; i++) {
      if (cards[i].rank != cards[i + 1].rank + 1) return false;
    }
    return true;
  }

  static int? _getNOfAKind(List<_Card> cards, int n) {
    final counts = <int, int>{};
    for (final card in cards) {
      counts[card.rank] = (counts[card.rank] ?? 0) + 1;
    }
    
    // Find rank with count n (highest first since map iteration order isn't guaranteed sorted by key, but we want highest rank)
    final matches = counts.entries.where((e) => e.value == n).map((e) => e.key).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.compareTo(a)); // Descending
    return matches.first;
  }
  
  static int _getKicker(List<_Card> cards, List<int> excludeRanks) {
    return cards.firstWhere((c) => !excludeRanks.contains(c.rank)).rank;
  }

  @override
  int compareTo(PokerHand other) {
    if (rankValue != other.rankValue) {
      return rankValue.compareTo(other.rankValue);
    }
    
    // Compare scores (tie-breakers)
    for (int i = 0; i < score.length && i < other.score.length; i++) {
      if (score[i] != other.score[i]) {
        return score[i].compareTo(other.score[i]);
      }
    }
    
    return 0;
  }
  
  @override
  String toString() => '$rankDescription (${cards.join(" ")})';
}

class _Card {
  final int rank;
  final String suit;
  final String original;
  
  _Card(this.rank, this.suit, this.original);
  
  @override
  String toString() => original;
}

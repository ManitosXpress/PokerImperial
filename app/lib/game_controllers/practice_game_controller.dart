import 'dart:async';
import 'dart:math';
import 'types.dart';
import 'hand_evaluator.dart';
import 'bot_ai.dart';
import 'poker_state_machine.dart';

class PracticeGameController {
  late GameState gameState;
  late PokerStateMachine _fsm;
  final Function(Map<String, dynamic>) onStateChange;
  Timer? _botTimer;

  PracticeGameController({
    required String humanPlayerId,
    required String humanPlayerName,
    required this.onStateChange,
  }) {
    _initGame(humanPlayerId, humanPlayerName);
  }

  void _initGame(String humanId, String humanName) {
    // Create players
    List<Player> players = [];
    
    // Human
    players.add(Player(id: humanId, name: humanName));
    
    // Bots
    for (int i = 0; i < 7; i++) {
      players.add(Player(
        id: 'bot-$i',
        name: BotAI.generateName(),
        isBot: true,
      ));
    }

    gameState = GameState(
      roomId: 'practice-room',
      dealerId: players[0].id,
      players: players,
    );

    _fsm = PokerStateMachine(gameState);
    
    _startNewHand();
  }

  void _startNewHand() {
    gameState.status = GameStatus.playing;
    gameState.stage = GameStage.preFlop;
    gameState.pot = 0;
    gameState.communityCards = [];
    gameState.currentBet = gameState.bigBlind;
    gameState.winners = null;
    
    // Reset player states
    for (var p in gameState.players) {
      p.isFolded = false;
      p.isAllIn = false;
      p.currentBet = 0;
      p.hand = _dealCards(2);
      p.handRank = null;
    }

    // Blinds
    _postBlinds();
    
    // Deal community (hidden initially)
    // In a real game we deal them as stages progress
    
    _notifyState();
    
    // Check if first player is bot
    _checkNextTurn();
  }

  List<String> _dealCards(int count) {
    final suits = ['h', 'd', 'c', 's'];
    final ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    List<String> cards = [];
    final random = Random();
    
    for (int i = 0; i < count; i++) {
      String card;
      do {
        card = '${ranks[random.nextInt(ranks.length)]}${suits[random.nextInt(suits.length)]}';
      } while (cards.contains(card) || _isCardUsed(card));
      cards.add(card);
    }
    return cards;
  }

  bool _isCardUsed(String card) {
    // Check all players hands and community cards
    for (var p in gameState.players) {
      if (p.hand.contains(card)) return true;
    }
    if (gameState.communityCards.contains(card)) return true;
    return false;
  }

  void _postBlinds() {
    int dealerIdx = gameState.players.indexWhere((p) => p.id == gameState.dealerId);
    int sbIdx = (dealerIdx + 1) % gameState.players.length;
    int bbIdx = (dealerIdx + 2) % gameState.players.length;
    int utgIdx = (dealerIdx + 3) % gameState.players.length;

    _placeBet(gameState.players[sbIdx], gameState.smallBlind);
    _placeBet(gameState.players[bbIdx], gameState.bigBlind);

    gameState.currentTurn = gameState.players[utgIdx].id;
  }

  void _placeBet(Player player, int amount) {
    if (amount > player.chips) amount = player.chips;
    player.chips -= amount;
    player.currentBet += amount;
    gameState.pot += amount;
    
    if (player.chips == 0) player.isAllIn = true;
    if (player.currentBet > gameState.currentBet) gameState.currentBet = player.currentBet;
  }

  void handleAction(String playerId, String action, [int amount = 0]) {
    final player = gameState.players.firstWhere((p) => p.id == playerId);
    
    if (gameState.currentTurn != playerId) return;

    switch (action) {
      case 'fold':
        player.isFolded = true;
        break;
      case 'call':
        int callAmount = gameState.currentBet - player.currentBet;
        _placeBet(player, callAmount);
        break;
      case 'check':
        // Allowed if currentBet == player.currentBet
        break;
      case 'bet':
      case 'raise':
        int totalBet = amount;
        if (action == 'raise') totalBet += gameState.currentBet; // Simplified
        // Actually amount usually means "add to pot" or "total bet" depending on UI
        // Let's assume amount is the TOTAL bet the player wants to be at
        if (amount < gameState.minBet) amount = gameState.minBet;
        int diff = amount - player.currentBet;
        _placeBet(player, diff);
        break;
      case 'allin':
        _placeBet(player, player.chips);
        break;
    }

    _nextTurn();
  }

  void _nextTurn() {
    // Check if round complete
    if (_fsm.isRoundComplete()) {
      _advanceStage();
      return;
    }

    // Find next active player
    int currentIdx = gameState.players.indexWhere((p) => p.id == gameState.currentTurn);
    int nextIdx = (currentIdx + 1) % gameState.players.length;
    
    while (gameState.players[nextIdx].isFolded || gameState.players[nextIdx].isAllIn) {
      nextIdx = (nextIdx + 1) % gameState.players.length;
      if (nextIdx == currentIdx) {
        // Everyone else folded/all-in
        _advanceStage();
        return;
      }
    }

    gameState.currentTurn = gameState.players[nextIdx].id;
    _notifyState();
    _checkNextTurn();
  }

  void _checkNextTurn() {
    final currentPlayer = gameState.players.firstWhere((p) => p.id == gameState.currentTurn);
    if (currentPlayer.isBot) {
      BotAI.decideAction(currentPlayer, gameState).then((decision) {
        handleAction(currentPlayer.id, decision['action'], decision['amount']);
      });
    }
  }

  void _advanceStage() {
    _fsm.nextStage();
    
    // Deal community cards
    if (gameState.stage == GameStage.flop) {
      gameState.communityCards.addAll(_dealCards(3));
    } else if (gameState.stage == GameStage.turn || gameState.stage == GameStage.river) {
      gameState.communityCards.addAll(_dealCards(1));
    } else if (gameState.stage == GameStage.showdown) {
      _handleShowdown();
      return;
    }

    // Reset bets for new round
    gameState.currentBet = 0;
    for (var p in gameState.players) {
      p.currentBet = 0;
    }

    // Set turn to first active player after dealer
    int dealerIdx = gameState.players.indexWhere((p) => p.id == gameState.dealerId);
    int nextIdx = (dealerIdx + 1) % gameState.players.length;
    while (gameState.players[nextIdx].isFolded || gameState.players[nextIdx].isAllIn) {
      nextIdx = (nextIdx + 1) % gameState.players.length;
    }
    gameState.currentTurn = gameState.players[nextIdx].id;

    _notifyState();
    _checkNextTurn();
  }

  void _handleShowdown() {
    final winners = HandEvaluator.determineWinners(gameState.players, gameState.communityCards);
    final distribution = HandEvaluator.calculatePotDistribution(gameState.players, winners, gameState.pot);
    
    gameState.winners = distribution;
    gameState.status = GameStatus.finished;
    gameState.currentTurn = null;
    
    // Distribute chips
    for (var win in distribution['winners']) {
      final player = gameState.players.firstWhere((p) => p.id == win['playerId']);
      player.chips += (win['amount'] as int);
    }

    _notifyState();

    // Auto restart
    Timer(Duration(seconds: 5), () {
      // Move dealer
      int dealerIdx = gameState.players.indexWhere((p) => p.id == gameState.dealerId);
      gameState.dealerId = gameState.players[(dealerIdx + 1) % gameState.players.length].id;
      _startNewHand();
    });
  }

  void _notifyState() {
    onStateChange(gameState.toJson());
  }
  
  void dispose() {
    _botTimer?.cancel();
  }
}

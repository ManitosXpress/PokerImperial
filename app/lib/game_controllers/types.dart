enum GameStatus {
  waiting,
  playing,
  finished,
}

enum GameStage {
  preFlop,
  flop,
  turn,
  river,
  showdown,
}

class Player {
  final String id;
  final String name;
  int chips;
  int currentBet;
  bool isFolded;
  bool isAllIn;
  bool isBot;
  List<String> hand; // ['Ah', 'Kd']
  String? handRank; // 'Flush', 'Pair', etc. (for showdown)
  
  Player({
    required this.id,
    required this.name,
    this.chips = 10000,
    this.currentBet = 0,
    this.isFolded = false,
    this.isAllIn = false,
    this.isBot = false,
    this.hand = const [],
    this.handRank,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'chips': chips,
      'currentBet': currentBet,
      'isFolded': isFolded,
      'isAllIn': isAllIn,
      'isBot': isBot,
      'hand': hand,
      'handRank': handRank,
    };
  }
}

class Pot {
  int amount;
  List<String> eligiblePlayers; // IDs of players who can win this pot

  Pot({
    required this.amount,
    required this.eligiblePlayers,
  });
}

class GameState {
  String roomId;
  GameStatus status;
  GameStage stage;
  int pot;
  List<String> communityCards;
  String? currentTurn;
  String dealerId;
  int smallBlind;
  int bigBlind;
  int currentBet;
  int minBet;
  List<Player> players;
  List<Pot> sidePots;
  Map<String, dynamic>? winners;

  GameState({
    required this.roomId,
    this.status = GameStatus.waiting,
    this.stage = GameStage.preFlop,
    this.pot = 0,
    this.communityCards = const [],
    this.currentTurn,
    required this.dealerId,
    this.smallBlind = 10,
    this.bigBlind = 20,
    this.currentBet = 0,
    this.minBet = 20,
    this.players = const [],
    this.sidePots = const [],
    this.winners,
  });

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'status': status.toString().split('.').last,
      'stage': stage.toString().split('.').last,
      'pot': pot,
      'communityCards': communityCards,
      'currentTurn': currentTurn,
      'dealerId': dealerId,
      'smallBlind': smallBlind,
      'bigBlind': bigBlind,
      'currentBet': currentBet,
      'minBet': minBet,
      'players': players.map((p) => p.toJson()).toList(),
      'sidePots': sidePots.map((p) => {'amount': p.amount, 'eligible': p.eligiblePlayers}).toList(),
      'winners': winners,
    };
  }
}

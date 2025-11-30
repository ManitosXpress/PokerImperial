import 'types.dart';

class PokerStateMachine {
  GameState state;

  PokerStateMachine(this.state);

  void nextStage() {
    switch (state.stage) {
      case GameStage.preFlop:
        state.stage = GameStage.flop;
        break;
      case GameStage.flop:
        state.stage = GameStage.turn;
        break;
      case GameStage.turn:
        state.stage = GameStage.river;
        break;
      case GameStage.river:
        state.stage = GameStage.showdown;
        break;
      case GameStage.showdown:
        // End of game
        state.status = GameStatus.finished;
        break;
    }
  }

  bool isRoundComplete() {
    // Logic to check if all active players have matched the current bet
    // and acted at least once
    // Simplified for now
    
    int activePlayers = state.players.where((p) => !p.isFolded && !p.isAllIn).length;
    if (activePlayers <= 1) return true; // Everyone else folded or all-in

    bool allMatched = state.players.every((p) {
      if (p.isFolded || p.isAllIn) return true;
      return p.currentBet == state.currentBet;
    });

    // Also need to check if everyone acted (not just matched blinds)
    // This requires tracking 'hasActed' flag which we can add to Player or State
    // For now, assume if all matched and it's not the start of round, it's complete.
    
    return allMatched;
  }
}

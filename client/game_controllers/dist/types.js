/**
 * Shared type definitions for poker game controllers
 * These types are used by both Practice and Real Money game modes
 */
export var GameStateEnum;
(function (GameStateEnum) {
    GameStateEnum["WaitingForPlayers"] = "waiting";
    GameStateEnum["PostingBlinds"] = "posting_blinds";
    GameStateEnum["PreFlop"] = "pre-flop";
    GameStateEnum["Flop"] = "flop";
    GameStateEnum["Turn"] = "turn";
    GameStateEnum["River"] = "river";
    GameStateEnum["Showdown"] = "showdown";
})(GameStateEnum || (GameStateEnum = {}));
export var GameAction;
(function (GameAction) {
    GameAction["Fold"] = "fold";
    GameAction["Check"] = "check";
    GameAction["Call"] = "call";
    GameAction["Bet"] = "bet";
    GameAction["Raise"] = "raise";
    GameAction["AllIn"] = "allin";
})(GameAction || (GameAction = {}));
//# sourceMappingURL=types.js.map
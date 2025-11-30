/**
 * Shared type definitions for poker game controllers
 * These types are used by both Practice and Real Money game modes
 */
export declare enum GameStateEnum {
    WaitingForPlayers = "waiting",
    PostingBlinds = "posting_blinds",
    PreFlop = "pre-flop",
    Flop = "flop",
    Turn = "turn",
    River = "river",
    Showdown = "showdown"
}
export declare enum GameAction {
    Fold = "fold",
    Check = "check",
    Call = "call",
    Bet = "bet",
    Raise = "raise",
    AllIn = "allin"
}
export interface Card {
    rank: string;
    suit: string;
    toString(): string;
}
export interface Player {
    id: string;
    name: string;
    chips: number;
    hand?: string[];
    isFolded: boolean;
    currentBet: number;
    isBot?: boolean;
    isAllIn?: boolean;
    pokerSessionId?: string;
    totalRakePaid?: number;
}
export interface PotStructure {
    mainPot: number;
    sidePots: SidePot[];
    totalPot: number;
}
export interface SidePot {
    amount: number;
    eligiblePlayerIds: string[];
    description: string;
}
export interface WinnerInfo {
    playerId: string;
    playerName: string;
    amount: number;
    handRank: string;
    handDescription: string;
    potType: 'main' | 'side';
}
export interface HandResult {
    playerId: string;
    hand: any;
    rank: number;
    description: string;
}
export interface GameState {
    pot: number;
    communityCards: string[];
    currentTurn: string | null;
    dealerId: string | null;
    round: GameStateEnum;
    currentBet: number;
    minBet: number;
    players: Player[];
    lastAction?: {
        playerId: string;
        action: string;
        amount?: number;
    };
}
export interface BotDecision {
    action: GameAction;
    amount?: number;
    reasoning?: string;
}
export type GameStateCallback = (state: GameState | any) => void;
//# sourceMappingURL=types.d.ts.map
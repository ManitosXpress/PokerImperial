/**
 * Shared type definitions for poker game controllers
 * These types are used by both Practice and Real Money game modes
 */

export enum GameStateEnum {
    WaitingForPlayers = 'waiting',
    PostingBlinds = 'posting_blinds',
    PreFlop = 'pre-flop',
    Flop = 'flop',
    Turn = 'turn',
    River = 'river',
    Showdown = 'showdown'
}

export enum GameAction {
    Fold = 'fold',
    Check = 'check',
    Call = 'call',
    Bet = 'bet',
    Raise = 'raise',
    AllIn = 'allin'
}

export interface Card {
    rank: string; // '2'-'9', 'T', 'J', 'Q', 'K', 'A'
    suit: string; // 'h', 'd', 'c', 's'
    toString(): string; // e.g., "Ah" for Ace of Hearts
}

export interface Player {
    id: string;
    name: string;
    chips: number;
    hand?: string[]; // Array of card strings like ["Ah", "Kd"]
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
    description: string; // e.g., "Side pot (Player A vs Player B)"
}

export interface WinnerInfo {
    playerId: string;
    playerName: string;
    amount: number;
    handRank: string; // e.g., "Royal Flush", "Two Pair"
    handDescription: string; // e.g., "Two Pair, Aces and Kings"
    potType: 'main' | 'side'; // Which pot did they win
}

export interface HandResult {
    playerId: string;
    hand: any; // pokersolver Hand object
    rank: number;
    description: string;
}

export interface GameState {
    pot: number;
    communityCards: string[];
    currentTurn: string | null; // Player ID whose turn it is
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
    reasoning?: string; // For debugging
}

export type GameStateCallback = (state: GameState | any) => void;

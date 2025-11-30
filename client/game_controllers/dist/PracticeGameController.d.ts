/**
 * PracticeGameController - Client-side game controller for practice mode
 *
 * CRITICAL: This file has ZERO Firebase imports and does NOT touch real credits
 * All game state is managed in memory and resets on page refresh
 *
 * Features:
 * - Local in-memory game state
 * - Demo balance (10,000 chips per player)
 * - Automatic bot players
 * - Full Texas Hold'em rules via FSM
 * - Side pot and split pot support
 * - Intelligent bot AI
 */
import { IPokerGameController } from './IPokerGameController';
import { Player, GameState, GameAction, GameStateCallback } from './types';
export declare class PracticeGameController implements IPokerGameController {
    private userId;
    private userName;
    private players;
    private deck;
    private stateMachine;
    private communityCards;
    private pot;
    private currentBet;
    private currentTurnIndex;
    private dealerIndex;
    private smallBlindAmount;
    private bigBlindAmount;
    private readonly DEMO_STARTING_CHIPS;
    onGameStateChange?: GameStateCallback;
    private botTimeout?;
    constructor(userId: string, userName: string);
    /**
     * Start a new practice game
     * Automatically adds bots to fill the table
     */
    startGame(players: Player[]): void;
    /**
     * Start a new hand
     */
    private startNewHand;
    /**
     * Post small and big blinds
     */
    private postBlinds;
    /**
     * Handle a player action
     */
    handleAction(playerId: string, action: GameAction | string, amount?: number): void;
    /**
     * Process a player's action
     * Returns whether the action was aggressive (bet/raise)
     */
    private processAction;
    /**
     * Place a bet for a player
     */
    private placeBet;
    /**
     * Advance the game after an action
     */
    private advanceGame;
    /**
     * Move to next player's turn
     */
    private startNextTurn;
    /**
     * Schedule a bot's turn with thinking delay
     */
    private scheduleBotTurn;
    /**
     * Handle a bot's turn
     */
    private handleBotTurn;
    /**
     * Advance to next betting round (flop, turn, river, or showdown)
     */
    private advanceToNextRound;
    /**
     * Skip directly to showdown (for all-in scenarios)
     */
    private skipToShowdown;
    /**
     * Handle showdown - determine winners and distribute pot
     */
    private handleShowdown;
    /**
     * Handle single winner (everyone else folded)
     */
    private handleSingleWinner;
    /**
     * Get current game state
     */
    getGameState(): GameState;
    /**
     * Add chips to a player (for practice mode, just adds to demo balance)
     */
    addChips(playerId: string, amount: number): void;
    /**
     * Emit game state to subscribers
     */
    private emitGameState;
    /**
     * Initialize a fresh deck
     */
    private initializeDeck;
    /**
     * Shuffle the deck
     */
    private shuffleDeck;
    /**
     * Deal cards from the deck
     */
    private dealCards;
    /**
     * Clean up resources
     */
    destroy(): void;
}
//# sourceMappingURL=PracticeGameController.d.ts.map
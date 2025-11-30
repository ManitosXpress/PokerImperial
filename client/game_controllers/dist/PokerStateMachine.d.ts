/**
 * PokerStateMachine - Finite State Machine for Texas Hold'em game flow
 * Manages state transitions and betting round completion logic
 */
import { Player, GameStateEnum } from './types';
export interface BettingRoundState {
    lastAggressorIndex: number;
    playersActed: Set<string>;
    bettingComplete: boolean;
}
export declare class PokerStateMachine {
    private currentState;
    private bettingState;
    constructor();
    /**
     * Get the current state
     */
    getState(): GameStateEnum;
    /**
     * Transition to a new state
     * Validates that the transition is legal
     */
    transition(newState: GameStateEnum): boolean;
    /**
     * Check if a state transition is valid
     */
    private isValidTransition;
    /**
     * Check if current state is a betting round
     */
    private isBettingRound;
    /**
     * Reset betting round state
     */
    resetBettingRound(): void;
    /**
     * Record that a player has acted
     */
    recordPlayerAction(playerId: string, isAggressive: boolean, playerIndex: number): void;
    /**
     * Set the initial aggressor (usually big blind in pre-flop)
     */
    setInitialAggressor(playerIndex: number): void;
    /**
     * Check if betting round is complete
     * Betting is complete when:
     * 1. All active players have acted
     * 2. All active players have matching bets (or are all-in)
     * 3. Action has returned to the last aggressor (or past them)
     */
    isBettingRoundComplete(activePlayers: Player[], currentPlayerIndex: number, currentBet: number): boolean;
    /**
     * Determine if we should skip to showdown (all-in scenario)
     * This happens when there's only one or zero players with chips left
     */
    shouldSkipToShowdown(activePlayers: Player[]): boolean;
    /**
     * Get the next state in the normal game flow
     */
    getNextNormalState(): GameStateEnum | null;
    /**
     * Reset the state machine for a new hand
     */
    reset(): void;
    /**
     * Get betting round information
     */
    getBettingState(): BettingRoundState;
}
//# sourceMappingURL=PokerStateMachine.d.ts.map
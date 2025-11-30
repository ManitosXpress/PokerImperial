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

export class PokerStateMachine {
    private currentState: GameStateEnum = GameStateEnum.WaitingForPlayers;
    private bettingState: BettingRoundState = {
        lastAggressorIndex: 0,
        playersActed: new Set(),
        bettingComplete: false
    };

    constructor() { }

    /**
     * Get the current state
     */
    getState(): GameStateEnum {
        return this.currentState;
    }

    /**
     * Transition to a new state
     * Validates that the transition is legal
     */
    transition(newState: GameStateEnum): boolean {
        if (!this.isValidTransition(this.currentState, newState)) {
            console.error(`Invalid transition from ${this.currentState} to ${newState}`);
            return false;
        }

        console.log(`State transition: ${this.currentState} → ${newState}`);
        this.currentState = newState;

        // Reset betting state on new betting round
        if (this.isBettingRound(newState)) {
            this.resetBettingRound();
        }

        return true;
    }

    /**
     * Check if a state transition is valid
     */
    private isValidTransition(from: GameStateEnum, to: GameStateEnum): boolean {
        const validTransitions: { [key in GameStateEnum]: GameStateEnum[] } = {
            [GameStateEnum.WaitingForPlayers]: [GameStateEnum.PostingBlinds],
            [GameStateEnum.PostingBlinds]: [GameStateEnum.PreFlop],
            [GameStateEnum.PreFlop]: [GameStateEnum.Flop, GameStateEnum.Showdown],
            [GameStateEnum.Flop]: [GameStateEnum.Turn, GameStateEnum.Showdown],
            [GameStateEnum.Turn]: [GameStateEnum.River, GameStateEnum.Showdown],
            [GameStateEnum.River]: [GameStateEnum.Showdown],
            [GameStateEnum.Showdown]: [GameStateEnum.WaitingForPlayers, GameStateEnum.PostingBlinds]
        };

        return validTransitions[from]?.includes(to) || false;
    }

    /**
     * Check if current state is a betting round
     */
    private isBettingRound(state: GameStateEnum): boolean {
        return [
            GameStateEnum.PreFlop,
            GameStateEnum.Flop,
            GameStateEnum.Turn,
            GameStateEnum.River
        ].includes(state);
    }

    /**
     * Reset betting round state
     */
    resetBettingRound(): void {
        this.bettingState = {
            lastAggressorIndex: 0,
            playersActed: new Set(),
            bettingComplete: false
        };
    }

    /**
     * Record that a player has acted
     */
    recordPlayerAction(playerId: string, isAggressive: boolean, playerIndex: number): void {
        this.bettingState.playersActed.add(playerId);
        if (isAggressive) {
            this.bettingState.lastAggressorIndex = playerIndex;
        }
    }

    /**
     * Set the initial aggressor (usually big blind in pre-flop)
     */
    setInitialAggressor(playerIndex: number): void {
        this.bettingState.lastAggressorIndex = playerIndex;
    }

    /**
     * Check if betting round is complete
     * Betting is complete when:
     * 1. All active players have acted
     * 2. All active players have matching bets (or are all-in)
     * 3. Action has returned to the last aggressor (or past them)
     */
    isBettingRoundComplete(
        activePlayers: Player[],
        currentPlayerIndex: number,
        currentBet: number
    ): boolean {
        const activeNonFolded = activePlayers.filter(p => !p.isFolded);

        // Only one player left - betting complete
        if (activeNonFolded.length <= 1) {
            return true;
        }

        // Check if all players with chips have acted
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);
        const allWithChipsActed = playersWithChips.every(p =>
            this.bettingState.playersActed.has(p.id)
        );

        if (!allWithChipsActed) {
            return false;
        }

        // Check if all bets are matched (or players are all-in)
        const allBetsMatched = activeNonFolded.every(p =>
            p.currentBet === currentBet || p.chips === 0
        );

        if (!allBetsMatched) {
            return false;
        }

        // Check if we've returned to the last aggressor
        // If current player is or has passed the aggressor, round is complete
        const aggressorPlayer = activePlayers[this.bettingState.lastAggressorIndex];
        if (aggressorPlayer && this.bettingState.playersActed.has(aggressorPlayer.id)) {
            return true;
        }

        return false;
    }

    /**
     * Determine if we should skip to showdown (all-in scenario)
     * This happens when there's only one or zero players with chips left
     */
    shouldSkipToShowdown(activePlayers: Player[]): boolean {
        const activeNonFolded = activePlayers.filter(p => !p.isFolded);
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);
        return playersWithChips.length <= 1;
    }

    /**
     * Get the next state in the normal game flow
     */
    getNextNormalState(): GameStateEnum | null {
        const stateFlow: { [key in GameStateEnum]?: GameStateEnum } = {
            [GameStateEnum.PostingBlinds]: GameStateEnum.PreFlop,
            [GameStateEnum.PreFlop]: GameStateEnum.Flop,
            [GameStateEnum.Flop]: GameStateEnum.Turn,
            [GameStateEnum.Turn]: GameStateEnum.River,
            [GameStateEnum.River]: GameStateEnum.Showdown
        };

        return stateFlow[this.currentState] || null;
    }

    /**
     * Reset the state machine for a new hand
     */
    reset(): void {
        this.currentState = GameStateEnum.WaitingForPlayers;
        this.resetBettingRound();
    }

    /**
     * Get betting round information
     */
    getBettingState(): BettingRoundState {
        return this.bettingState;
    }
}

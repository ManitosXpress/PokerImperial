/**
 * Interface for Poker Game Controllers
 * Defines the contract that both PracticeGameController and RealMoneyGameController must follow
 * This enables the Strategy Pattern for separating practice mode from real money mode
 */
import { Player, GameState, GameAction, GameStateCallback } from './types';
export interface IPokerGameController {
    /**
     * Start a new game with the given players
     * @param players Array of players participating in the game
     */
    startGame(players: Player[]): void;
    /**
     * Handle a player action (fold, check, call, bet, raise, all-in)
     * @param playerId ID of the player taking the action
     * @param action The action being taken
     * @param amount Optional bet/raise amount
     */
    handleAction(playerId: string, action: GameAction | string, amount?: number): void;
    /**
     * Get the current state of the game
     * @returns Current game state including pot, cards, players, etc.
     */
    getGameState(): GameState;
    /**
     * Add chips to a player's stack (for top-ups)
     * @param playerId ID of the player
     * @param amount Number of chips to add
     */
    addChips(playerId: string, amount: number): void;
    /**
     * Callback function that gets called whenever the game state changes
     * UI components should subscribe to this to update the display
     */
    onGameStateChange?: GameStateCallback;
    /**
     * Clean up resources when the game is destroyed
     */
    destroy?(): void;
}
//# sourceMappingURL=IPokerGameController.d.ts.map
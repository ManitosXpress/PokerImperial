/**
 * GameControllerFactory - Factory pattern for creating game controllers
 * Instantiates the appropriate controller based on game mode
 */

import { IPokerGameController } from './IPokerGameController';
import { PracticeGameController } from './PracticeGameController';
import { Player } from './types';

export type GameMode = 'practice' | 'real';

export class GameControllerFactory {
    /**
     * Create a game controller based on mode
     * @param mode 'practice' for offline practice mode, 'real' for online with real money
     * @param userId User ID
     * @param userName User display name
     * @returns Appropriate controller instance
     */
    static createController(
        mode: GameMode,
        userId: string,
        userName: string
    ): IPokerGameController {
        console.log(`🏭 Creating ${mode} mode controller for ${userName}`);

        if (mode === 'practice') {
            return new PracticeGameController(userId, userName);
        } else {
            // RealMoneyGameController not implemented yet
            // This would connect to the server-side game via WebSocket
            throw new Error('Real money mode not yet implemented. Use practice mode for now.');
        }
    }

    /**
     * Create a practice game with bots
     * Convenience method that creates controller and starts game immediately
     */
    static createPracticeGame(userId: string, userName: string): IPokerGameController {
        const controller = new PracticeGameController(userId, userName);

        // Create the human player
        const humanPlayer: Player = {
            id: userId,
            name: userName,
            chips: 0, // Will be set by controller
            currentBet: 0,
            isFolded: false,
            isBot: false
        };

        // Start game (controller will add bots automatically)
        controller.startGame([humanPlayer]);

        return controller;
    }
}

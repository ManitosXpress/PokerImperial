/**
 * GameControllerFactory - Factory pattern for creating game controllers
 * Instantiates the appropriate controller based on game mode
 */
import { IPokerGameController } from './IPokerGameController';
export type GameMode = 'practice' | 'real';
export declare class GameControllerFactory {
    /**
     * Create a game controller based on mode
     * @param mode 'practice' for offline practice mode, 'real' for online with real money
     * @param userId User ID
     * @param userName User display name
     * @returns Appropriate controller instance
     */
    static createController(mode: GameMode, userId: string, userName: string): IPokerGameController;
    /**
     * Create a practice game with bots
     * Convenience method that creates controller and starts game immediately
     */
    static createPracticeGame(userId: string, userName: string): IPokerGameController;
}
//# sourceMappingURL=GameControllerFactory.d.ts.map
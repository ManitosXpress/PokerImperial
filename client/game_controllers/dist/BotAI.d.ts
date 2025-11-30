/**
 * BotAI - Intelligent bot decision-making for practice mode
 * Makes decisions based on hand strength, position, pot odds, and random variation
 */
import { Player, GameState, BotDecision } from './types';
export declare class BotAI {
    private static readonly BOT_NAMES;
    private static usedNames;
    /**
     * Get a random bot name that hasn't been used yet
     */
    static getRandomBotName(): string;
    /**
     * Main decision-making function for bots
     * @param bot The bot player making the decision
     * @param gameState Current game state
     * @returns Bot's decision with action and optional amount
     */
    static decide(bot: Player, gameState: GameState): BotDecision;
    /**
     * Evaluate hand strength on a scale of 0-100
     */
    private static evaluateHandStrength;
    /**
     * Evaluate pre-flop hand strength based on hole cards
     */
    private static evaluatePreFlopStrength;
    /**
     * Convert pokersolver hand rank to strength value
     */
    private static convertHandRankToStrength;
    /**
     * Get position factor (0-1, where 1 is best position)
     */
    private static getPositionFactor;
    /**
     * Calculate pot odds (percentage of pot that call represents)
     */
    private static calculatePotOdds;
    /**
     * Decide whether to check or bet when there's no current bet
     */
    private static decideWhenNoBet;
    /**
     * Make decision when facing a bet
     */
    private static makeDecision;
    /**
     * Get random thinking delay in milliseconds (1-3 seconds)
     */
    static getThinkingDelay(): number;
}
//# sourceMappingURL=BotAI.d.ts.map
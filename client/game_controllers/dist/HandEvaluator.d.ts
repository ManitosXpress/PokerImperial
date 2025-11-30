/**
 * HandEvaluator - Evaluates poker hands and determines winners
 * Handles complex scenarios like side pots, split pots, and multiple all-ins
 */
import { Player, PotStructure, WinnerInfo, HandResult } from './types';
export declare class HandEvaluator {
    /**
     * Calculate pot structure including main pot and side pots
     * This handles scenarios where players go all-in with different amounts
     */
    static calculatePots(players: Player[]): PotStructure;
    /**
     * Evaluate hands for all active players
     */
    static evaluateHands(players: Player[], communityCards: string[]): HandResult[];
    /**
     * Determine winners for main pot and all side pots
     * Handles split pots when multiple players tie
     */
    static determineWinners(players: Player[], communityCards: string[], potStructure: PotStructure, rakePercentage?: number): WinnerInfo[];
    /**
     * Simple winner evaluation for single pot (no side pots)
     * Used when all players have equal or sufficient chips
     */
    static evaluateSimpleWinner(players: Player[], communityCards: string[], totalPot: number, rakePercentage?: number): WinnerInfo[];
}
//# sourceMappingURL=HandEvaluator.d.ts.map
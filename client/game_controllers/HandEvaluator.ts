/**
 * HandEvaluator - Evaluates poker hands and determines winners
 * Handles complex scenarios like side pots, split pots, and multiple all-ins
 */

import { Player, PotStructure, SidePot, WinnerInfo, HandResult } from './types';

// Using pokersolver library for hand evaluation
// @ts-ignore
const Hand = require('pokersolver').Hand;

export class HandEvaluator {
    /**
     * Calculate pot structure including main pot and side pots
     * This handles scenarios where players go all-in with different amounts
     */
    static calculatePots(players: Player[]): PotStructure {
        const activePlayers = players.filter(p => !p.isFolded);

        if (activePlayers.length === 0) {
            return { mainPot: 0, sidePots: [], totalPot: 0 };
        }

        // Create contribution array: [{ playerId, contribution, chips }]
        const contributions = activePlayers.map(p => ({
            playerId: p.id,
            contribution: p.currentBet,
            remainingChips: p.chips
        })).sort((a, b) => a.contribution - b.contribution);

        const pots: { amount: number; eligiblePlayerIds: string[] }[] = [];
        let previousLevel = 0;

        // Build pots from smallest contribution to largest
        for (let i = 0; i < contributions.length; i++) {
            const currentLevel = contributions[i].contribution;

            if (currentLevel > previousLevel) {
                // Calculate pot amount for this level
                const eligiblePlayers = contributions.slice(i).map(c => c.playerId);
                const potAmount = (currentLevel - previousLevel) * eligiblePlayers.length;

                if (potAmount > 0) {
                    pots.push({
                        amount: potAmount,
                        eligiblePlayerIds: eligiblePlayers
                    });
                }

                previousLevel = currentLevel;
            }
        }

        // First pot is main pot, rest are side pots
        const mainPot = pots.length > 0 ? pots[0].amount : 0;
        const sidePots: SidePot[] = pots.slice(1).map((pot, idx) => ({
            amount: pot.amount,
            eligiblePlayerIds: pot.eligiblePlayerIds,
            description: `Side pot ${idx + 1}`
        }));

        const totalPot = pots.reduce((sum, pot) => sum + pot.amount, 0);

        return { mainPot, sidePots, totalPot };
    }

    /**
     * Evaluate hands for all active players
     */
    static evaluateHands(players: Player[], communityCards: string[]): HandResult[] {
        const activePlayers = players.filter(p => !p.isFolded && p.hand && p.hand.length > 0);

        return activePlayers.map(player => {
            const hand = Hand.solve([...player.hand!, ...communityCards]);
            return {
                playerId: player.id,
                hand: hand,
                rank: hand.rank,
                description: hand.descr
            };
        });
    }

    /**
     * Determine winners for main pot and all side pots
     * Handles split pots when multiple players tie
     */
    static determineWinners(
        players: Player[],
        communityCards: string[],
        potStructure: PotStructure,
        rakePercentage: number = 0.10
    ): WinnerInfo[] {
        const handResults = this.evaluateHands(players, communityCards);
        const winners: WinnerInfo[] = [];

        // Helper function to find winners for a specific pot
        const findWinnersForPot = (eligiblePlayerIds: string[], potAmount: number, potType: 'main' | 'side'): WinnerInfo[] => {
            const eligibleResults = handResults.filter(hr => eligiblePlayerIds.includes(hr.playerId));

            if (eligibleResults.length === 0) return [];
            if (eligibleResults.length === 1) {
                const player = players.find(p => p.id === eligibleResults[0].playerId)!;
                const rake = Math.floor(potAmount * rakePercentage);
                const winAmount = potAmount - rake;

                // Track rake
                player.totalRakePaid = (player.totalRakePaid || 0) + rake;

                return [{
                    playerId: eligibleResults[0].playerId,
                    playerName: player.name,
                    amount: winAmount,
                    handRank: eligibleResults[0].description,
                    handDescription: eligibleResults[0].hand.toString(),
                    potType
                }];
            }

            // Find best hand(s) among eligible players
            const hands = eligibleResults.map(hr => hr.hand);
            const winningHands = Hand.winners(hands);
            const winningResults = eligibleResults.filter(hr => winningHands.includes(hr.hand));

            // Calculate rake and split amount
            const rake = Math.floor(potAmount * rakePercentage);
            const amountAfterRake = potAmount - rake;
            const splitAmount = Math.floor(amountAfterRake / winningResults.length);
            const rakePerWinner = Math.floor(rake / winningResults.length);

            return winningResults.map(wr => {
                const player = players.find(p => p.id === wr.playerId)!;
                player.totalRakePaid = (player.totalRakePaid || 0) + rakePerWinner;

                return {
                    playerId: wr.playerId,
                    playerName: player.name,
                    amount: splitAmount,
                    handRank: wr.description,
                    handDescription: wr.hand.toString(),
                    potType
                };
            });
        };

        // Evaluate main pot
        if (potStructure.mainPot > 0) {
            const mainPotEligible = players.filter(p => !p.isFolded).map(p => p.id);
            const mainPotWinners = findWinnersForPot(mainPotEligible, potStructure.mainPot, 'main');
            winners.push(...mainPotWinners);
        }

        // Evaluate each side pot
        potStructure.sidePots.forEach((sidePot, idx) => {
            const sidePotWinners = findWinnersForPot(sidePot.eligiblePlayerIds, sidePot.amount, 'side');
            winners.push(...sidePotWinners);
        });

        return winners;
    }

    /**
     * Simple winner evaluation for single pot (no side pots)
     * Used when all players have equal or sufficient chips
     */
    static evaluateSimpleWinner(
        players: Player[],
        communityCards: string[],
        totalPot: number,
        rakePercentage: number = 0.10
    ): WinnerInfo[] {
        const handResults = this.evaluateHands(players, communityCards);

        if (handResults.length === 0) return [];
        if (handResults.length === 1) {
            const player = players.find(p => p.id === handResults[0].playerId)!;
            const rake = Math.floor(totalPot * rakePercentage);
            const winAmount = totalPot - rake;

            player.totalRakePaid = (player.totalRakePaid || 0) + rake;

            return [{
                playerId: handResults[0].playerId,
                playerName: player.name,
                amount: winAmount,
                handRank: handResults[0].description,
                handDescription: handResults[0].hand.toString(),
                potType: 'main'
            }];
        }

        // Multiple players - find winner(s)
        const hands = handResults.map(hr => hr.hand);
        const winningHands = Hand.winners(hands);
        const winningResults = handResults.filter(hr => winningHands.includes(hr.hand));

        // Calculate split
        const rake = Math.floor(totalPot * rakePercentage);
        const amountAfterRake = totalPot - rake;
        const splitAmount = Math.floor(amountAfterRake / winningResults.length);
        const rakePerWinner = Math.floor(rake / winningResults.length);

        return winningResults.map(wr => {
            const player = players.find(p => p.id === wr.playerId)!;
            player.totalRakePaid = (player.totalRakePaid || 0) + rakePerWinner;

            return {
                playerId: wr.playerId,
                playerName: player.name,
                amount: splitAmount,
                handRank: wr.description,
                handDescription: wr.hand.toString(),
                potType: 'main'
            };
        });
    }
}

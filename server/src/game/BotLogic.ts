import { Player } from '../types';
const Hand = require('pokersolver').Hand;

export class BotLogic {
    static decide(bot: Player, currentBet: number, pot: number, communityCards: string[] = []): 'fold' | 'call' | 'bet' | 'check' | 'raise' {
        try {
            const botHand = bot.hand || [];
            // Basic Pre-flop Logic
            if (communityCards.length === 0) {
                return this.decidePreFlop(botHand, currentBet, bot);
            }

            // Post-flop Logic using pokersolver
            const allCards = [...botHand, ...communityCards];
            const solvedHand = Hand.solve(allCards);
            const rank = solvedHand.rank; // 1=High Card, 2=Pair, etc.

            const callAmount = currentBet - bot.currentBet;

            // If checking is free and we have nothing, just check
            if (callAmount === 0) return 'check';

            // Decision based on Hand Rank
            // Rank 1: High Card, 2: Pair, 3: Two Pair, 4: Three of a Kind, 5: Straight, 6: Flush, 7: Full House, etc.

            // Strong Hand (Three of a Kind or better) -> Aggressive
            if (rank >= 4) {
                // Raise if possible, otherwise call/bet
                return 'bet';
            }

            // Medium Hand (Pair or Two Pair) -> Passive/Call
            if (rank >= 2) {
                return 'call';
            }

            // Weak Hand (High Card) -> Fold if bet is too high relative to pot?
            // For simplicity: Fold if there is a bet
            if (callAmount > 0) {
                // Bluff chance? 10%
                if (Math.random() < 0.1) return 'call';
                return 'fold';
            }

            return 'check';

        } catch (e) {
            console.error('BotLogic error:', e);
            return 'fold'; // Safety fallback
        }
    }

    private static decidePreFlop(hand: string[], currentBet: number, bot: Player): 'fold' | 'call' | 'bet' | 'check' {
        if (hand.length < 2) return 'fold';

        const c1 = hand[0];
        const c2 = hand[1];
        const r1 = c1.slice(0, -1);
        const r2 = c2.slice(0, -1);
        const s1 = c1.slice(-1);
        const s2 = c2.slice(-1);

        const isPair = r1 === r2;
        const isHighCard = ['A', 'K', 'Q', 'J', 'T'].includes(r1) || ['A', 'K', 'Q', 'J', 'T'].includes(r2);
        const isSuited = s1 === s2;

        const callAmount = currentBet - bot.currentBet;

        // Returns
        if (callAmount === 0) return 'check';

        // Always play pairs
        if (isPair) return 'call';

        // Play high cards
        if (isHighCard) return 'call';

        // Play suited connectors or suited highish?
        if (isSuited && Math.random() > 0.5) return 'call';

        // Fold trash
        return 'fold';
    }
}

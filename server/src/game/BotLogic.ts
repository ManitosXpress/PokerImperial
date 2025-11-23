import { Player } from '../types';

export class BotLogic {
    static decide(bot: Player, currentBet: number, pot: number): 'fold' | 'call' | 'bet' | 'check' {
        // Very simple logic for now
        const callAmount = currentBet - bot.currentBet;

        // If no bet to call, just check
        if (callAmount === 0) return 'check';

        // Random decision based on "strength" (random for now)
        const random = Math.random();

        if (random > 0.8) {
            return 'bet'; // Aggressive
        } else if (random > 0.3) {
            return 'call'; // Passive
        } else {
            return 'fold'; // Weak
        }
    }
}

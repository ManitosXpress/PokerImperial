"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BotLogic = void 0;
class BotLogic {
    static decide(bot, currentBet, pot) {
        // Very simple logic for now
        const callAmount = currentBet - bot.currentBet;
        // If no bet to call, just check
        if (callAmount === 0)
            return 'check';
        // Random decision based on "strength" (random for now)
        const random = Math.random();
        if (random > 0.8) {
            return 'bet'; // Aggressive
        }
        else if (random > 0.3) {
            return 'call'; // Passive
        }
        else {
            return 'fold'; // Weak
        }
    }
}
exports.BotLogic = BotLogic;

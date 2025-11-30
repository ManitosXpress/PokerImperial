/**
 * BotAI - Intelligent bot decision-making for practice mode
 * Makes decisions based on hand strength, position, pot odds, and random variation
 */
import { GameAction } from './types';
// @ts-ignore
const Hand = require('pokersolver').Hand;
export class BotAI {
    /**
     * Get a random bot name that hasn't been used yet
     */
    static getRandomBotName() {
        const availableNames = this.BOT_NAMES.filter(name => !this.usedNames.has(name));
        if (availableNames.length === 0) {
            // Reset if we've used all names
            this.usedNames.clear();
            return this.BOT_NAMES[Math.floor(Math.random() * this.BOT_NAMES.length)];
        }
        const name = availableNames[Math.floor(Math.random() * availableNames.length)];
        this.usedNames.add(name);
        return name;
    }
    /**
     * Main decision-making function for bots
     * @param bot The bot player making the decision
     * @param gameState Current game state
     * @returns Bot's decision with action and optional amount
     */
    static decide(bot, gameState) {
        const callAmount = gameState.currentBet - bot.currentBet;
        const potOdds = this.calculatePotOdds(callAmount, gameState.pot);
        // If no bet to call, decide between check and bet
        if (callAmount === 0) {
            return this.decideWhenNoBet(bot, gameState);
        }
        // Evaluate hand strength
        const handStrength = this.evaluateHandStrength(bot.hand || [], gameState.communityCards, gameState.round);
        // Get position factor (earlier position = more cautious)
        const position = this.getPositionFactor(bot.id, gameState);
        // Make decision based on hand strength and other factors
        return this.makeDecision(bot, gameState, handStrength, position, callAmount, potOdds);
    }
    /**
     * Evaluate hand strength on a scale of 0-100
     */
    static evaluateHandStrength(holeCards, communityCards, round) {
        if (!holeCards || holeCards.length < 2)
            return 0;
        // Pre-flop hand strength evaluation
        if (round === 'pre-flop' || communityCards.length === 0) {
            return this.evaluatePreFlopStrength(holeCards);
        }
        // Post-flop: use pokersolver to evaluate current hand
        try {
            const hand = Hand.solve([...holeCards, ...communityCards]);
            return this.convertHandRankToStrength(hand.rank, hand.descr);
        }
        catch (e) {
            return 30; // Default medium strength on error
        }
    }
    /**
     * Evaluate pre-flop hand strength based on hole cards
     */
    static evaluatePreFlopStrength(holeCards) {
        if (holeCards.length < 2)
            return 0;
        const [card1, card2] = holeCards;
        const rank1 = card1.charAt(0);
        const rank2 = card2.charAt(0);
        const suit1 = card1.charAt(1);
        const suit2 = card2.charAt(1);
        const suited = suit1 === suit2;
        const rankValues = {
            '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
            'T': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14
        };
        const val1 = rankValues[rank1] || 0;
        const val2 = rankValues[rank2] || 0;
        const isPair = val1 === val2;
        const highCard = Math.max(val1, val2);
        const lowCard = Math.min(val1, val2);
        // Premium pairs
        if (isPair && highCard >= 13)
            return 95; // AA, KK
        if (isPair && highCard >= 11)
            return 85; // QQ, JJ
        if (isPair && highCard >= 9)
            return 75; // TT, 99
        if (isPair)
            return 60 + highCard * 2; // Other pairs
        // Premium non-pairs
        if (highCard === 14 && lowCard >= 12)
            return 90; // AK, AQ
        if (highCard === 14 && lowCard >= 10)
            return suited ? 80 : 70; // AJ, AT
        if (highCard === 13 && lowCard >= 11)
            return suited ? 75 : 65; // KQ, KJ
        // Suited connectors and high cards
        if (suited && Math.abs(val1 - val2) === 1)
            return 60; // Suited connectors
        if (suited && highCard >= 11)
            return 55; // Suited with face card
        if (highCard >= 12)
            return 50; // Any face card
        // Connected cards
        if (Math.abs(val1 - val2) === 1)
            return 45;
        // Default based on high card
        return 20 + highCard * 2;
    }
    /**
     * Convert pokersolver hand rank to strength value
     */
    static convertHandRankToStrength(rank, description) {
        // pokersolver ranks: 1 (high card) to 9 (straight flush/royal flush)
        const rankStrength = {
            1: 20, // High Card
            2: 35, // Pair
            3: 50, // Two Pair
            4: 65, // Three of a Kind
            5: 75, // Straight
            6: 80, // Flush
            7: 90, // Full House
            8: 95, // Four of a Kind
            9: 100 // Straight Flush / Royal Flush
        };
        return rankStrength[rank] || 30;
    }
    /**
     * Get position factor (0-1, where 1 is best position)
     */
    static getPositionFactor(botId, gameState) {
        const activePlayers = gameState.players.filter(p => !p.isFolded);
        const dealerIndex = gameState.players.findIndex(p => p.id === gameState.dealerId);
        const botIndex = gameState.players.findIndex(p => p.id === botId);
        if (dealerIndex === -1 || botIndex === -1)
            return 0.5;
        // Calculate position relative to dealer (0 = earliest, 1 = button/latest)
        const relativePosition = (botIndex - dealerIndex + gameState.players.length) % gameState.players.length;
        return relativePosition / Math.max(activePlayers.length - 1, 1);
    }
    /**
     * Calculate pot odds (percentage of pot that call represents)
     */
    static calculatePotOdds(callAmount, pot) {
        if (pot === 0)
            return 1;
        return callAmount / (pot + callAmount);
    }
    /**
     * Decide whether to check or bet when there's no current bet
     */
    static decideWhenNoBet(bot, gameState) {
        const handStrength = this.evaluateHandStrength(bot.hand || [], gameState.communityCards, gameState.round);
        const random = Math.random();
        // Very strong hand: bet aggressively
        if (handStrength >= 85) {
            if (random > 0.2) { // 80% bet
                const betAmount = Math.min(Math.floor(gameState.pot * 0.75 + gameState.currentBet), bot.chips + bot.currentBet);
                return { action: GameAction.Bet, amount: betAmount, reasoning: 'Strong hand, betting' };
            }
            return { action: GameAction.Check, reasoning: 'Strong hand, slow playing' };
        }
        // Strong hand: bet sometimes
        if (handStrength >= 65) {
            if (random > 0.5) { // 50% bet
                const betAmount = Math.min(Math.floor(gameState.pot * 0.5 + gameState.currentBet), bot.chips + bot.currentBet);
                return { action: GameAction.Bet, amount: betAmount, reasoning: 'Good hand, betting' };
            }
            return { action: GameAction.Check, reasoning: 'Good hand, checking' };
        }
        // Medium or weak hand: mostly check
        if (random > 0.85) { // 15% bluff bet
            const betAmount = Math.min(Math.floor(gameState.pot * 0.3 + gameState.currentBet), bot.chips + bot.currentBet);
            return { action: GameAction.Bet, amount: betAmount, reasoning: 'Bluffing' };
        }
        return { action: GameAction.Check, reasoning: 'Medium/weak hand' };
    }
    /**
     * Make decision when facing a bet
     */
    static makeDecision(bot, gameState, handStrength, position, callAmount, potOdds) {
        const random = Math.random();
        const chipsLeft = bot.chips;
        // If call amount >= all chips, forced to go all-in or fold
        if (callAmount >= chipsLeft) {
            if (handStrength >= 75 || (handStrength >= 60 && random > 0.6)) {
                return { action: GameAction.AllIn, reasoning: 'Strong hand, all-in' };
            }
            return { action: GameAction.Fold, reasoning: 'Cannot afford call' };
        }
        // Premium hands (85+): Raise or call aggressively
        if (handStrength >= 85) {
            if (random > 0.3) { // 70% raise
                const raiseAmount = Math.min(gameState.currentBet + Math.floor(gameState.pot * 0.5), bot.currentBet + chipsLeft);
                return { action: GameAction.Bet, amount: raiseAmount, reasoning: 'Premium hand, raising' };
            }
            return { action: GameAction.Call, reasoning: 'Premium hand, calling' };
        }
        // Strong hands (65-84): Often call, sometimes raise
        if (handStrength >= 65) {
            if (random > 0.7 && position > 0.6) { // 30% raise with good position
                const raiseAmount = Math.min(gameState.currentBet + Math.floor(gameState.pot * 0.3), bot.currentBet + chipsLeft);
                return { action: GameAction.Bet, amount: raiseAmount, reasoning: 'Strong hand, raising' };
            }
            if (random > 0.2) { // 80% call
                return { action: GameAction.Call, reasoning: 'Strong hand, calling' };
            }
            return { action: GameAction.Fold, reasoning: 'Strong hand, folding (rare)' };
        }
        // Medium hands (45-64): Call if pot odds are good
        if (handStrength >= 45) {
            if (potOdds < 0.3 && random > 0.4) { // Good pot odds, 60% call
                return { action: GameAction.Call, reasoning: 'Medium hand, good pot odds' };
            }
            if (random > 0.7) { // 30% call anyway
                return { action: GameAction.Call, reasoning: 'Medium hand, calling' };
            }
            return { action: GameAction.Fold, reasoning: 'Medium hand, bad odds' };
        }
        // Weak hands (30-44): Rarely call, mostly fold
        if (handStrength >= 30) {
            if (potOdds < 0.2 && random > 0.7) { // Very good odds, 30% call
                return { action: GameAction.Call, reasoning: 'Weak hand, very good odds' };
            }
            return { action: GameAction.Fold, reasoning: 'Weak hand, folding' };
        }
        // Very weak hands (<30): Almost always fold
        if (random > 0.95) { // 5% bluff call
            return { action: GameAction.Call, reasoning: 'Very weak hand, bluffing' };
        }
        return { action: GameAction.Fold, reasoning: 'Very weak hand' };
    }
    /**
     * Get random thinking delay in milliseconds (1-3 seconds)
     */
    static getThinkingDelay() {
        return 1000 + Math.random() * 2000;
    }
}
// Pool of realistic bot names
BotAI.BOT_NAMES = [
    'Alex Chen', 'Maria Garcia', 'James Wilson', 'Sophie Laurent',
    'Raj Patel', 'Emma Thompson', 'Lucas Silva', 'Nina Kowalski',
    'Omar Hassan', 'Yuki Tanaka', 'Isabella Rossi', 'Carlos Mendez',
    'Fatima Ahmed', 'Viktor Petrov', 'Aisha Khan', 'Diego Torres',
    'Leila Abbasi', 'Marcus Johnson', 'Priya Sharma', 'Andre Dubois',
    'Zara Mohammed', 'Kenji Yoshida', 'Olivia Martin', 'Hassan Ali',
    'Chloe Nguyen', 'Dmitri Volkov', 'Jasmine Lee', 'Pablo Rivera',
    'Amara Nwosu', 'Felix Schmidt', 'Nadia Popov', 'Ryan O\'Brien',
    'Valentina Cruz', 'Arjun Reddy', 'Sophia Andersson', 'Ibrahim Diallo',
    'Mia Rodriguez', 'Luca Moretti', 'Zahra Mansour', 'Ethan Kim',
    'Camila Santos', 'Mohammed Farsi', 'Freya Hansen', 'Wei Zhang',
    'Lucia Fernandez', 'Nikita Sokolov', 'Aaliyah Jackson', 'Mateo Vargas',
    'Sakura Watanabe', 'Giovanni Ricci', 'Layla Hussein', 'Kai Müller'
];
BotAI.usedNames = new Set();
//# sourceMappingURL=BotAI.js.map
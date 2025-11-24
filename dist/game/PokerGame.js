"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PokerGame = void 0;
class PokerGame {
    constructor() {
        this.deck = [];
        this.players = [];
        this.pot = 0;
        this.initializeDeck();
    }
    initializeDeck() {
        const suits = ['H', 'D', 'C', 'S'];
        const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
        this.deck = [];
        for (const suit of suits) {
            for (const rank of ranks) {
                this.deck.push(rank + suit);
            }
        }
        this.shuffleDeck();
    }
    shuffleDeck() {
        for (let i = this.deck.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
        }
    }
    addPlayer(player) {
        this.players.push(player);
    }
    dealHand() {
        // Basic dealing logic stub
        return this.deck.splice(0, 2);
    }
}
exports.PokerGame = PokerGame;

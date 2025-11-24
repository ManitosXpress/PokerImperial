import { Player, Room } from '../types';
const Hand = require('pokersolver').Hand;

export class PokerGame {
    private deck: string[] = [];
    private pot: number = 0;
    private communityCards: string[] = [];
    private currentTurnIndex: number = 0;
    private dealerIndex: number = 0;
    private smallBlindAmount: number = 10;
    private bigBlindAmount: number = 20;
    private currentBet: number = 0;
    private round: 'pre-flop' | 'flop' | 'turn' | 'river' | 'showdown' = 'pre-flop';
    private players: Player[] = [];
    private activePlayers: Player[] = []; // Players currently in the hand
    private lastAggressorIndex: number = 0;

    constructor() { }

    public startGame(players: Player[]) {
        if (players.length < 2) throw new Error('Not enough players');
        this.players = players;
        this.activePlayers = [...players];
        this.dealerIndex = (this.dealerIndex + 1) % this.players.length;
        this.startRound();
    }

    private startRound() {
        this.initializeDeck();
        this.pot = 0;
        this.communityCards = [];
        this.round = 'pre-flop';
        this.currentBet = this.bigBlindAmount;

        // Reset player states for new round
        this.players.forEach(p => {
            p.hand = [];
            p.isFolded = false;
            p.currentBet = 0;
        });
        this.activePlayers = this.players.filter(p => p.chips > 0);

        // Deal cards
        this.activePlayers.forEach(p => {
            p.hand = this.deal(2);
        });

        // Blinds
        const sbIndex = (this.dealerIndex + 1) % this.activePlayers.length;
        const bbIndex = (this.dealerIndex + 2) % this.activePlayers.length;

        this.placeBet(this.activePlayers[sbIndex], this.smallBlindAmount);
        this.placeBet(this.activePlayers[bbIndex], this.bigBlindAmount);

        this.currentTurnIndex = (bbIndex + 1) % this.activePlayers.length;

        // In pre-flop, the BB is the initial "aggressor" that everyone must match.
        // If everyone calls, action returns to BB.
        this.lastAggressorIndex = bbIndex;
    }

    public getGameState() {
        return {
            pot: this.pot,
            communityCards: this.communityCards,
            currentTurn: this.activePlayers[this.currentTurnIndex]?.id,
            dealerId: this.players[this.dealerIndex]?.id,
            round: this.round,
            currentBet: this.currentBet,
            players: this.players.map(p => ({
                id: p.id,
                name: p.name,
                chips: p.chips,
                currentBet: p.currentBet,
                isFolded: p.isFolded,
                isBot: p.isBot,
                hand: p.hand
            }))
        };
    }

    public handleAction(playerId: string, action: 'bet' | 'call' | 'fold' | 'check', amount: number = 0) {
        const player = this.activePlayers[this.currentTurnIndex];
        if (!player || player.id !== playerId) {
            throw new Error('Not your turn');
        }

        switch (action) {
            case 'fold':
                player.isFolded = true;
                this.activePlayers = this.activePlayers.filter(p => !p.isFolded);
                if (this.activePlayers.length === 1) {
                    this.endHand(this.activePlayers[0]); // Winner by fold
                    return;
                }
                break;
            case 'call':
                const callAmount = this.currentBet - player.currentBet;
                this.placeBet(player, callAmount);
                break;
            case 'bet':
                if (amount < this.currentBet) throw new Error('Bet must be at least current bet');
                this.placeBet(player, amount - player.currentBet);
                if (amount > this.currentBet) {
                    this.lastAggressorIndex = this.currentTurnIndex;
                }
                this.currentBet = amount;
                break;
            case 'check':
                if (player.currentBet < this.currentBet) throw new Error('Cannot check, must call');
                break;
        }

        this.nextTurn();
    }

    private nextTurn() {
        // Check if round should end BEFORE moving to next player
        // Logic: If everyone remaining has matched the current bet, 
        // AND the next player to act would be the lastAggressor (meaning we completed the circle),
        // THEN the round is over.

        // Exception: Pre-flop BB option. 
        // If pre-flop, and next is BB, and BB has matched but NOT acted (checked/raised)?
        // We can simplify: The round ends if allMatched is true AND:
        // 1. We are back to lastAggressor.
        // 2. OR (Pre-flop specific) We are back to BB and BB checks (handled in handleAction check -> nextTurn).
        //    If BB calls (impossible, they are BB), or checks.

        // Let's use a standard approach:
        // Move index first? No, check current state.

        let nextIndex = this.currentTurnIndex;
        do {
            nextIndex = (nextIndex + 1) % this.activePlayers.length;
        } while (this.activePlayers[nextIndex].isFolded);

        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
        const allMatched = activeNonFolded.every(p => p.currentBet === this.currentBet || p.chips === 0);

        if (allMatched && nextIndex === this.lastAggressorIndex) {
            // Special case: Pre-flop BB option.
            // If round is pre-flop, and lastAggressor is BB.
            // If we are here, it means everyone called the BB.
            // Action is ON the BB.
            // If BB checks, handleAction calls nextTurn. 
            // In that call, nextIndex will be UTG. lastAggressor is BB.
            // UTG != BB. So we continue? NO.
            // If BB checks, round SHOULD end.

            // So, we need to detect if the player who JUST acted (currentTurnIndex) was the lastAggressor?
            // If currentTurnIndex == lastAggressorIndex AND allMatched -> Round End.

            if (this.currentTurnIndex === this.lastAggressorIndex) {
                this.nextRound();
                return;
            }

            // But wait, if A bets. B calls. C calls.
            // A bets (lastAggressor = A).
            // B calls. current=B. next=C.
            // C calls. current=C. next=A.
            // allMatched = true. nextIndex = A (lastAggressor).
            // So we should end here? Yes.

            // But what about the BB option?
            // Pre-flop. Aggressor = BB.
            // UTG calls. ... SB calls.
            // Current=SB. next=BB.
            // allMatched = true. nextIndex = BB (lastAggressor).
            // If we end here, BB doesn't get to act!
            // So for Pre-flop, if next is BB, we DO NOT end.

            if (this.round === 'pre-flop' && this.activePlayers[nextIndex].currentBet === this.bigBlindAmount && this.currentBet === this.bigBlindAmount) {
                // Allow BB to act
            } else {
                this.nextRound();
                return;
            }
        }

        this.currentTurnIndex = nextIndex;

        // Check if next player is a bot
        const nextPlayer = this.activePlayers[this.currentTurnIndex];
        if (nextPlayer.isBot) {
            setTimeout(() => this.handleBotTurn(nextPlayer), 1000 + Math.random() * 1000);
        }
    }

    private nextRound() {
        this.currentTurnIndex = (this.dealerIndex + 1) % this.activePlayers.length;
        // Skip folded
        while (this.activePlayers[this.currentTurnIndex].isFolded) {
            this.currentTurnIndex = (this.currentTurnIndex + 1) % this.activePlayers.length;
        }

        this.activePlayers.forEach(p => p.currentBet = 0);
        this.currentBet = 0;
        this.lastAggressorIndex = this.currentTurnIndex; // First to act is new aggressor base

        switch (this.round) {
            case 'pre-flop':
                this.round = 'flop';
                this.communityCards.push(...this.deal(3));
                break;
            case 'flop':
                this.round = 'turn';
                this.communityCards.push(...this.deal(1));
                break;
            case 'turn':
                this.round = 'river';
                this.communityCards.push(...this.deal(1));
                break;
            case 'river':
                this.round = 'showdown';
                this.evaluateWinner();
                return;
        }

        // Trigger bot if first player is bot
        const nextPlayer = this.activePlayers[this.currentTurnIndex];
        if (nextPlayer.isBot) {
            setTimeout(() => this.handleBotTurn(nextPlayer), 1000);
        }
    }

    private handleBotTurn(bot: Player) {
        const { BotLogic } = require('./BotLogic');

        try {
            let action = BotLogic.decide(bot, this.currentBet, this.pot);
            let amount = 0;

            if (action === 'check' && this.currentBet > bot.currentBet) {
                action = 'call';
            }
            if (action === 'bet') {
                amount = this.currentBet + 50;
            }

            console.log(`Bot ${bot.name} decided to ${action}`);
            this.handleAction(bot.id, action, amount);

            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }

        } catch (e) {
            console.error('Bot error:', e);
            this.handleAction(bot.id, 'fold');
        }
    }

    public onGameStateChange?: (state: any) => void;

    private evaluateWinner() {
        const activePlayers = this.activePlayers.filter(p => !p.isFolded);

        if (activePlayers.length === 1) {
            this.endHand(activePlayers[0]);
            return;
        }

        // Create hands for each player with their cards + community cards
        const playerHands = activePlayers.map(player => ({
            player: player,
            hand: Hand.solve([...player.hand!, ...this.communityCards])
        }));

        // Find winning hand(s)
        const hands = playerHands.map(ph => ph.hand);
        const winningHands = Hand.winners(hands);

        // Find players with winning hands
        const winners = playerHands.filter(ph => winningHands.includes(ph.hand));

        if (winners.length === 1) {
            // Single winner
            this.endHand(winners[0].player);
        } else {
            // Split pot
            const splitAmount = Math.floor(this.pot / winners.length);
            winners.forEach(w => {
                w.player.chips += splitAmount;
            });

            // Notify about split pot
            if (this.onGameStateChange) {
                this.onGameStateChange({
                    type: 'hand_winner',
                    winners: winners.map(w => ({
                        id: w.player.id,
                        name: w.player.name,
                        amount: splitAmount
                    })),
                    split: true,
                    gameState: this.getGameState()
                });
            }

            // Auto-restart
            setTimeout(() => {
                this.startRound();
                if (this.onGameStateChange) {
                    this.onGameStateChange(this.getGameState());
                }
            }, 5000);
        }
    }

    private placeBet(player: Player, amount: number) {
        if (player.chips < amount) {
            amount = player.chips; // All-in
        }
        player.chips -= amount;
        player.currentBet += amount;
        this.pot += amount;
    }

    private initializeDeck() {
        const suits = ['h', 'd', 'c', 's'];
        const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];
        this.deck = [];
        for (const suit of suits) {
            for (const rank of ranks) {
                this.deck.push(rank + suit);
            }
        }
        this.shuffleDeck();
    }

    private shuffleDeck() {
        for (let i = this.deck.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
        }
    }

    private deal(count: number): string[] {
        return this.deck.splice(0, count);
    }

    private endHand(winner: Player) {
        const wonAmount = this.pot;
        winner.chips += this.pot;

        // Emit hand_winner event
        if (this.onGameStateChange) {
            this.onGameStateChange({
                type: 'hand_winner',
                winner: {
                    id: winner.id,
                    name: winner.name,
                    amount: wonAmount
                },
                gameState: this.getGameState()
            });
        }

        console.log(`${winner.name} wins ${wonAmount} chips!`);

        // Auto-start next hand after 5 seconds
        setTimeout(() => {
            this.startRound();
            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }
        }, 5000);
    }
}

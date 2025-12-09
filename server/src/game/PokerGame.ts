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
    
    // AFK System
    private turnTimer: NodeJS.Timeout | null = null;
    private readonly TURN_TIMEOUT_SECONDS = 15;

    // Rake System
    private isPublicRoom: boolean = true; // Default to public

    constructor() { }

    public startGame(players: Player[], isPublic: boolean = true) {
        if (players.length < 2) throw new Error('Not enough players');
        this.players = players;
        this.isPublicRoom = isPublic; // Store room type for rake calculation
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
            // Note: We do NOT reset isSitOut here; it persists until user returns
        });
        
        // Active players are those with chips
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
        
        this.lastAggressorIndex = bbIndex;

        // Start the turn flow
        this.startTurnTimer();
    }

    private startTurnTimer() {
        // Clear existing timer
        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        const currentPlayer = this.activePlayers[this.currentTurnIndex];
        if (!currentPlayer) return;

        // AFK Check: If player is already marked as Sit Out/Absent, skip immediately
        if (currentPlayer.isSitOut) {
            console.log(`⏩ Player ${currentPlayer.name} is SIT OUT. Auto-playing...`);
            // Immediate action without delay
            this.handleTurnTimeout(); 
            return;
        }

        // If bot, use existing bot logic (it has its own delay)
        if (currentPlayer.isBot) {
            setTimeout(() => this.handleBotTurn(currentPlayer), 1000 + Math.random() * 1000);
            return;
        }

        // For human players, start the countdown
        console.log(`⏳ Starting ${this.TURN_TIMEOUT_SECONDS}s timer for ${currentPlayer.name}`);
        this.turnTimer = setTimeout(() => {
            this.handleTurnTimeout();
        }, this.TURN_TIMEOUT_SECONDS * 1000);
    }

    private handleTurnTimeout() {
        const currentPlayer = this.activePlayers[this.currentTurnIndex];
        if (!currentPlayer) return;

        console.log(`⏰ Timeout for ${currentPlayer.name}. Marking as SIT OUT.`);
        
        // 1. Mark as Absent
        currentPlayer.isSitOut = true;

        // 2. Decide Auto-Action: CHECK if possible, otherwise FOLD
        // Check condition: currentBet == player.currentBet
        const canCheck = currentPlayer.currentBet === this.currentBet;
        const action = canCheck ? 'check' : 'fold';

        console.log(`🤖 Auto-Action for ${currentPlayer.name}: ${action}`);

        try {
            this.handleAction(currentPlayer.id, action);
        } catch (e) {
            console.error('Error executing auto-action:', e);
            // Fallback to fold if check fails for some reason
            if (action !== 'fold') {
                this.handleAction(currentPlayer.id, 'fold');
            }
        }
    }

    public addChips(playerId: string, amount: number) {
        const player = this.players.find(p => p.id === playerId);
        if (player) {
            player.chips += amount;
            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }
        }
    }

    public getGameState() {
        const minRaise = this.currentBet + Math.max(this.bigBlindAmount, this.currentBet);

        return {
            pot: this.pot,
            communityCards: this.communityCards,
            currentTurn: this.activePlayers[this.currentTurnIndex]?.id,
            dealerId: this.players[this.dealerIndex]?.id,
            round: this.round,
            currentBet: this.currentBet,
            minBet: minRaise,
            players: this.players.map(p => ({
                id: p.id,
                name: p.name,
                chips: p.chips,
                currentBet: p.currentBet,
                isFolded: p.isFolded,
                isBot: p.isBot,
                isSitOut: p.isSitOut, // Expose AFK status to client
                isAllIn: p.chips === 0 && p.currentBet > 0,
                hand: p.hand
            }))
        };
    }

    public handleAction(playerId: string, action: 'bet' | 'call' | 'fold' | 'check' | 'allin', amount: number = 0) {
        console.log(`🃏 PokerGame.handleAction: playerId=${playerId}, action=${action}, currentTurnIndex=${this.currentTurnIndex}`);
        const player = this.activePlayers[this.currentTurnIndex];
        
        if (!player || player.id !== playerId) {
            throw new Error('Not your turn');
        }

        // If player acts manually, remove Sit Out status
        if (player.isSitOut) {
            console.log(`👋 Player ${player.name} returned! Clearing SIT OUT status.`);
            player.isSitOut = false;
        }

        // Clear timer since action was taken
        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
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
                const minRaise = this.currentBet + Math.max(this.bigBlindAmount, this.currentBet);
                if (amount < minRaise && player.chips >= minRaise) {
                    throw new Error(`Minimum raise is ${minRaise}`);
                }
                this.placeBet(player, amount - player.currentBet);
                if (amount > this.currentBet) {
                    this.lastAggressorIndex = this.currentTurnIndex;
                }
                this.currentBet = amount;
                break;
            case 'allin':
                const allInAmount = player.currentBet + player.chips;
                this.placeBet(player, player.chips);
                if (allInAmount > this.currentBet) {
                    this.lastAggressorIndex = this.currentTurnIndex;
                    this.currentBet = allInAmount;
                }
                break;
            case 'check':
                if (player.currentBet < this.currentBet) throw new Error('Cannot check, must call');
                break;
        }

        this.nextTurn();
    }

    private nextTurn() {
        // Check if we should skip to showdown (all-in scenario)
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);

        if (playersWithChips.length <= 1) {
            console.log('All-in scenario detected - skipping to showdown');
            this.revealAllCardsAndShowdown();
            return;
        }

        let nextIndex = this.currentTurnIndex;
        do {
            nextIndex = (nextIndex + 1) % this.activePlayers.length;
        } while (this.activePlayers[nextIndex].isFolded);

        const allMatched = activeNonFolded.every(p => p.currentBet === this.currentBet || p.chips === 0);

        if (allMatched && nextIndex === this.lastAggressorIndex) {
            if (this.currentTurnIndex === this.lastAggressorIndex) {
                this.nextRound();
                return;
            }

            if (this.round === 'pre-flop' && this.activePlayers[nextIndex].currentBet === this.bigBlindAmount && this.currentBet === this.bigBlindAmount) {
                // Allow BB to act
            } else {
                this.nextRound();
                return;
            }
        }

        this.currentTurnIndex = nextIndex;
        
        // Notify state change before starting timer/bot
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        // Start timer for the new player (handles both Bot and Human/AFK)
        this.startTurnTimer();
    }

    private revealAllCardsAndShowdown() {
        while (this.communityCards.length < 5) {
            if (this.round === 'pre-flop') {
                this.communityCards.push(...this.deal(3));
                this.round = 'flop';
            } else if (this.round === 'flop') {
                this.communityCards.push(...this.deal(1));
                this.round = 'turn';
            } else if (this.round === 'turn') {
                this.communityCards.push(...this.deal(1));
                this.round = 'river';
                break;
            }
        }

        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        setTimeout(() => {
            this.round = 'showdown';
            this.evaluateWinner();
        }, 2000);
    }

    private nextRound() {
        this.currentTurnIndex = (this.dealerIndex + 1) % this.activePlayers.length;
        while (this.activePlayers[this.currentTurnIndex].isFolded) {
            this.currentTurnIndex = (this.currentTurnIndex + 1) % this.activePlayers.length;
        }

        this.activePlayers.forEach(p => p.currentBet = 0);
        this.currentBet = 0;
        this.lastAggressorIndex = this.currentTurnIndex;

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
        
        // Notify state change
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        // Start timer
        this.startTurnTimer();
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
        } catch (e) {
            console.error('Bot error:', e);
            this.handleAction(bot.id, 'fold');
        }
    }

    public onGameStateChange?: (state: any) => void;

    // --- RAKE SYSTEM IMPLEMENTATION ---
    private calculateRakeDistribution(pot: number): { 
        totalRake: number, 
        netPot: number, 
        distribution: { platform: number, club: number, seller: number } 
    } {
        const RAKE_PERCENTAGE = 0.08;
        const totalRake = Math.floor(pot * RAKE_PERCENTAGE);
        const netPot = pot - totalRake;

        let distribution = {
            platform: 0,
            club: 0,
            seller: 0
        };

        if (!this.isPublicRoom) {
            // Case A: Private Room - 100% to Platform
            distribution.platform = totalRake;
            console.log(`💰 Rake (Private): ${totalRake} -> Platform: ${distribution.platform}`);
        } else {
            // Case B: Public Room - Split 50/30/20
            distribution.platform = Math.floor(totalRake * 0.50);
            distribution.club = Math.floor(totalRake * 0.30);
            distribution.seller = Math.floor(totalRake * 0.20);
            
            // Handle remainder cents/rounding by adding to platform
            const distributed = distribution.platform + distribution.club + distribution.seller;
            const remainder = totalRake - distributed;
            if (remainder > 0) distribution.platform += remainder;

            console.log(`💰 Rake (Public): ${totalRake} -> Platform: ${distribution.platform}, Club: ${distribution.club}, Seller: ${distribution.seller}`);
        }

        return { totalRake, netPot, distribution };
    }

    private evaluateWinner() {
        const activePlayers = this.activePlayers.filter(p => !p.isFolded);

        if (activePlayers.length === 1) {
            this.endHand(activePlayers[0]);
            return;
        }

        const playerHands = activePlayers.map(player => ({
            player: player,
            hand: Hand.solve([...player.hand!, ...this.communityCards])
        }));

        const hands = playerHands.map(ph => ph.hand);
        const winningHands = Hand.winners(hands);
        const winners = playerHands.filter(ph => winningHands.includes(ph.hand));

        // Calculate Rake
        const { totalRake, netPot, distribution } = this.calculateRakeDistribution(this.pot);

        if (winners.length === 1) {
            const winner = winners[0].player;
            const winnerHand = winners[0].hand;
            winner.totalRakePaid = (winner.totalRakePaid || 0) + totalRake;
            
            this.endHand(winner, netPot, winnerHand, playerHands, distribution);
        } else {
            const splitAmount = Math.floor(netPot / winners.length);
            const rakePerWinner = Math.floor(totalRake / winners.length);

            winners.forEach(w => {
                w.player.chips += splitAmount;
                w.player.totalRakePaid = (w.player.totalRakePaid || 0) + rakePerWinner;
            });

            if (this.onGameStateChange) {
                this.onGameStateChange({
                    type: 'hand_winner',
                    winners: winners.map(w => ({
                        id: w.player.id,
                        name: w.player.name,
                        amount: splitAmount,
                        handDescription: w.hand.descr || w.hand.name
                    })),
                    split: true,
                    rake: totalRake,
                    rakeDistribution: distribution, // Send to client/backend listener
                    players: this.players.map(p => ({
                        id: p.id,
                        name: p.name,
                        isFolded: p.isFolded,
                        hand: p.isFolded ? null : p.hand,
                        handDescription: !p.isFolded && p.hand ?
                            Hand.solve([...p.hand, ...this.communityCards]).descr ||
                            Hand.solve([...p.hand, ...this.communityCards]).name
                            : null
                    })),
                    gameState: this.getGameState()
                });
            }

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
            amount = player.chips;
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

    private endHand(winner: Player, wonAmount?: number, winnerHand?: any, playerHands?: Array<{ player: Player, hand: any }>, rakeDistribution?: any) {
        let finalAmount = wonAmount;
        let rakeAmount = 0;
        let distribution = rakeDistribution;

        if (finalAmount === undefined) {
            // Winner by fold - Recalculate rake
            const result = this.calculateRakeDistribution(this.pot);
            rakeAmount = result.totalRake;
            finalAmount = result.netPot;
            distribution = result.distribution;
            
            winner.totalRakePaid = (winner.totalRakePaid || 0) + rakeAmount;
        } else {
             rakeAmount = this.pot - finalAmount;
        }

        winner.chips += finalAmount;

        if (this.onGameStateChange) {
            this.onGameStateChange({
                type: 'hand_winner',
                winner: {
                    id: winner.id,
                    name: winner.name,
                    amount: finalAmount,
                    handDescription: winnerHand ? (winnerHand.descr || winnerHand.name) : null
                },
                rake: rakeAmount,
                rakeDistribution: distribution,
                players: this.players.map(p => ({
                    id: p.id,
                    name: p.name,
                    isFolded: p.isFolded,
                    hand: p.isFolded ? null : p.hand,
                    handDescription: !p.isFolded && p.hand ?
                        Hand.solve([...p.hand, ...this.communityCards]).descr ||
                        Hand.solve([...p.hand, ...this.communityCards]).name
                        : null
                })),
                gameState: this.getGameState()
            });
        }

        console.log(`${winner.name} wins ${finalAmount} chips!`);

        setTimeout(() => {
            this.startRound();
            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }
        }, 5000);
    }
}

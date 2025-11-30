/**
 * PracticeGameController - Client-side game controller for practice mode
 * 
 * CRITICAL: This file has ZERO Firebase imports and does NOT touch real credits
 * All game state is managed in memory and resets on page refresh
 * 
 * Features:
 * - Local in-memory game state
 * - Demo balance (10,000 chips per player)
 * - Automatic bot players
 * - Full Texas Hold'em rules via FSM
 * - Side pot and split pot support
 * - Intelligent bot AI
 */

import { IPokerGameController } from './IPokerGameController';
import { Player, GameState, GameAction, GameStateEnum, GameStateCallback } from './types';
import { PokerStateMachine } from './PokerStateMachine';
import { HandEvaluator } from './HandEvaluator';
import { BotAI } from './BotAI';

// NO FIREBASE IMPORTS ALLOWED!
// NO CREDIT SYSTEM IMPORTS ALLOWED!

export class PracticeGameController implements IPokerGameController {
    // Game state
    private players: Player[] = [];
    private deck: string[] = [];
    private stateMachine: PokerStateMachine;
    private communityCards: string[] = [];
    private pot: number = 0;
    private currentBet: number = 0;
    private currentTurnIndex: number = 0;
    private dealerIndex: number = 0;
    private smallBlindAmount: number = 10;
    private bigBlindAmount: number = 20;

    // Demo settings
    private readonly DEMO_STARTING_CHIPS = 10000;

    // Callbacks
    public onGameStateChange?: GameStateCallback;

    // Bot turn timeout
    private botTimeout?: NodeJS.Timeout;

    constructor(private userId: string, private userName: string) {
        this.stateMachine = new PokerStateMachine();
        console.log('🎮 PracticeGameController initialized - NO Firebase, NO real credits');
    }

    /**
     * Start a new practice game
     * Automatically adds bots to fill the table
     */
    startGame(players: Player[]): void {
        if (players.length < 1) {
            throw new Error('Need at least 1 player to start practice mode');
        }

        console.log('🎮 Starting practice game...');

        // Initialize human players with demo chips
        this.players = players.map(p => ({
            ...p,
            chips: this.DEMO_STARTING_CHIPS,
            currentBet: 0,
            isFolded: false,
            totalRakePaid: 0
        }));

        // Add 7 bots to make 8 players total
        const botsNeeded = 8 - this.players.length;
        for (let i = 0; i < botsNeeded; i++) {
            const bot: Player = {
                id: `bot-${Date.now()}-${i}`,
                name: BotAI.getRandomBotName(),
                chips: this.DEMO_STARTING_CHIPS,
                currentBet: 0,
                isFolded: false,
                isBot: true,
                totalRakePaid: 0
            };
            this.players.push(bot);
        }

        console.log(`👥 ${this.players.length} players at table (${this.players.filter(p => p.isBot).length} bots)`);

        // Start first hand
        this.startNewHand();
    }

    /**
     * Start a new hand
     */
    private startNewHand(): void {
        console.log('\n🃏 Starting new hand...');

        // Reset state machine
        this.stateMachine.reset();
        this.stateMachine.transition(GameStateEnum.PostingBlinds);

        // Initialize deck
        this.initializeDeck();

        // Reset pot and community cards
        this.pot = 0;
        this.communityCards = [];
        this.currentBet = 0;

        // Move dealer button
        this.dealerIndex = (this.dealerIndex + 1) % this.players.length;

        // Reset players for new hand
        this.players.forEach(p => {
            p.hand = [];
            p.isFolded = false;
            p.currentBet = 0;
            p.isAllIn = false;
        });

        // Deal hole cards
        this.players.forEach(p => {
            p.hand = this.dealCards(2);
        });

        console.log(`🎴 Dealt cards to ${this.players.length} players`);

        // Post blinds
        this.postBlinds();

        // Transition to pre-flop
        this.stateMachine.transition(GameStateEnum.PreFlop);

        // Emit initial game state
        this.emitGameState();

        // Start first player's turn
        this.startNextTurn();
    }

    /**
     * Post small and big blinds
     */
    private postBlinds(): void {
        const sbIndex = (this.dealerIndex + 1) % this.players.length;
        const bbIndex = (this.dealerIndex + 2) % this.players.length;

        const sbPlayer = this.players[sbIndex];
        const bbPlayer = this.players[bbIndex];

        console.log(`💰 ${sbPlayer.name} posts SB (${this.smallBlindAmount})`);
        console.log(`💰 ${bbPlayer.name} posts BB (${this.bigBlindAmount})`);

        this.placeBet(sbPlayer, this.smallBlindAmount);
        this.placeBet(bbPlayer, this.bigBlindAmount);

        this.currentBet = this.bigBlindAmount;

        // Set big blind as initial aggressor
        this.stateMachine.setInitialAggressor(bbIndex);

        // First to act is after big blind
        this.currentTurnIndex = (bbIndex + 1) % this.players.length;
    }

    /**
     * Handle a player action
     */
    handleAction(playerId: string, action: GameAction | string, amount: number = 0): void {
        const currentPlayer = this.players[this.currentTurnIndex];

        if (!currentPlayer || currentPlayer.id !== playerId) {
            throw new Error('Not your turn');
        }

        console.log(`🎯 ${currentPlayer.name} ${action}${amount ? ` ${amount}` : ''}`);

        // Process action
        const isAggressive = this.processAction(currentPlayer, action as GameAction, amount);

        // Record action in state machine
        this.stateMachine.recordPlayerAction(playerId, isAggressive, this.currentTurnIndex);

        // Emit game state
        this.emitGameState();

        // Check if betting round is complete or if we should continue
        this.advanceGame();
    }

    /**
     * Process a player's action
     * Returns whether the action was aggressive (bet/raise)
     */
    private processAction(player: Player, action: GameAction, amount: number): boolean {
        let isAggressive = false;

        switch (action) {
            case GameAction.Fold:
                player.isFolded = true;
                break;

            case GameAction.Check:
                if (player.currentBet < this.currentBet) {
                    throw new Error('Cannot check - must call or fold');
                }
                break;

            case GameAction.Call:
                const callAmount = this.currentBet - player.currentBet;
                this.placeBet(player, callAmount);
                break;

            case GameAction.Bet:
            case GameAction.Raise:
                // Validate bet amount
                const totalBet = amount;
                const additionalBet = totalBet - player.currentBet;

                if (additionalBet > player.chips) {
                    throw new Error('Insufficient chips for bet');
                }

                this.placeBet(player, additionalBet);

                if (totalBet > this.currentBet) {
                    this.currentBet = totalBet;
                    isAggressive = true;
                }
                break;

            case GameAction.AllIn:
                const allInAmount = player.currentBet + player.chips;
                this.placeBet(player, player.chips);
                player.isAllIn = true;

                if (allInAmount > this.currentBet) {
                    this.currentBet = allInAmount;
                    isAggressive = true;
                }
                console.log(`🔥 ${player.name} is ALL-IN!`);
                break;
        }

        return isAggressive;
    }

    /**
     * Place a bet for a player
     */
    private placeBet(player: Player, amount: number): void {
        const actualAmount = Math.min(amount, player.chips);
        player.chips -= actualAmount;
        player.currentBet += actualAmount;
        this.pot += actualAmount;

        if (player.chips === 0) {
            player.isAllIn = true;
        }
    }

    /**
     * Advance the game after an action
     */
    private advanceGame(): void {
        const activePlayers = this.players.filter(p => !p.isFolded);

        // Check for single winner (everyone else folded)
        if (activePlayers.length === 1) {
            this.handleSingleWinner(activePlayers[0]);
            return;
        }

        // Check if we should skip to showdown (all-in scenario)
        if (this.stateMachine.shouldSkipToShowdown(activePlayers)) {
            console.log('⚡ All-in scenario - skipping to showdown');
            this.skipToShowdown();
            return;
        }

        // Check if betting round is complete
        if (this.stateMachine.isBettingRoundComplete(activePlayers, this.currentTurnIndex, this.currentBet)) {
            this.advanceToNextRound();
            return;
        }

        // Continue to next player's turn
        this.startNextTurn();
    }

    /**
     * Move to next player's turn
     */
    private startNextTurn(): void {
        // Find next non-folded player
        do {
            this.currentTurnIndex = (this.currentTurnIndex + 1) % this.players.length;
        } while (this.players[this.currentTurnIndex].isFolded || this.players[this.currentTurnIndex].isAllIn);

        const nextPlayer = this.players[this.currentTurnIndex];

        // If next player is a bot, schedule their turn
        if (nextPlayer.isBot) {
            this.scheduleBotTurn(nextPlayer);
        }
    }

    /**
     * Schedule a bot's turn with thinking delay
     */
    private scheduleBotTurn(bot: Player): void {
        const delay = BotAI.getThinkingDelay();

        this.botTimeout = setTimeout(() => {
            this.handleBotTurn(bot);
        }, delay);
    }

    /**
     * Handle a bot's turn
     */
    private handleBotTurn(bot: Player): void {
        try {
            const gameState = this.getGameState();
            const decision = BotAI.decide(bot, gameState);

            console.log(`🤖 Bot ${bot.name}: ${decision.action}${decision.amount ? ` ${decision.amount}` : ''} (${decision.reasoning})`);

            this.handleAction(bot.id, decision.action, decision.amount);
        } catch (error) {
            console.error('Bot error:', error);
            // Fallback: bot folds on error
            this.handleAction(bot.id, GameAction.Fold);
        }
    }

    /**
     * Advance to next betting round (flop, turn, river, or showdown)
     */
    private advanceToNextRound(): void {
        const nextState = this.stateMachine.getNextNormalState();

        if (!nextState) {
            console.error('No next state available');
            return;
        }

        console.log(`➡️  Advancing to ${nextState}`);

        // Reset betting for new round
        this.players.forEach(p => p.currentBet = 0);
        this.currentBet = 0;
        this.stateMachine.transition(nextState);

        // Deal community cards based on new state
        switch (nextState) {
            case GameStateEnum.Flop:
                this.communityCards = this.dealCards(3);
                console.log(`🎴 Flop: ${this.communityCards.join(' ')}`);
                break;
            case GameStateEnum.Turn:
                this.communityCards.push(...this.dealCards(1));
                console.log(`🎴 Turn: ${this.communityCards[3]}`);
                break;
            case GameStateEnum.River:
                this.communityCards.push(...this.dealCards(1));
                console.log(`🎴 River: ${this.communityCards[4]}`);
                break;
            case GameStateEnum.Showdown:
                this.handleShowdown();
                return;
        }

        // Set current turn to first player after dealer
        this.currentTurnIndex = (this.dealerIndex + 1) % this.players.length;
        while (this.players[this.currentTurnIndex].isFolded || this.players[this.currentTurnIndex].isAllIn) {
            this.currentTurnIndex = (this.currentTurnIndex + 1) % this.players.length;
        }

        // Emit state
        this.emitGameState();

        // Start next player's turn
        this.startNextTurn();
    }

    /**
     * Skip directly to showdown (for all-in scenarios)
     */
    private skipToShowdown(): void {
        // Deal remaining community cards
        while (this.communityCards.length < 5) {
            const state = this.stateMachine.getState();
            const nextState = this.stateMachine.getNextNormalState();

            if (nextState === GameStateEnum.Showdown) break;

            this.stateMachine.transition(nextState!);

            if (nextState === GameStateEnum.Flop) {
                this.communityCards = this.dealCards(3);
                console.log(`🎴 Flop: ${this.communityCards.join(' ')}`);
            } else if (nextState === GameStateEnum.Turn) {
                this.communityCards.push(...this.dealCards(1));
                console.log(`🎴 Turn: ${this.communityCards[3]}`);
            } else if (nextState === GameStateEnum.River) {
                this.communityCards.push(...this.dealCards(1));
                console.log(`🎴 River: ${this.communityCards[4]}`);
            }

            // Emit state so UI shows cards being revealed
            this.emitGameState();
        }

        // Small delay before showdown
        setTimeout(() => {
            this.handleShowdown();
        }, 1500);
    }

    /**
     * Handle showdown - determine winners and distribute pot
     */
    private handleShowdown(): void {
        console.log('\n🏆 SHOWDOWN');
        this.stateMachine.transition(GameStateEnum.Showdown);

        const activePlayers = this.players.filter(p => !p.isFolded);

        // Calculate pot structure (handles side pots)
        const potStructure = HandEvaluator.calculatePots(activePlayers);
        console.log(`💰 Total pot: ${potStructure.totalPot} (Main: ${potStructure.mainPot}, Side pots: ${potStructure.sidePots.length})`);

        // Determine winners
        const winners = HandEvaluator.determineWinners(
            activePlayers,
            this.communityCards,
            potStructure,
            0.10 // 10% rake
        );

        // Award winnings
        winners.forEach(winner => {
            const player = this.players.find(p => p.id === winner.playerId)!;
            player.chips += winner.amount;
            console.log(`🎉 ${winner.playerName} wins ${winner.amount} with ${winner.handRank}`);
        });

        // Emit showdown results
        if (this.onGameStateChange) {
            this.onGameStateChange({
                type: 'showdown',
                winners: winners,
                potStructure: potStructure,
                gameState: this.getGameState()
            });
        }

        // Start new hand after delay
        setTimeout(() => {
            this.startNewHand();
        }, 5000);
    }

    /**
     * Handle single winner (everyone else folded)
     */
    private handleSingleWinner(winner: Player): void {
        console.log(`🏆 ${winner.name} wins ${this.pot} (everyone else folded)`);

        const rake = Math.floor(this.pot * 0.10);
        const winAmount = this.pot - rake;

        winner.chips += winAmount;
        winner.totalRakePaid = (winner.totalRakePaid || 0) + rake;

        // Emit winner event
        if (this.onGameStateChange) {
            this.onGameStateChange({
                type: 'hand_winner',
                winner: {
                    id: winner.id,
                    name: winner.name,
                    amount: winAmount
                },
                rake: rake,
                gameState: this.getGameState()
            });
        }

        // Start new hand after delay
        setTimeout(() => {
            this.startNewHand();
        }, 3000);
    }

    /**
     * Get current game state
     */
    getGameState(): GameState {
        const minRaise = this.currentBet + Math.max(this.bigBlindAmount, this.currentBet);

        return {
            pot: this.pot,
            communityCards: this.communityCards,
            currentTurn: this.players[this.currentTurnIndex]?.id || null,
            dealerId: this.players[this.dealerIndex]?.id || null,
            round: this.stateMachine.getState(),
            currentBet: this.currentBet,
            minBet: minRaise,
            players: this.players.map(p => ({
                id: p.id,
                name: p.name,
                chips: p.chips,
                currentBet: p.currentBet,
                isFolded: p.isFolded,
                isBot: p.isBot,
                isAllIn: p.isAllIn,
                hand: p.hand,
                totalRakePaid: p.totalRakePaid
            }))
        };
    }

    /**
     * Add chips to a player (for practice mode, just adds to demo balance)
     */
    addChips(playerId: string, amount: number): void {
        const player = this.players.find(p => p.id === playerId);
        if (player) {
            player.chips += amount;
            console.log(`💵 Added ${amount} demo chips to ${player.name}`);
            this.emitGameState();
        }
    }

    /**
     * Emit game state to subscribers
     */
    private emitGameState(): void {
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }
    }

    /**
     * Initialize a fresh deck
     */
    private initializeDeck(): void {
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

    /**
     * Shuffle the deck
     */
    private shuffleDeck(): void {
        for (let i = this.deck.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
        }
    }

    /**
     * Deal cards from the deck
     */
    private dealCards(count: number): string[] {
        return this.deck.splice(0, count);
    }

    /**
     * Clean up resources
     */
    destroy(): void {
        if (this.botTimeout) {
            clearTimeout(this.botTimeout);
        }
        console.log('🎮 PracticeGameController destroyed');
    }
}

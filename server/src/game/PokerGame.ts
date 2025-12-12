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

    // Rebuy System
    private rebuyTimers: Map<string, NodeJS.Timeout> = new Map();
    private readonly REBUY_TIMEOUT_SECONDS = 30;

    // Rake System
    private isPublicRoom: boolean = true; // Default to public

    // Callbacks
    public onGameStateChange?: (state: any) => void;
    public onSystemEvent?: (event: string, data: any) => void;

    constructor() { }

    public startGame(players: Player[], isPublic: boolean = true) {
        if (players.length < 2) throw new Error('Not enough players');
        this.players = players;
        this.isPublicRoom = isPublic; 
        
        // Initialize status
        this.players.forEach(p => {
            if (!p.status) p.status = 'PLAYING';
        });

        this.dealerIndex = (this.dealerIndex + 1) % this.players.length;
        this.startRound();
    }

    private startRound() {
        // Filter valid players for the next round
        const eligiblePlayers = this.players.filter(p => p.chips > 0 && p.status !== 'WAITING_FOR_REBUY');

        if (eligiblePlayers.length < 2) {
            console.log('Not enough eligible players to start round. Waiting for rebuys or joins.');
            
            // Check for Last Man Standing condition
            // If we have 1 eligible player and NO one waiting for rebuy, they win.
            const playersWaitingRebuy = this.players.filter(p => p.status === 'WAITING_FOR_REBUY');
            if (eligiblePlayers.length === 1 && playersWaitingRebuy.length === 0) {
                console.log('Last Man Standing detected!');
                // Wait, if it's just one player and game hasn't started, it's not a win, it's "waiting for opponents".
                // But if this follows a hand end or player removal, it might be a win.
                // The prompt asks specifically for: "Cada vez que un jugador sale... verifica... Si activePlayers.length == 1... Victoria por Abandono"
                // This check needs to be in checkActivePlayers which is called on exit.
                // Here in startRound we handle "Can we start NEXT round?".
                // If we can't, we just wait.
                // But if there is a pot sitting there? No, startRound resets pot.
                // However, if the game was "active" and suddenly everyone leaves but one, 
                // removePlayer calls this.
                
                // We should let checkActivePlayers handle the immediate win trigger.
                // But if we fall through here, ensure we don't clear pot if it wasn't distributed?
                // startRound calls this.pot = 0;
                // We must ensure startRound isn't called if we are in a Walkover state.
            }
            return;
        }

        this.initializeDeck();
        this.pot = 0;
        this.communityCards = [];
        this.round = 'pre-flop';
        this.currentBet = this.bigBlindAmount;

        this.activePlayers = [...eligiblePlayers];
        
        // Reset player states for new round (only for active players)
        this.activePlayers.forEach(p => {
            p.hand = [];
            p.isFolded = false;
            p.currentBet = 0;
            p.isAllIn = false; // Reset all-in status para nueva ronda
            p.status = 'PLAYING';
            // Note: We do NOT reset isSitOut here; it persists until user returns
        });
        
        // Deal cards
        this.activePlayers.forEach(p => {
            p.hand = this.deal(2);
        });

        // Blinds logic (simplified for dynamic player count)
        const dealerActiveIndex = 0; 
        const sbIndex = (dealerActiveIndex + 1) % this.activePlayers.length;
        const bbIndex = (dealerActiveIndex + 2) % this.activePlayers.length;

        this.placeBet(this.activePlayers[sbIndex], this.smallBlindAmount);
        this.placeBet(this.activePlayers[bbIndex], this.bigBlindAmount);

        this.currentTurnIndex = (bbIndex + 1) % this.activePlayers.length;
        this.lastAggressorIndex = bbIndex;

        // Start the turn flow
        this.startTurnTimer();
        
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }
    }

    private startTurnTimer() {
        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        const currentPlayer = this.activePlayers[this.currentTurnIndex];
        if (!currentPlayer) return;

        if (currentPlayer.isSitOut) {
            console.log(`⏩ Player ${currentPlayer.name} is SIT OUT. Auto-playing...`);
            this.handleTurnTimeout(); 
            return;
        }

        if (currentPlayer.isBot) {
            setTimeout(() => this.handleBotTurn(currentPlayer), 1000 + Math.random() * 1000);
            return;
        }

        console.log(`⏳ Starting ${this.TURN_TIMEOUT_SECONDS}s timer for ${currentPlayer.name}`);
        this.turnTimer = setTimeout(() => {
            this.handleTurnTimeout();
        }, this.TURN_TIMEOUT_SECONDS * 1000);
    }

    private handleTurnTimeout() {
        const currentPlayer = this.activePlayers[this.currentTurnIndex];
        if (!currentPlayer) return;

        console.log(`⏰ Timeout for ${currentPlayer.name}. Marking as SIT OUT.`);
        currentPlayer.isSitOut = true;

        const canCheck = currentPlayer.currentBet === this.currentBet;
        const action = canCheck ? 'check' : 'fold';

        try {
            this.handleAction(currentPlayer.id, action);
        } catch (e) {
            console.error('Error executing auto-action:', e);
            if (action !== 'fold') {
                this.handleAction(currentPlayer.id, 'fold');
            }
        }
    }

    public addChips(playerId: string, amount: number) {
        const player = this.players.find(p => p.id === playerId);
        if (player) {
            console.log(`💰 Adding ${amount} chips to ${player.name}`);
            player.chips += amount;
            
            // If they were waiting for rebuy, clear status and timer
            if (player.status === 'WAITING_FOR_REBUY') {
                player.status = 'PLAYING';
                if (this.rebuyTimers.has(playerId)) {
                    clearTimeout(this.rebuyTimers.get(playerId)!);
                    this.rebuyTimers.delete(playerId);
                }
                
                // Try to restart round if we were waiting
                // Check if we have enough players now
                const eligiblePlayers = this.players.filter(p => p.chips > 0 && p.status !== 'WAITING_FOR_REBUY');
                if (eligiblePlayers.length >= 2 && this.round === 'pre-flop' && this.pot === 0 && this.activePlayers.length === 0) {
                     // Game was idle, start it
                     this.startRound();
                }
            }

            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }
        }
    }
    
    public removePlayer(playerId: string) {
        // 1. Remove from lists
        this.players = this.players.filter(p => p.id !== playerId);
        this.activePlayers = this.activePlayers.filter(p => p.id !== playerId);
        
        // 2. Clear Rebuy Timers
        if (this.rebuyTimers.has(playerId)) {
            clearTimeout(this.rebuyTimers.get(playerId)!);
            this.rebuyTimers.delete(playerId);
        }

        // 3. CRITICAL: Trigger Walkover / Last Man Standing Check
        this.checkActivePlayers();
        
        // Note: If player was active in current hand, checkActivePlayers will handle it.
        // If not, nothing happens, we just wait.
    }

    /**
     * checkActivePlayers
     * Checks if only one player remains and triggers Walkover Victory.
     * Called on removePlayer or kickPlayer.
     */
    private checkActivePlayers() {
        // If we only have 1 active player left (survivor) and the game is effectively running
        // Note: activePlayers includes players in the current hand.
        // If players.length is 1, it means everyone else left the table completely.
        
        if (this.players.length === 1) {
            console.log('🏆 Walkover Condition Met: Only 1 player remaining in the room.');
            const winner = this.players[0];
            
            // Stop any timers
            if (this.turnTimer) {
                clearTimeout(this.turnTimer);
                this.turnTimer = null;
            }

            // Award Current Pot to Winner (if any)
            if (this.pot > 0) {
                console.log(`Giving abandoned pot of ${this.pot} to ${winner.name}`);
                winner.chips += this.pot;
                this.pot = 0;
            }

            // Emit Victory Event
            if (this.onSystemEvent) {
                this.onSystemEvent('game_finished', { 
                    winnerId: winner.id, 
                    reason: 'walkover',
                    message: "¡Ganaste! Todos los rivales se retiraron."
                });
                
                // Trigger Cashout immediately
                // The server/RoomManager listens to 'game_finished' and calls closeTableAndCashOut
            }
            
            // Reset state
            this.activePlayers = [];
            this.round = 'pre-flop';
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
                isSitOut: p.isSitOut,
                status: p.status, // Expose status (WAITING_FOR_REBUY)
                isAllIn: p.isAllIn || (p.chips === 0 && p.currentBet > 0),
                hand: p.hand
            }))
        };
    }

    public handleAction(playerId: string, action: 'bet' | 'call' | 'fold' | 'check' | 'allin', amount: number = 0) {
        const player = this.activePlayers[this.currentTurnIndex];
        
        if (!player || player.id !== playerId) {
            throw new Error('Not your turn');
        }

        if (player.isSitOut) {
            console.log(`👋 Player ${player.name} returned! Clearing SIT OUT status.`);
            player.isSitOut = false;
        }

        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        switch (action) {
            case 'fold':
                player.isFolded = true;
                this.activePlayers = this.activePlayers.filter(p => !p.isFolded);
                if (this.activePlayers.length === 1) {
                    this.endHand(this.activePlayers[0]); 
                    return;
                }
                break;
            case 'call':
                const callAmount = this.currentBet - player.currentBet;
                this.placeBet(player, callAmount);
                break;
            case 'bet':
                // Calcular apuesta mínima (raise mínimo)
                // Regla estándar: raise mínimo = apuesta actual + bigBlind (o el tamaño del último raise, lo que sea mayor)
                // Para simplificar, usamos: currentBet + bigBlind
                const minRaise = this.currentBet + this.bigBlindAmount;
                
                // Validar que la apuesta sea suficiente
                const totalBetNeeded = amount - player.currentBet;
                if (totalBetNeeded > player.chips) {
                    throw new Error(`No tienes suficientes fichas. Necesitas ${totalBetNeeded}, tienes ${player.chips}`);
                }
                
                // Si la apuesta es menor al mínimo raise Y el jugador tiene fichas para el raise mínimo, rechazar
                if (amount < minRaise && player.chips >= (minRaise - player.currentBet)) {
                    throw new Error(`Apuesta mínima es ${minRaise}. Tienes ${player.chips} fichas disponibles.`);
                }
                
                // Si el jugador intenta apostar más de lo que tiene, tratarlo como all-in
                if (amount > player.currentBet + player.chips) {
                    amount = player.currentBet + player.chips;
                    player.isAllIn = true;
                    console.log(`⚠️ ${player.name} intentó apostar más de lo que tiene. Tratado como ALL-IN: ${amount}`);
                }
                
                // Realizar la apuesta
                const betAmount = amount - player.currentBet;
                this.placeBet(player, betAmount);
                
                // Si la apuesta es mayor que currentBet, actualizar y marcar como agresor
                if (amount > this.currentBet) {
                    this.lastAggressorIndex = this.currentTurnIndex;
                    this.currentBet = amount;
                    console.log(`💰 ${player.name} aumenta apuesta a ${amount}. Apuesta máxima ahora: ${this.currentBet}`);
                } else if (amount === this.currentBet) {
                    // Si iguala exactamente, es un call, no un raise
                    console.log(`📞 ${player.name} iguala apuesta de ${amount}`);
                }
                break;
            case 'allin':
                const allInAmount = player.currentBet + player.chips;
                this.placeBet(player, player.chips);
                // Marcar jugador como all-in
                player.isAllIn = true;
                if (allInAmount > this.currentBet) {
                    this.lastAggressorIndex = this.currentTurnIndex;
                    this.currentBet = allInAmount;
                }
                console.log(`🔥 ${player.name} va ALL-IN con ${allInAmount} fichas. Apuesta máxima ahora: ${this.currentBet}`);
                break;
            case 'check':
                if (player.currentBet < this.currentBet) throw new Error('Cannot check, must call');
                break;
        }

        this.nextTurn();
    }

    private nextTurn() {
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);

        // CORRECCIÓN CRÍTICA: No saltar al showdown hasta que TODOS los jugadores hayan actuado
        // El siguiente jugador DEBE tener oportunidad de igualar, aumentar o retirarse
        
        let nextIndex = this.currentTurnIndex;
        do {
            nextIndex = (nextIndex + 1) % this.activePlayers.length;
        } while (this.activePlayers[nextIndex].isFolded);

        const nextPlayer = this.activePlayers[nextIndex];
        
        // Si el siguiente jugador está all-in (sin fichas), saltarlo automáticamente
        if (nextPlayer.chips === 0 && nextPlayer.currentBet > 0) {
            // Jugador all-in, pasar al siguiente que pueda actuar
            const originalNextIndex = nextIndex;
            do {
                nextIndex = (nextIndex + 1) % this.activePlayers.length;
            } while ((this.activePlayers[nextIndex].isFolded || 
                     (this.activePlayers[nextIndex].chips === 0 && this.activePlayers[nextIndex].currentBet > 0)) 
                     && nextIndex !== originalNextIndex);
            
            // Si volvimos al mismo jugador, todos están all-in o retirados
            if (nextIndex === originalNextIndex) {
                console.log('Todos los jugadores están all-in o retirados, yendo al showdown');
                this.revealAllCardsAndShowdown();
                return;
            }
        }

        // Verificar si todos los jugadores activos han igualado la apuesta
        const allMatched = activeNonFolded.every(p => {
            // Un jugador está "matched" si:
            // 1. Su apuesta actual es igual a la apuesta máxima, O
            // 2. Está all-in (sin fichas) y ya apostó todo lo que podía
            return p.currentBet === this.currentBet || (p.chips === 0 && p.currentBet > 0);
        });

        // CRÍTICO: Solo ir al showdown si:
        // 1. Todos igualaron Y
        // 2. El siguiente turno es del último agresor (ya pasó por todos) Y
        // 3. No hay más jugadores con fichas que puedan actuar
        if (allMatched) {
            const nextPlayerCanAct = this.activePlayers[nextIndex].chips > 0 && 
                                     this.activePlayers[nextIndex].currentBet < this.currentBet;
            
            // Si el siguiente jugador puede actuar, darle el turno
            if (nextPlayerCanAct) {
                console.log(`Siguiente jugador ${this.activePlayers[nextIndex].name} puede actuar. Pasando turno.`);
                this.currentTurnIndex = nextIndex;
                if (this.onGameStateChange) {
                    this.onGameStateChange(this.getGameState());
                }
                this.startTurnTimer();
                return;
            }
            
            // Si todos igualaron Y el siguiente turno es del último agresor
            if (nextIndex === this.lastAggressorIndex) {
                // Si solo queda 1 jugador con fichas después de que todos igualaron, ir al showdown
                if (playersWithChips.length <= 1) {
                    console.log('All-in scenario: Todos igualaron, yendo al showdown');
                    this.revealAllCardsAndShowdown();
                    return;
                }
                
                // Si todos igualaron pero hay múltiples jugadores con fichas, avanzar ronda
                if (this.currentTurnIndex === this.lastAggressorIndex) {
                    this.nextRound();
                    return;
                }

                // Caso especial: Pre-flop, Big Blind puede actuar
                if (this.round === 'pre-flop' && this.activePlayers[nextIndex].currentBet === this.bigBlindAmount && this.currentBet === this.bigBlindAmount) {
                    // Permitir que BB actúe
                } else {
                    this.nextRound();
                    return;
                }
            }
        }

        // Pasar turno al siguiente jugador
        this.currentTurnIndex = nextIndex;
        
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        this.startTurnTimer();
    }

    private revealAllCardsAndShowdown() {
        // Catch errors here to prevent freezing
        try {
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
        } catch (e) {
            console.error('Error in revealAllCardsAndShowdown:', e);
            // Try to rescue game state by forcing evaluate
            this.evaluateWinner(); 
        }
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
        
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

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

            this.handleAction(bot.id, action, amount);
        } catch (e) {
            console.error('Bot error:', e);
            this.handleAction(bot.id, 'fold');
        }
    }

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
            // Private Table: 100% Platform (as per new rules)
            distribution.platform = totalRake;
        } else {
            // Public Table: 50/30/20 (as per new rules)
            distribution.platform = Math.floor(totalRake * 0.50);
            distribution.club = Math.floor(totalRake * 0.30);
            distribution.seller = Math.floor(totalRake * 0.20);
            
            const distributed = distribution.platform + distribution.club + distribution.seller;
            const remainder = totalRake - distributed;
            if (remainder > 0) distribution.platform += remainder;
        }

        return { totalRake, netPot, distribution };
    }

    private evaluateWinner() {
        try {
            console.log('Evaluating winner...');
            const activePlayers = this.activePlayers.filter(p => !p.isFolded);

            if (activePlayers.length === 1) {
                this.endHand(activePlayers[0]);
                return;
            }

            // Safe solve
            const playerHands = activePlayers.map(player => {
                try {
                    // Filter nulls or malformed cards? Deck should be safe.
                    // But if hand is empty?
                    if (!player.hand || player.hand.length === 0) {
                        console.error(`Player ${player.name} has no hand! Folding them.`);
                        return null; 
                    }
                    return {
                        player: player,
                        hand: Hand.solve([...player.hand, ...this.communityCards])
                    };
                } catch (e) {
                    console.error(`Error solving hand for ${player.name}:`, e);
                    return null;
                }
            }).filter(ph => ph !== null) as Array<{ player: Player, hand: any }>;

            if (playerHands.length === 0) {
                console.error('No valid hands found. Returning pot to pot?');
                // Emergency: just end hand, no winner? Or refund?
                // Refund everyone active
                const split = Math.floor(this.pot / activePlayers.length);
                activePlayers.forEach(p => p.chips += split);
                this.pot = 0;
                // Next round
                setTimeout(() => this.checkForBankruptPlayers(), 5000);
                return;
            }

            const hands = playerHands.map(ph => ph.hand);
            const winningHands = Hand.winners(hands);
            // Note: winningHands references the exact objects from hands array
            const winners = playerHands.filter(ph => winningHands.includes(ph.hand));

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

                setTimeout(() => {
                    this.checkForBankruptPlayers();
                }, 5000);
            }
        } catch (e) {
            console.error('CRITICAL ERROR in evaluateWinner:', e);
            // Try to recover: refund pot?
            // Just push to next round to avoid freeze
            setTimeout(() => this.checkForBankruptPlayers(), 5000);
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
            this.checkForBankruptPlayers();
        }, 5000);
    }
    
    private checkForBankruptPlayers() {
        let hasBankruptPlayers = false;

        this.players.forEach(p => {
            if (p.chips === 0 && p.status !== 'WAITING_FOR_REBUY') {
                if (p.isBot) {
                    // Bots auto rebuy or leave? 
                    // For now, let's just give them chips to keep game going if it's practice
                    p.chips = 1000; 
                } else {
                    console.log(`💸 Player ${p.name} is bankrupt. Waiting for Rebuy.`);
                    p.status = 'WAITING_FOR_REBUY';
                    hasBankruptPlayers = true;
                    
                    // Trigger Rebuy Timer
                    this.startRebuyTimer(p);
                    
                    if (this.onSystemEvent) {
                        this.onSystemEvent('player_needs_rebuy', { playerId: p.id, timeout: this.REBUY_TIMEOUT_SECONDS });
                    }
                }
            }
        });

        // Continue game ONLY if we have eligible players
        // startRound() checks eligibility.
        this.startRound();
    }

    private startRebuyTimer(player: Player) {
        if (this.rebuyTimers.has(player.id)) {
            clearTimeout(this.rebuyTimers.get(player.id)!);
        }

        const timer = setTimeout(() => {
            console.log(`⏰ Rebuy timeout for ${player.name}. Kicking.`);
            if (this.onSystemEvent) {
                this.onSystemEvent('kick_player', { playerId: player.id, reason: 'rebuy_timeout' });
            }
        }, this.REBUY_TIMEOUT_SECONDS * 1000);

        this.rebuyTimers.set(player.id, timer);
    }
}

import { Player, Room } from '../types';
import * as crypto from 'crypto';
import { processRakeLocal } from '../utils/localRake';
const Hand = require('pokersolver').Hand;

const GAME_SECRET = process.env.GAME_SECRET || 'default-secret-change-in-production-2024';

export class PokerGame {
    private deck: string[] = [];
    private pot: number = 0;
    private communityCards: string[] = [];
    private currentTurnIndex: number = 0;
    private currentTurn: string = ''; // ✅ CRITICAL: Store UID of player whose turn it is
    private dealerIndex: number = 0;
    private smallBlindAmount: number = 10;
    private bigBlindAmount: number = 20;
    private currentBet: number = 0;
    private round: 'pre-flop' | 'flop' | 'turn' | 'river' | 'showdown' | 'waiting' = 'pre-flop'; // 🆕 Added 'waiting' state
    private players: Player[] = [];
    private activePlayers: Player[] = []; // Players currently in the hand
    private lastAggressorIndex: number = 0;
    private isHandProcessing: boolean = false; // 🔒 Security Flag: Prevent double spending on race conditions
    private isHandEnding: boolean = false; // 🔒 Hand Lock: Prevent duplicate victory logic
    public actionSequence: number = 0; // 🔢 Sequence ID for global ordering
    public turnExpiresAt: number = 0; // 🕒 Timestamp when current turn expires

    // AFK System
    private turnTimer: NodeJS.Timeout | null = null;
    private readonly TURN_TIMEOUT_SECONDS = 15;

    // Rebuy System
    private rebuyTimers: Map<string, NodeJS.Timeout> = new Map();
    private readonly REBUY_TIMEOUT_SECONDS = 30;

    // Rake System
    private isPublicRoom: boolean = true; // Default to public
    public roomId: string = ''; // ID de la sala para firma criptográfica
    private isPrivate: boolean = false; // 🔒 Flag for private table (100% rake to platform)
    private clubId?: string; // Club ID for rake distribution
    private sellerId?: string; // Seller ID for rake distribution

    // Side Pots System - For All-In scenarios with different stack sizes
    private sidePots: Array<{
        amount: number;
        eligiblePlayerIds: Set<string>;
        maxContribution: number; // Maximum contribution per player for this pot
    }> = [];
    private playerTotalContributions: Map<string, number> = new Map(); // Track total contributions per player in current hand

    // Callbacks
    public onGameStateChange?: (state: any) => void;
    public onSystemEvent?: (event: string, data: any) => void;

    constructor() { }

    public startGame(players: Player[], isPublic: boolean = true, roomId: string = '', clubId?: string, sellerId?: string) {
        if (players.length < 2) throw new Error('Not enough players');
        this.players = players;
        this.isPublicRoom = isPublic;
        this.roomId = roomId;
        this.isPrivate = !isPublic; // 🔒 Convert to isPrivate flag
        this.clubId = clubId;
        this.sellerId = sellerId;

        // Initialize status
        this.players.forEach(p => {
            if (!p.status) p.status = 'PLAYING';
        });

        this.dealerIndex = (this.dealerIndex + 1) % this.players.length;
        this.startRound();
    }

    /**
     * Mueve el botón de Dealer al siguiente jugador elegible.
     * Debe llamarse ANTES de iniciar una nueva mano.
     */
    private rotateDealerButton() {
        if (this.players.length < 2) return;

        let attempts = 0;
        do {
            this.dealerIndex = (this.dealerIndex + 1) % this.players.length;
            const potentialDealer = this.players[this.dealerIndex];
            if (potentialDealer.status !== 'WAITING_FOR_REBUY' && (potentialDealer.chips > 0 || potentialDealer.isBot)) {
                break;
            }
            attempts++;
        } while (attempts < this.players.length);

        console.log(`🔘 Dealer Button movido a: ${this.players[this.dealerIndex].name}`);
    }
    private startRound() {
        // RESET HAND LOCK
        this.isHandEnding = false;

        // 🧹 RESET STATE immediately (Ensure clean slate even if we go to waiting)
        this.initializeDeck();
        this.pot = 0;
        this.sidePots = [];
        this.playerTotalContributions.clear();
        this.communityCards = [];
        this.round = 'pre-flop'; // Default, will change to waiting if needed

        const eligiblePlayers = this.players.filter(p =>
            p.status !== 'WAITING_FOR_REBUY' &&
            p.status !== 'ELIMINATED' &&
            (p.chips > 0 || p.isBot)
        );

        if (eligiblePlayers.length < 2) {
            console.log('⏳ Esperando más jugadores para iniciar ronda...');
            this.round = 'waiting'; // Explicitly set waiting state
            this.activePlayers = []; // Ensure no active players
            return;
        }

        // ROTACIÓN DEL DEALER
        this.rotateDealerButton();

        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        this.currentBet = this.bigBlindAmount;

        this.activePlayers = [...eligiblePlayers];

        this.activePlayers.forEach(p => {
            p.hand = [];
            p.isFolded = false;
            p.currentBet = 0;
            p.isAllIn = false;
            p.status = 'PLAYING';
            p.hasActed = false;
        });

        this.activePlayers.forEach(p => {
            p.hand = this.deal(2);
        });

        // LÓGICA DE CIEGAS Y POSICIONES
        const dealerId = this.players[this.dealerIndex].id;
        let activeDealerIndex = this.activePlayers.findIndex(p => p.id === dealerId);

        if (activeDealerIndex === -1) {
            activeDealerIndex = 0;
        }

        let sbIndex = 0;
        let bbIndex = 0;
        let firstActionIndex = 0;

        if (this.activePlayers.length === 2) {
            // Heads Up: Dealer es SB y habla primero Pre-flop
            sbIndex = activeDealerIndex;
            bbIndex = (activeDealerIndex + 1) % this.activePlayers.length;
            firstActionIndex = sbIndex;
        } else {
            // Mesa Normal
            sbIndex = (activeDealerIndex + 1) % this.activePlayers.length;
            bbIndex = (activeDealerIndex + 2) % this.activePlayers.length;
            firstActionIndex = (activeDealerIndex + 3) % this.activePlayers.length;
        }

        console.log(`🃏 Round Info: Dealer=${this.activePlayers[activeDealerIndex].name}, SB=${this.activePlayers[sbIndex].name}, BB=${this.activePlayers[bbIndex].name}`);

        this.placeBet(this.activePlayers[sbIndex], this.smallBlindAmount);
        this.placeBet(this.activePlayers[bbIndex], this.bigBlindAmount);

        this.currentTurnIndex = firstActionIndex;
        this.currentTurn = this.activePlayers[firstActionIndex]?.uid || this.activePlayers[firstActionIndex]?.id || ''; // ✅ Set UID
        this.lastAggressorIndex = bbIndex;

        console.log(`[TURN_INIT] Starting turn for ${this.activePlayers[firstActionIndex]?.name} (UID: ${this.currentTurn})`);
        this.startTurnTimer();

        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }
    }

    private startTurnTimer() {
        // No iniciar timer si la mano terminó (currentTurnIndex = -1)
        if (this.currentTurnIndex === -1) {
            console.log('⏹️ No se inicia timer - Mano terminada');
            return;
        }

        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        const currentPlayer = this.activePlayers[this.currentTurnIndex];
        if (!currentPlayer) return;

        // Reset expiration if not set
        this.turnExpiresAt = 0;

        if (currentPlayer.isSitOut) {
            console.log(`⏩ Player ${currentPlayer.name} is SIT OUT. Auto-playing...`);
            this.handleTurnTimeout();
            return;
        }

        if (currentPlayer.isBot) {
            setTimeout(() => this.handleBotTurn(currentPlayer), 1000 + Math.random() * 1000);
            return;
        }

        // SET EXPIRATION TIME (Server Authority)
        this.turnExpiresAt = Date.now() + (this.TURN_TIMEOUT_SECONDS * 1000);
        console.log(`⏳ Starting ${this.TURN_TIMEOUT_SECONDS}s timer for ${currentPlayer.name}. Expires at: ${this.turnExpiresAt}`);

        this.turnTimer = setTimeout(() => {
            this.handleTurnTimeout();
        }, this.TURN_TIMEOUT_SECONDS * 1000);
    }

    private handleTurnTimeout() {
        // 🛡️ SURGICAL FIX: Wrap entire logic in try/catch
        try {
            // 1. Clear timer first
            if (this.turnTimer) {
                clearTimeout(this.turnTimer);
                this.turnTimer = null;
            }

            // 2. Verify player existence
            const currentPlayer = this.activePlayers[this.currentTurnIndex];

            if (!currentPlayer) {
                console.warn(`⏰ handleTurnTimeout: Player at index ${this.currentTurnIndex} is undefined. Aborting.`);
                return;
            }

            console.log(`⏰ Timeout for ${currentPlayer.name} (ID: ${currentPlayer.id}). Marking as SIT OUT.`);

            // ✅ FIX: Do NOT mark as SIT OUT immediately on timeout.
            // This prevents active (but slow) players from being kicked to spectator mode.
            // currentPlayer.isSitOut = true; 

            // Only Check/Fold
            const canCheck = currentPlayer.currentBet === this.currentBet;
            const action = canCheck ? 'check' : 'fold';

            const playerIdentifier = currentPlayer.uid || currentPlayer.id;
            console.log(`[TIMEOUT_ACTION] Auto-${action} for ${currentPlayer.name} (No Sit-Out enforcement)`);
            this.handleAction(playerIdentifier, action);
        } catch (e) {
            console.error('❌ CRITICAL ERROR in handleTurnTimeout:', e);
            try {
                this.nextTurn();
            } catch (e2) {
                console.error('❌ FAILED TO RECOVER from timeout error:', e2);
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

    /**
     * Actualiza el ID de un jugador (Reconexión)
     * Migra todo el estado del ID antiguo al nuevo.
     */
    public updatePlayerId(oldId: string, newId: string) {
        console.log(`🔄 PokerGame: Updating Player ID from ${oldId} to ${newId}`);

        // 1. Update in main players list
        const player = this.players.find(p => p.id === oldId);
        if (player) {
            player.id = newId;
        }

        // 2. Update in active players list
        const activePlayer = this.activePlayers.find(p => p.id === oldId);
        if (activePlayer) {
            activePlayer.id = newId;
        }

        // 3. Update Rebuy Timers
        if (this.rebuyTimers.has(oldId)) {
            const timer = this.rebuyTimers.get(oldId)!;
            this.rebuyTimers.delete(oldId);
            this.rebuyTimers.set(newId, timer);
        }

        // 4. Update Player Total Contributions
        if (this.playerTotalContributions.has(oldId)) {
            const contribution = this.playerTotalContributions.get(oldId)!;
            this.playerTotalContributions.delete(oldId);
            this.playerTotalContributions.set(newId, contribution);
        }

        // 5. Update Side Pots Eligibility
        this.sidePots.forEach(pot => {
            if (pot.eligiblePlayerIds.has(oldId)) {
                pot.eligiblePlayerIds.delete(oldId);
                pot.eligiblePlayerIds.add(newId);
            }
        });

        console.log(`✅ PokerGame: Player ID updated successfully.`);
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
     * 
     * BUG FIX: Ahora detecta correctamente cuando solo queda un jugador activo
     * y ejecuta forceGameEnd() + closeTableAndCashOut() automáticamente
     */
    private checkActivePlayers() {
        // Verificar jugadores activos (no retirados, no esperando rebuy)
        const activePlayers = this.players.filter(p =>
            p.status !== 'WAITING_FOR_REBUY' &&
            p.status !== 'ELIMINATED' &&
            (p.chips > 0 || p.isBot) // Incluir bots o jugadores con fichas
        );

        // BUG FIX: Si solo queda 1 jugador activo, es victoria inmediata
        if (activePlayers.length === 1) {
            console.log('🏆 Last Man Standing Condition Met: Only 1 active player remaining.');
            const winner = activePlayers[0];

            // Detener timer
            if (this.turnTimer) {
                clearTimeout(this.turnTimer);
                this.turnTimer = null;
            }
            this.currentTurnIndex = -1;

            // FIX CRÍTICO: Usar endHand para procesar el Rake correctamente y generar eventos
            if (this.pot > 0) {
                console.log(`💰 Procesando victoria de ${winner.name} a través de endHand (Rake processing)`);
                this.endHand(winner);
            } else {
                // Si el bote es 0, solo reinicia
                this.activePlayers = [];
                this.round = 'pre-flop';
            }

            // 🔒 FIX: Si este es el ÚNICO jugador en la sala (todos los demás se fueron), cerrar la mesa
            // Esto previene que el ganador se quede "atrapado" solo en la sala
            if (this.players.length === 1 && this.onSystemEvent) {
                console.log(`🔒 [AUTO-CLOSE] Player ${winner.name} is the last one in the room. Closing table.`);
                setTimeout(() => {
                    if (this.onSystemEvent) {
                        this.onSystemEvent('TABLE_CLOSED', {
                            tableId: this.roomId,
                            reason: 'LAST_MAN_STANDING',
                            winnerUid: winner.uid,
                            winnerId: winner.id,
                            finalChips: winner.chips
                        });
                    }
                }, 2000); // Pequeño delay para permitir que se procese el endHand primero
            }

            return;
        }

        // Si hay 0 jugadores activos, la mesa está vacía (ya se maneja en RoomManager)
        if (activePlayers.length === 0) {
            console.log('⚠️ No hay jugadores activos en la mesa.');
            this.activePlayers = [];
            this.round = 'pre-flop';
        }
    }

    public getPublicState(requestingPlayerId?: string, useDelta: boolean = false): any {
        const fullState = {
            tableId: this.roomId,
            sequenceId: this.actionSequence, // 🔢 Emit Sequence ID
            pot: this.pot,
            communityCards: this.communityCards,
            stage: this.round.toUpperCase(),
            dealerIndex: this.dealerIndex,
            currentTurnIndex: this.currentTurnIndex,
            turnExpiresAt: this.turnExpiresAt, // 🕒 Expose expiration time

            // CRITICAL FIX: Map players with BOTH field names for frontend compatibility
            players: this.players.map(p => ({
                id: p.id,
                uid: p.uid,
                name: p.name,
                chips: p.chips,
                bet: p.currentBet, // Original field name
                currentBet: p.currentBet, // CRITICAL: Flutter expects this name
                isFolded: p.isFolded,
                isAllIn: p.isAllIn || (p.chips === 0 && p.currentBet > 0),
                seatIndex: (p as any).seatIndex,
                avatar: (p as any).avatar,
                // CRITICAL: Include both 'cards' and 'hand' for compatibility
                // Only show if requesting player OR showdown
                cards: (requestingPlayerId === p.id || this.round === 'showdown') ? p.hand : null,
                hand: (requestingPlayerId === p.id || this.round === 'showdown') ? p.hand : null
            })),

            // Additional fields for compatibility
            // CRITICAL: Return UID directly from this.currentTurn variable or derive it
            currentTurn: this.currentTurn || (this.activePlayers[this.currentTurnIndex]?.uid || this.activePlayers[this.currentTurnIndex]?.id),
            dealerId: this.players[this.dealerIndex]?.id,
            currentBet: this.currentBet,
            minBet: this.currentBet + Math.max(this.bigBlindAmount, this.currentBet),
            smallBlind: this.smallBlindAmount,
            bigBlind: this.bigBlindAmount,
            activePlayerIds: this.activePlayers.map(p => p.id)
        };

        if (useDelta) {
            // 📉 Delta Logic: Future optimization to only return changed fields
            // For now, full state is safer to avoid desync
            return fullState;
        }

        return fullState;
    }

    public getGameState() {
        // Default to public state with no private cards revealed (spectator view)
        return this.getPublicState(undefined);
    }

    public handleAction(playerId: string, action: 'bet' | 'call' | 'fold' | 'check' | 'allin', amount: number = 0, sequenceId?: number) {
        // Verificar que el juego no haya terminado
        if (this.currentTurnIndex === -1) {
            throw new Error('La mano ya terminó. No se pueden realizar más acciones.');
        }

        const player = this.activePlayers[this.currentTurnIndex];

        // 🔒 CONCURRENCY LOCK: Check if another action is processing
        if (this.isHandProcessing) {
            console.warn(`🔒 Race Condition prevented: Action ignored for ${playerId} while processing.`);
            return; // Fail silently or throw, but better strict ignore to prevent state corruption
        }

        // 🔢 SEQUENCE CHECK (Optimistic Concurrency Control)
        if (sequenceId !== undefined && sequenceId !== this.actionSequence) {
            console.warn(`🔢 Sequence Mismatch: Server ${this.actionSequence} vs Client ${sequenceId}. Rejected.`);
            throw new Error('Out of sync. Please wait.');
        }

        this.isHandProcessing = true; // Lock

        try {

            // 1. Validar Autoridad (Identity & Turn) - UID-BASED VALIDATION
            // Find player by Socket ID OR Firebase UID
            const actingPlayer = this.activePlayers.find(p => p.id === playerId || p.uid === playerId);

            // ... (Diagnostic Logging suppressed for brevity, assume unchanged) ...

            // Validate turn using UID (primary) with socket.id fallback
            if (!actingPlayer) {
                console.error(`[TURN_ERROR] Player not found: ${playerId}`);
                throw new Error('Player not found');
            }

            if (this.currentTurn !== actingPlayer.uid && this.currentTurn !== actingPlayer.id) {
                console.error(`[TURN_ERROR] Not your turn. Current: ${this.currentTurn} | Attempting: ${actingPlayer.uid || actingPlayer.id}`);
                throw new Error('Not your turn');
            }

            if (!player || player !== actingPlayer) {
                console.error(`[TURN_ERROR] Index mismatch detected`);
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

            // 2. Ejecutar Lógica de Acción
            switch (action) {
                case 'fold':
                    player.isFolded = true;
                    player.hasActed = true; // CRÍTICO

                    const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
                    if (activeNonFolded.length === 1) {
                        this.endHand(activeNonFolded[0]);
                        return;
                    }
                    break;
                case 'call':
                    const callAmount = this.currentBet - player.currentBet;
                    this.placeBet(player, callAmount);
                    player.hasActed = true; // CRÍTICO
                    break;
                case 'bet':
                    const minRaise = this.currentBet + this.bigBlindAmount;
                    const totalBetNeeded = amount - player.currentBet;

                    if (totalBetNeeded > player.chips) {
                        throw new Error(`No tienes suficientes fichas.`);
                    }
                    if (amount < minRaise && player.chips >= (minRaise - player.currentBet)) {
                        throw new Error(`Apuesta mínima es ${minRaise}.`);
                    }

                    if (amount > player.currentBet + player.chips) {
                        amount = player.currentBet + player.chips;
                        player.isAllIn = true;
                    }

                    const betAmount = amount - player.currentBet;
                    this.placeBet(player, betAmount);
                    player.hasActed = true; // CRÍTICO

                    if (amount > this.currentBet) {
                        this.lastAggressorIndex = this.currentTurnIndex;
                        this.currentBet = amount;
                    }
                    break;
                case 'allin':
                    const allInAmount = player.currentBet + player.chips;
                    this.placeBet(player, player.chips);
                    player.isAllIn = true;
                    player.hasActed = true; // CRÍTICO
                    if (allInAmount > this.currentBet) {
                        this.lastAggressorIndex = this.currentTurnIndex;
                        this.currentBet = allInAmount;
                    }
                    break;
                case 'check':
                    if (player.currentBet < this.currentBet) throw new Error('Cannot check, must call');
                    player.hasActed = true; // CRÍTICO
                    break;
            }

            // 🔢 INCREMENT SEQUENCE
            this.actionSequence++;

            // 3. ¿La ronda de apuestas ha terminado?
            if (this.canAdvancePhase()) {
                this.nextRound();
            } else {
                this.moveToNextActivePlayer();
            }

            // Broadcast State
            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }

        } catch (error) {
            throw error;
        } finally {
            // 🔥 CRITICAL FIX: ASYNC UNLOCK (50ms) to allow event queue clearing
            setTimeout(() => {
                this.isHandProcessing = false; // Unlock after delay
            }, 50);
        }
    }

    private moveToNextActivePlayer(): void {
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded && p.status === 'PLAYING');

        // Check if only one player left (Winner)
        if (activeNonFolded.length <= 1) {
            this.endHand(activeNonFolded[0]);
            return;
        }

        let nextIndex = this.currentTurnIndex;
        let found = false;
        let attempts = 0;
        const maxAttempts = this.activePlayers.length * 2;

        // 🛡️ Busqueda de siguiente jugador habilitado
        do {
            nextIndex = (nextIndex + 1) % this.activePlayers.length;
            const p = this.activePlayers[nextIndex];

            // STRICT SKIPPING LOGIC:
            // 1. Player exists
            // 2. Status is 'PLAYING'
            // 3. Not folded
            // 4. Not All-In (All-in players cant act)
            if (p && p.status === 'PLAYING' && !p.isFolded && !p.isAllIn) {
                found = true;
                break;
            }
            attempts++;
        } while (attempts < maxAttempts);

        if (found) {
            const nextPlayer = this.activePlayers[nextIndex];
            this.currentTurnIndex = nextIndex;
            this.currentTurn = nextPlayer.uid || nextPlayer.id || ''; // ✅ Update UID

            // 📝 [DEBUG_TURN] Log solicitado explícitamente
            console.log(`[DEBUG_TURN] Next actor: ${nextPlayer.name} (UID: ${this.currentTurn})`);

            // Broadcast State IMMEDIATELY so frontend updates buttons
            if (this.onGameStateChange) {
                this.onGameStateChange(this.getGameState());
            }

            // Start Timer
            this.startTurnTimer();
        } else {
            // No se encontró jugador habilitado para actuar.
            // Esto significa que todos los demás están Folded o All-In.
            console.log('🔄 No provisional active players found (all folded or all-in). Checking phase advance...');

            if (this.areAllPlayersAllIn()) {
                console.log('🔄 All-in condition met. Advancing to Showdown.');
                this.autoAdvanceToShowdown();
            } else if (this.canAdvancePhase()) {
                console.log('✅ Phase Complete. Advancing to next round.');
                this.nextRound();
            } else {
                console.error('CRITICAL: Stuck in turn loop. No players can act, but canAdvancePhase() is false.');
                // Failsafe: Force next round to unblock
                this.nextRound();
            }
        }
    }

    private canAdvancePhase(): boolean {
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded && p.status === 'PLAYING');
        const playersWhoCanAct = activeNonFolded.filter(p => !p.isAllIn);
        const maxBet = this.currentBet;

        // 1. All-in Scenario: If only 1 player can act (others all-in) and they matched bet -> Advance
        // or if everyone is all-in
        if (playersWhoCanAct.length <= 1) {
            const allMatched = activeNonFolded.every(p => p.currentBet === maxBet || (p.chips === 0 && p.currentBet > 0));
            if (allMatched && playersWhoCanAct.length === 0) return true; // Everyone All-in
            if (allMatched && playersWhoCanAct.length === 1 && playersWhoCanAct[0].hasActed) return true; // 1 Active + others All-in
        }

        // 2. Standard Scenario: Everyone must match maxBet AND have acted
        const allMatchedAndActed = playersWhoCanAct.every(p => {
            return p.currentBet === maxBet && p.hasActed;
        });

        // 🛡️ PRE-FLOP LOGIC: ensure Big Blind option is respected
        // Logic handles it because BB starts with hasActed=false.
        // If everyone calls, BB is last to act. BB Check -> hasActed=true -> Advance.

        if (allMatchedAndActed) {
            console.log(`✅ [PHASE_CHECK] All eligible players matched & acted. Validating advance.`);
            return true;
        }

        return false;
    }

    /**
     * Valida si es el turno del jugador usando UID y ID
     */
    public validateTurn(uidOrId: string): boolean {
        if (this.currentTurnIndex === -1) return false;
        const player = this.activePlayers[this.currentTurnIndex];
        if (!player) return false;

        // Validar por ID o UID (para soporte híbrido)
        return player.id === uidOrId || player.uid === uidOrId;
    }

    /**
     * Fuerza el fold del jugador actual (usado por Watchdog)
     */
    public forceCurrentPlayerFold() {
        if (this.currentTurnIndex === -1) return;
        const player = this.activePlayers[this.currentTurnIndex];
        if (!player) return;

        console.log(`👮 Watchdog forcing fold for ${player.name}`);
        this.handleAction(player.id, 'fold');
    }

    /**
     * Carga el estado desde Firestore (Hydration)
     */
    public loadState(data: any) {
        if (!data) return;

        // Restore basic properties
        this.pot = data.pot || 0;
        this.communityCards = data.communityCards || [];
        this.currentTurnIndex = data.currentTurnIndex !== undefined ? data.currentTurnIndex : -1;
        this.dealerIndex = data.dealerIndex || 0;
        this.round = (data.currentRound || 'pre-flop').toLowerCase();
        this.deck = data.deck || [];
        this.turnExpiresAt = data.turnExpiresAt || 0;

        // Restore players
        if (data.players && Array.isArray(data.players)) {
            this.players = data.players;
            // Re-construct activePlayers based on game state logic if needed, 
            // but usually activePlayers is derived or stored. 
            // If activePlayers is stored in Firestore, use it.
            // If not, we might need to filter players who are in the hand.
            // For now, assuming players contains all necessary state flags (isFolded, etc)

            // Re-build activePlayers list (players currently in the hand)
            // This logic depends on how you persist activePlayers. 
            // If you added activePlayers to Firestore schema, load it.
            // Otherwise, filter from this.players.
            if (data.activePlayers && Array.isArray(data.activePlayers)) {
                // Map active players to the objects in this.players to maintain references if possible,
                // or just use the loaded data.
                this.activePlayers = data.activePlayers;
            } else {
                // Fallback: active players are those not eliminated and in the game
                // This might be inaccurate if we don't persist activePlayers explicitly
                this.activePlayers = this.players.filter(p => !p.isFolded && p.status === 'PLAYING');
            }
        }
    }

    /**
     * Verifica si todos los jugadores activos están all-in (o todos menos uno que ya no puede actuar)
     * IMPORTANTE: Esta verificación solo debe hacerse DESPUÉS de que todos hayan tenido oportunidad de actuar
     * 
     * Condiciones para saltar al showdown automáticamente:
     * 1. Todos los jugadores activos han igualado la apuesta
     * 2. Todos los jugadores con fichas han actuado
     * 3. Y además, todos están all-in (0 o 1 jugador con fichas restantes)
     */
    private areAllPlayersAllIn(): boolean {
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);

        // Si solo queda un jugador, no es all-in, es victoria directa
        if (activeNonFolded.length <= 1) {
            return false;
        }

        // Verificar que todos hayan igualado la apuesta
        const allBetsMatched = activeNonFolded.every(p => {
            return p.currentBet === this.currentBet || (p.chips === 0 && p.currentBet > 0);
        });

        if (!allBetsMatched) {
            return false; // Aún hay jugadores que no han igualado, no saltar
        }

        // Verificar que todos los jugadores con fichas hayan actuado
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);
        const allWithChipsActed = playersWithChips.length === 0 || playersWithChips.every(p => p.hasActed === true);

        if (!allWithChipsActed) {
            return false; // Aún hay jugadores que no han actuado, no saltar
        }

        // Si llegamos aquí, todos igualaron y actuaron
        // Ahora verificar si todos están all-in (0 o 1 jugador con fichas)
        return playersWithChips.length <= 1;
    }

    private nextTurn() {
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
        const playersWithChips = activeNonFolded.filter(p => p.chips > 0);

        // 1. Check for Game Over / Showdown Conditions
        if (activeNonFolded.length <= 1) {
            this.revealAllCardsAndShowdown();
            return;
        }

        // 2. Check if Round Complete (All matched bets AND all acted)
        const allBetsMatched = activeNonFolded.every(p =>
            p.currentBet === this.currentBet || (p.chips === 0 && p.currentBet > 0)
        );

        // Players with chips must have acted. Players all-in don't need to act again if they matched.
        const allWithChipsActed = playersWithChips.length === 0 || playersWithChips.every(p => p.hasActed === true);

        if (allBetsMatched && allWithChipsActed) {
            // Check for Auto-Showdown (All-In scenario)
            if (this.areAllPlayersAllIn()) {
                console.log('🔥 All players All-In and matched. Auto-advancing to showdown.');
                this.autoAdvanceToShowdown();
                return;
            }

            // Round is complete, move to next round
            this.nextRound();
            return;
        }

        // 3. Find Next Player (Circular Loop)
        // 🛡️ SURGICAL FIX: do...while loop with safety counter
        let nextIndex = this.currentTurnIndex;
        let foundNext = false;
        const playerCount = this.activePlayers.length;
        let attempts = 0;
        const maxAttempts = playerCount * 2; // Safety limit: 2 full loops

        do {
            nextIndex = (nextIndex + 1) % playerCount;
            const player = this.activePlayers[nextIndex];
            attempts++;

            // Validation logic
            if (!player) continue;
            if (player.isFolded) continue; // Skip folded players
            if (player.chips === 0) continue; // All-in players don't act
            if (player.isSitOut) continue; // Skip sit-out

            foundNext = true;
            break;

        } while (attempts < maxAttempts);

        if (!foundNext) {
            console.warn('⚠️ nextTurn: No active player found after loop. Forcing next round/showdown.');
            if (this.areAllPlayersAllIn()) {
                this.autoAdvanceToShowdown();
            } else {
                this.nextRound();
            }
            return;
        }

        // 4. Update Turn
        this.currentTurnIndex = nextIndex;
        this.currentTurn = this.activePlayers[nextIndex]?.uid || this.activePlayers[nextIndex]?.id || ''; // ✅ Update UID
        console.log(`➡️ [TURN_UPDATE] Turn advanced to ${this.activePlayers[nextIndex]?.name} (UID: ${this.currentTurn})`);

        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        this.startTurnTimer();
    }

    /**
     * Auto-avanza al showdown cuando todos los jugadores están all-in
     * Reparte las cartas restantes secuencialmente y calcula el ganador
     */
    private autoAdvanceToShowdown() {
        // Detener cualquier timer activo
        if (this.turnTimer) {
            clearTimeout(this.turnTimer);
            this.turnTimer = null;
        }

        // Invalidar turno actual para evitar más acciones
        this.currentTurnIndex = -1;

        console.log(`🎴 Auto-repartiendo cartas comunitarias restantes... (Ronda actual: ${this.round})`);

        // Repartir cartas restantes secuencialmente
        const cardsToDeal: string[] = [];
        let targetRound: 'flop' | 'turn' | 'river' | 'showdown' = 'showdown';

        if (this.round === 'pre-flop') {
            // Repartir Flop, Turn y River
            cardsToDeal.push(...this.deal(3)); // Flop
            cardsToDeal.push(...this.deal(1)); // Turn
            cardsToDeal.push(...this.deal(1)); // River
            targetRound = 'showdown';
        } else if (this.round === 'flop') {
            // Repartir Turn y River
            cardsToDeal.push(...this.deal(1)); // Turn
            cardsToDeal.push(...this.deal(1)); // River
            targetRound = 'showdown';
        } else if (this.round === 'turn') {
            // Repartir River
            cardsToDeal.push(...this.deal(1)); // River
            targetRound = 'showdown';
        } else if (this.round === 'river') {
            // Ya estamos en river, solo evaluar
            targetRound = 'showdown';
        }

        // Agregar cartas al mazo comunitario
        if (cardsToDeal.length > 0) {
            this.communityCards.push(...cardsToDeal);
            console.log(`✅ Cartas repartidas: ${cardsToDeal.join(', ')}`);
        }

        // Actualizar estado del juego para que el frontend pueda animar las cartas
        if (this.onGameStateChange) {
            this.onGameStateChange(this.getGameState());
        }

        // Avanzar al showdown y evaluar ganador
        // Usar un pequeño delay para que el frontend pueda mostrar las cartas
        setTimeout(() => {
            this.round = 'showdown';
            console.log('🏆 Evaluando ganador en showdown automático...');
            this.evaluateWinner();
        }, 1500); // Delay de 1.5s para animación en frontend
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
        console.log(`[PHASE_ADVANCE] Moving to next round...`);

        // 🛡️ Limpieza de Flags hasActed y CurrentBet
        this.activePlayers.forEach(p => {
            p.currentBet = 0;
            p.hasActed = false; // RESET CRÍTICO
        });
        this.currentBet = 0;

        // DETERMINAR TURNO POST-FLOP (Izquierda del Dealer)
        // 🛡️ SURGICAL FIX: Validate Dealer Index
        if (!this.players[this.dealerIndex]) {
            console.error(`🛑 Critical: Dealer index ${this.dealerIndex} is invalid. Resetting to 0.`);
            this.dealerIndex = 0;
        }

        // Double check after reset
        if (!this.players[this.dealerIndex]) {
            console.error('🛑 Critical: No valid dealer found even after reset. Aborting round.');
            // If we can't find a dealer, the game state is likely corrupted or empty.
            return;
        }

        const dealerId = this.players[this.dealerIndex].id;
        let activeDealerIndex = this.activePlayers.findIndex(p => p.id === dealerId);

        if (activeDealerIndex === -1) activeDealerIndex = 0;

        // Find next player to act
        let nextToActIndex = (activeDealerIndex + 1) % this.activePlayers.length;

        // 🛡️ SURGICAL FIX: Robust Loop to find next valid player
        let attempts = 0;
        const maxAttempts = this.activePlayers.length * 2;

        while (attempts < maxAttempts) {
            const player = this.activePlayers[nextToActIndex];
            if (player && !player.isFolded && !player.isAllIn) {
                break;
            }
            nextToActIndex = (nextToActIndex + 1) % this.activePlayers.length;
            attempts++;
        }

        // Set the index
        this.currentTurnIndex = nextToActIndex;

        // Update currentTurn UID immediately
        const nextPlayer = this.activePlayers[nextToActIndex];
        if (nextPlayer) {
            this.currentTurn = nextPlayer.uid || nextPlayer.id || '';
            console.log(`➡️ [ROUND_START] Turn set to Left of Dealer: ${nextPlayer.name} (UID: ${this.currentTurn})`);
        }

        // 🛡️ SURGICAL FIX: Validate the new currentTurnIndex
        const activePlayer = this.activePlayers[this.currentTurnIndex];

        if (!activePlayer) {
            console.error(`🛑 Critical: nextRound calculated invalid index ${this.currentTurnIndex}. Resetting to 0.`);
            this.currentTurnIndex = 0;

            // Re-validate after reset
            if (!this.activePlayers[this.currentTurnIndex]) {
                console.error('🛑 Critical: Still invalid after reset. Triggering endHand safety.');
                // If we have at least one player, try to end hand with them as winner? 
                // Or just abort to avoid crash.
                if (this.activePlayers.length > 0) {
                    this.endHand(this.activePlayers[0]);
                }
                return;
            }
        }

        // Check if we have enough active players to continue
        const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);
        if (activeNonFolded.length < 2) {
            console.log('⚠️ nextRound: Less than 2 active players. Ending hand.');
            if (activeNonFolded.length === 1) {
                this.endHand(activeNonFolded[0]);
            }
            return;
        }

        // this.lastAggressorIndex = nextToActIndex;

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

        // Auto-Showdown check
        const activeNonFoldedForShowdown = this.activePlayers.filter(p => !p.isFolded);
        const playersWithChips = activeNonFoldedForShowdown.filter(p => p.chips > 0);

        if (activeNonFoldedForShowdown.length > 1 && playersWithChips.length <= 1) {
            console.log('🔥 Todos All-In post-reparto. Saltando a Showdown.');
            this.autoAdvanceToShowdown();
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
        // CONFIGURACIÓN DE RAKE
        const RAKE_PERCENTAGE = 0.08; // 8%

        let totalRake = 0;

        // REGLA: No Flop, No Drop (No Rake)
        // Verificar si hubo Flop (3 cartas comunitarias o más)
        const hasFlopSeen = this.communityCards.length >= 3;

        if (!hasFlopSeen) {
            totalRake = 0;
            console.log('🚫 [RAKE] No Flop, No Drop. Rake = 0');
        } else {
            // Cálculo simple del 8% como solicitó el usuario
            totalRake = Math.floor(pot * RAKE_PERCENTAGE);
        }

        const netPot = pot - totalRake;

        // 🔒 BUG FIX #3: RAKE DISTRIBUTION LOGIC
        let distribution = {
            platform: 0,
            club: 0,
            seller: 0
        };

        if (totalRake > 0) {
            if (this.isPrivate) {
                // 💰 PRIVATE TABLE: 100% to Platform
                distribution.platform = totalRake;
                console.log(`💰 [RAKE] PRIVATE table: 100% platform (${totalRake})`);
            } else {
                // 💰 PUBLIC TABLE: 50% Platform, 30% Club, 20% Seller
                const platformShare = Math.floor(totalRake * 0.50);
                const clubShare = this.clubId ? Math.floor(totalRake * 0.30) : 0;
                const sellerShare = this.sellerId ? Math.floor(totalRake * 0.20) : 0;

                // Handle centavos (remainder goes to platform)
                const allocated = platformShare + clubShare + sellerShare;
                const remainder = totalRake - allocated;

                distribution.platform = platformShare + remainder; // Platform gets remainder
                distribution.club = clubShare;
                distribution.seller = sellerShare;

                // Fallback: If club or seller missing, their share goes to platform
                if (!this.clubId && !this.sellerId) {
                    distribution.platform = totalRake; // All to platform if no club/seller
                } else if (!this.clubId) {
                    distribution.platform += distribution.club;
                    distribution.club = 0;
                } else if (!this.sellerId) {
                    distribution.platform += distribution.seller;
                    distribution.seller = 0;
                }

                console.log(`💰 [RAKE] PUBLIC table: Platform=${distribution.platform}, Club=${distribution.club}, Seller=${distribution.seller}`);
            }
        }

        // LOG DETAILED INFO
        console.log(`💰 [RAKE] Pot: ${pot} | FlopSeen: ${hasFlopSeen} | Rake: ${totalRake} | Winner Gets: ${netPot}`);

        return { totalRake, netPot, distribution };
    }

    /**
     * 💰 TRIGGER RAKE DISTRIBUTION (LOCAL SERVER-SIDE EXECUTION)
     * 
     * Ejecuta la distribución de rake DIRECTAMENTE usando Admin SDK.
     * Elimina la dependencia de Cloud Functions HTTP que pueden fallar.
     * 
     * Este método es NON-BLOCKING - ejecuta en background y no bloquea el flujo del juego.
     * La transacción de Firestore garantiza la integridad de datos financieros.
     */
    private triggerRakeDistribution(
        potTotal: number,
        rakeTotal: number,
        distribution: { platform: number; club: number; seller: number },
        winnerIds: string[]
    ): void {
        // Solo procesar si hay rake para distribuir
        if (rakeTotal <= 0) {
            console.log(`💰 [RAKE] No rake to distribute. Skipping.`);
            return;
        }

        console.log(`💰 [RAKE] Triggering LOCAL rake distribution: ${rakeTotal}`);

        // 🔥 EJECUCIÓN INMEDIATA DEL PAGO AL ADMIN (LOCAL, SIN CLOUD FUNCTIONS)
        processRakeLocal({
            tableId: this.roomId,
            handId: `hand_${Date.now()}`,
            rakeTotal: rakeTotal,
            isPrivate: this.isPrivate,
            potTotal: potTotal,
            winnerUid: winnerIds.length > 0 ? winnerIds[0] : null,
            clubId: this.clubId,
            sellerId: this.sellerId
        }).then(success => {
            if (success) {
                console.log(`💰 [RAKE] ✅ Local rake distribution completed successfully.`);
            } else {
                console.error(`💰 [RAKE] ❌ Local rake distribution failed.`);
            }
        }).catch(err => {
            console.error(`💰 [RAKE] ❌ Error in local rake async execution:`, err);
        });

        // También emitir evento para compatibilidad con sistemas legacy (si existen)
        // [FIX] Comentado para evitar doble procesamiento y logs incorrectos (RAKE_COLLECTED vs POT_DISTRIBUTED)
        /*
        if (this.onSystemEvent) {
            this.onSystemEvent('distribute_rake', {
                potTotal,
                rakeTotal,
                rakeDistribution: distribution,
                winnerIds,
                isPrivate: this.isPrivate,
                clubId: this.clubId,
                sellerId: this.sellerId,
                processedLocally: true // Flag para indicar que ya se procesó localmente
            });
        }
        */
    }

    private evaluateWinner() {
        try {
            console.log('Evaluating winner with side pots...');

            // Detener timer antes de evaluar ganador
            if (this.turnTimer) {
                clearTimeout(this.turnTimer);
                this.turnTimer = null;
            }

            const activeNonFolded = this.activePlayers.filter(p => !p.isFolded);

            // Caso especial: solo queda un jugador (todos se retiraron)
            if (activeNonFolded.length === 1) {
                this.endHand(activeNonFolded[0]);
                return;
            }

            // Calcular side pots antes de evaluar ganadores
            this.calculateSidePots();

            // Evaluar manos de todos los jugadores activos (NO FOLDED)
            const playerHands = activeNonFolded.map(player => {
                try {
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
                console.error('No valid hands found. Refunding pot.');
                const split = Math.floor(this.pot / activeNonFolded.length);
                activeNonFolded.forEach(p => p.chips += split);
                this.pot = 0;
                setTimeout(() => this.checkForBankruptPlayers(), 5000);
                return;
            }

            // Rastrear premios por jugador y rake total
            const playerWinnings = new Map<string, number>();
            let totalRakeCollected = 0;
            const potResults: Array<{ potName: string; amount: number; winnerId: string; winnerName: string }> = [];

            // Si no hay side pots (juego simple), crear uno con el pot total
            if (this.sidePots.length === 0) {
                this.sidePots = [{
                    amount: this.pot,
                    eligiblePlayerIds: new Set(activeNonFolded.map(p => p.id)),
                    maxContribution: this.pot
                }];
            }

            // Iterar sobre cada pot (main pot + side pots)
            for (let potIndex = 0; potIndex < this.sidePots.length; potIndex++) {
                const pot = this.sidePots[potIndex];
                const potName = potIndex === 0 ? 'Main Pot' : `Side Pot ${potIndex}`;

                // Filtrar jugadores elegibles para este pot
                const eligibleHands = playerHands.filter(ph => pot.eligiblePlayerIds.has(ph.player.id));

                if (eligibleHands.length === 0) {
                    console.warn(`${potName}: No eligible players, skipping.`);
                    continue;
                }

                // Encontrar ganador(es) de este pot
                const hands = eligibleHands.map(ph => ph.hand);
                const winningHands = Hand.winners(hands);
                const potWinners = eligibleHands.filter(ph => winningHands.includes(ph.hand));

                // Calcular rake para este pot
                const { totalRake, netPot, distribution } = this.calculateRakeDistribution(pot.amount);
                totalRakeCollected += totalRake;

                // Distribuir el pot entre ganadores
                if (potWinners.length === 1) {
                    const winner = potWinners[0].player;
                    const current = playerWinnings.get(winner.id) || 0;
                    playerWinnings.set(winner.id, current + netPot);
                    winner.totalRakePaid = (winner.totalRakePaid || 0) + totalRake;

                    potResults.push({
                        potName,
                        amount: netPot,
                        winnerId: winner.id,
                        winnerName: winner.name
                    });

                    console.log(`🏆 ${potName} ($${pot.amount}): ${winner.name} gana $${netPot} (rake: $${totalRake})`);
                } else {
                    // Split pot entre múltiples ganadores
                    const splitAmount = Math.floor(netPot / potWinners.length);
                    const rakePerWinner = Math.floor(totalRake / potWinners.length);

                    potWinners.forEach(w => {
                        const current = playerWinnings.get(w.player.id) || 0;
                        playerWinnings.set(w.player.id, current + splitAmount);
                        w.player.totalRakePaid = (w.player.totalRakePaid || 0) + rakePerWinner;
                    });

                    const winnerNames = potWinners.map(w => w.player.name).join(', ');
                    console.log(`🏆 ${potName} ($${pot.amount}): Split entre ${winnerNames} - cada uno gana $${splitAmount}`);
                }
            }

            // Asignar fichas a los ganadores
            playerWinnings.forEach((amount, playerId) => {
                const player = this.players.find(p => p.id === playerId);
                if (player) {
                    player.chips += amount;
                    console.log(`💰 ${player.name} recibe total de $${amount}`);
                }
            });

            // Encontrar el ganador principal (el que más ganó)
            let mainWinner = activeNonFolded[0];
            let maxWinnings = 0;
            playerWinnings.forEach((amount, playerId) => {
                if (amount > maxWinnings) {
                    maxWinnings = amount;
                    mainWinner = this.players.find(p => p.id === playerId) || mainWinner;
                }
            });

            const mainWinnerHand = playerHands.find(ph => ph.player.id === mainWinner.id)?.hand;

            // Construir respuesta con detalles de side pots
            const gameState: any = this.getGameState();
            gameState.stage = 'showdown';
            gameState.status = 'finished';
            gameState.sidePots = potResults;

            // Actualizar jugadores con handRank
            const playerHandsMap = new Map<string, any>();
            playerHands.forEach(ph => {
                playerHandsMap.set(ph.player.id, ph.hand);
            });

            gameState.players = gameState.players.map((p: any) => {
                const hand = playerHandsMap.get(p.id);
                const winnings = playerWinnings.get(p.id) || 0;
                return {
                    ...p,
                    handRank: hand && !p.isFolded ? (hand.descr || hand.name) : null,
                    winnings: winnings
                };
            });

            // 🔐 GENERAR FIRMA CRIPTOGRÁFICA
            const finalPlayerStacks: { [uid: string]: number } = {};
            this.players.forEach(p => {
                if (p.uid) finalPlayerStacks[p.uid] = p.chips;
            });

            const authPayload = {
                tableId: this.roomId,
                gameId: `hand_${Date.now()}`,
                winnerUid: mainWinner.uid || null, // Ganador principal para referencia (SAFE: null if undefined)
                potTotal: this.sidePots.reduce((acc, pot) => acc + pot.amount, 0) + this.pot, // Total real incluyendo side pots
                rakeTaken: totalRakeCollected,
                finalPlayerStacks: finalPlayerStacks,
                timestamp: Date.now()
            };

            const payloadString = JSON.stringify(authPayload);
            const signature = crypto.createHmac('sha256', GAME_SECRET)
                .update(payloadString)
                .digest('hex');

            // 💰 SOCKET FIRST, LEDGER LATER: Emitir evento para distribución de rake
            // Extraer IDs de ganadores del Map
            console.log(`💰 [DEBUG] playerWinnings Map size: ${playerWinnings.size}`);
            console.log(`💰 [DEBUG] playerWinnings keys:`, Array.from(playerWinnings.keys()));
            console.log(`💰 [DEBUG] this.players:`, this.players.map(p => ({ id: p.id, uid: p.uid, name: p.name })));

            const winnerIds = Array.from(playerWinnings.keys()).map(playerId => {
                const player = this.players.find(p => p.id === playerId);
                console.log(`💰 [DEBUG] Player ${playerId} -> UID: ${player?.uid || 'NOT FOUND'}`);
                return player?.uid;
            }).filter(uid => uid !== undefined) as string[];

            console.log(`💰 [DEBUG] Extracted winnerIds:`, winnerIds);

            // Calcular pot total (incluyendo side pots)
            const totalPotAmount = this.sidePots.reduce((acc, pot) => acc + pot.amount, 0);

            // Calcular distribución final del rake (actualmente todo va a platform)
            // La Cloud Function determinará la distribución real basada en clubId/sellerId
            const finalRakeDistribution = {
                platform: totalRakeCollected,
                club: 0,
                seller: 0
            };

            // Trigger rake distribution (non-blocking)
            this.triggerRakeDistribution(
                totalPotAmount,
                totalRakeCollected,
                finalRakeDistribution,
                winnerIds
            );

            if (this.onGameStateChange) {
                this.onGameStateChange({
                    type: 'hand_winner',
                    winners: Array.from(playerWinnings.entries()).map(([playerId, amount]) => {
                        const ph = playerHands.find(p => p.player.id === playerId);
                        return {
                            id: playerId,
                            name: ph?.player.name || 'Unknown',
                            amount: amount,
                            handDescription: ph?.hand?.descr || ph?.hand?.name || 'Unknown'
                        };
                    }),
                    split: playerWinnings.size > 1,
                    rake: totalRakeCollected,
                    sidePots: potResults,
                    players: this.players.map(p => ({
                        id: p.id,
                        name: p.name,
                        isFolded: p.isFolded,
                        hand: p.isFolded ? null : p.hand,
                        handDescription: !p.isFolded && p.hand ?
                            Hand.solve([...p.hand, ...this.communityCards]).descr ||
                            Hand.solve([...p.hand, ...this.communityCards]).name
                            : null,
                        winnings: playerWinnings.get(p.id) || 0
                    })),
                    gameState: gameState,
                    // 🔐 CAMPOS DE SEGURIDAD
                    authPayload: payloadString,
                    securitySignature: signature
                });
            }

            // Reset pot
            this.pot = 0;
            this.sidePots = [];

            setTimeout(() => {
                this.checkForBankruptPlayers();
            }, 5000);

        } catch (e) {
            console.error('CRITICAL ERROR in evaluateWinner:', e);
            setTimeout(() => this.checkForBankruptPlayers(), 5000);
        }
    }

    /**
     * calculateEffectiveStack - Calcula el stack efectivo para la apuesta actual
     * 
     * En poker, un jugador no puede ganar más de lo que puede cubrir.
     * El effective stack es el mínimo entre:
     * - Lo que el jugador tiene
     * - Lo que el oponente más corto puede igualar
     * 
     * @param playerId - ID del jugador que está apostando
     * @returns El stack máximo efectivo que el jugador puede apostar/igualar
     */
    private calculateEffectiveStack(playerId: string): number {
        const player = this.activePlayers.find(p => p.id === playerId);
        if (!player) return 0;

        // Obtener todos los oponentes activos (no retirados, no el jugador actual)
        const activeOpponents = this.activePlayers.filter(p =>
            p.id !== playerId &&
            !p.isFolded &&
            (p.chips > 0 || p.currentBet > 0) // Incluir jugadores all-in con apuesta
        );

        if (activeOpponents.length === 0) {
            return player.chips + player.currentBet;
        }

        // El effective stack es el mínimo de:
        // 1. Lo que el jugador tiene (chips + currentBet)
        // 2. Lo que cada oponente puede cubrir (chips + currentBet)
        const playerTotal = player.chips + player.currentBet;
        const opponentMaxAmounts = activeOpponents.map(p => p.chips + p.currentBet);
        const minOpponentAmount = Math.min(...opponentMaxAmounts);

        // El effective stack es el mínimo entre ambos
        return Math.min(playerTotal, minOpponentAmount);
    }

    /**
     * placeBet - Coloca una apuesta para un jugador
     * 
     * REGLA CRÍTICA: Aplica el cap de effective stack en TODAS las apuestas.
     * El exceso se devuelve inmediatamente al jugador en heads-up,
     * o crea side pots en juegos de 3+ jugadores.
     * 
     * @param player - Jugador que apuesta
     * @param amount - Cantidad a apostar
     * @returns La cantidad efectiva apostada (puede ser menor a amount por effective stack)
     */
    private placeBet(player: Player, amount: number): number {
        // Cap 1: No puede apostar más de lo que tiene
        if (player.chips < amount) {
            amount = player.chips;
        }

        // Cap 2: Aplicar effective stack cap
        const effectiveStack = this.calculateEffectiveStack(player.id);
        const maxAdditionalBet = effectiveStack - player.currentBet;

        if (amount > maxAdditionalBet && maxAdditionalBet > 0) {
            const excess = amount - maxAdditionalBet;
            console.log(`⚡ ${player.name}: Apuesta de ${amount} excede effective stack. Reducida a ${maxAdditionalBet}. Exceso de ${excess} devuelto.`);
            amount = maxAdditionalBet;
        }

        // Aplicar la apuesta
        player.chips -= amount;
        player.currentBet += amount;
        this.pot += amount;

        // Rastrear contribución total del jugador en esta mano
        const currentTotal = this.playerTotalContributions.get(player.id) || 0;
        this.playerTotalContributions.set(player.id, currentTotal + amount);

        // Marcar all-in si el jugador se quedó sin fichas
        if (player.chips === 0 && amount > 0) {
            player.isAllIn = true;
            console.log(`🔥 ${player.name} está ALL-IN con contribución total de ${player.currentBet}`);
        }

        return amount;
    }

    /**
     * calculateSidePots - Calcula los side pots basándose en las contribuciones de los jugadores
     * 
     * Se llama antes de evaluar el ganador para distribuir correctamente el bote.
     * Cada side pot incluye:
     * - amount: El monto total del pot
     * - eligiblePlayerIds: Los jugadores que pueden ganar este pot
     * - maxContribution: La contribución máxima por jugador para este pot
     */
    private calculateSidePots(): void {
        // Obtener jugadores activos (no retirados) con sus contribuciones totales
        const activeContributions = this.activePlayers
            .filter(p => !p.isFolded)
            .map(p => ({
                id: p.id,
                contribution: this.playerTotalContributions.get(p.id) || 0
            }))
            .filter(p => p.contribution > 0)
            .sort((a, b) => a.contribution - b.contribution); // Ordenar por contribución

        if (activeContributions.length === 0) {
            this.sidePots = [];
            return;
        }

        this.sidePots = [];
        let previousLevel = 0;

        for (let i = 0; i < activeContributions.length; i++) {
            const currentLevel = activeContributions[i].contribution;

            if (currentLevel > previousLevel) {
                // Jugadores elegibles para este nivel de pot son todos los que contribuyeron >= previousLevel
                const eligiblePlayers = activeContributions
                    .filter(p => p.contribution >= currentLevel)
                    .map(p => p.id);

                // Cantidad por jugador para este nivel
                const contributionPerPlayer = currentLevel - previousLevel;

                // Total de jugadores que contribuyeron a este nivel
                const contributors = activeContributions.filter(p => p.contribution >= currentLevel).length;

                // También incluir los jugadores que contribuyeron menos pero hasta su límite
                const partialContributors = activeContributions.filter(
                    p => p.contribution > previousLevel && p.contribution < currentLevel
                );

                let potAmount = 0;

                // Sumar contribuciones completas
                potAmount += contributionPerPlayer * contributors;

                // Sumar contribuciones parciales
                for (const partial of partialContributors) {
                    potAmount += partial.contribution - previousLevel;
                }

                if (potAmount > 0) {
                    this.sidePots.push({
                        amount: potAmount,
                        eligiblePlayerIds: new Set(eligiblePlayers),
                        maxContribution: currentLevel
                    });
                }

                previousLevel = currentLevel;
            }
        }

        // Simplificar: si solo hay un pot, convertirlo en main pot
        if (this.sidePots.length === 1) {
            console.log(`💰 Main Pot: $${this.sidePots[0].amount} (${this.sidePots[0].eligiblePlayerIds.size} jugadores elegibles)`);
        } else if (this.sidePots.length > 1) {
            console.log(`💰 Side Pots creados:`);
            this.sidePots.forEach((pot, idx) => {
                const potName = idx === 0 ? 'Main Pot' : `Side Pot ${idx}`;
                console.log(`   ${potName}: $${pot.amount} (${pot.eligiblePlayerIds.size} jugadores elegibles)`);
            });
        }
    }

    /**
     * getSidePots - Retorna los side pots actuales para mostrar en UI
     */
    public getSidePots(): Array<{ amount: number; playerCount: number }> {
        return this.sidePots.map(pot => ({
            amount: pot.amount,
            playerCount: pot.eligiblePlayerIds.size
        }));
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
        // 🔒 HAND LOCK: Prevent duplicate victory events
        if (this.isHandEnding) {
            console.warn(`🛑 [HAND_LOCK] endHand called but hand is already terminating. Ignoring duplicate call.`);
            return;
        }
        this.isHandEnding = true;

        // 🔒 SECURITY CHECK: Prevent race conditions (Double Spending)
        if (this.isHandProcessing) {
            console.warn(`🛑 [RACE_CONDITION] endHand called but hand is already processing for table ${this.roomId}. Ignoring.`);
            return;
        }
        this.isHandProcessing = true;

        try {
            // CRÍTICO: Detener el timer de turno inmediatamente cuando termina la mano
            if (this.turnTimer) {
                clearTimeout(this.turnTimer);
                this.turnTimer = null;
                console.log('⏹️ Timer de turno detenido - Mano terminada');
            }

            // Limpiar el turno actual para evitar que se pueda actuar
            this.currentTurnIndex = -1; // Invalidar turno actual
            this.currentTurn = ''; // 🛑 Force Waiting State in UI (No active turn)
            this.round = 'waiting'; // 🛑 Force Waiting State

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

            // Obtener estado del juego (currentTurn será undefined porque currentTurnIndex = -1)
            const gameState: any = this.getGameState();

            // Establecer el estado a showdown para que el cliente muestre todas las cartas
            gameState.stage = 'showdown';
            gameState.status = 'finished';

            // Actualizar jugadores en gameState con handRank
            if (playerHands && playerHands.length > 0) {
                const playerHandsMap = new Map<string, any>();
                playerHands.forEach(ph => {
                    playerHandsMap.set(ph.player.id, ph.hand);
                });

                gameState.players = gameState.players.map((p: any) => {
                    const hand = playerHandsMap.get(p.id);
                    if (hand && !p.isFolded) {
                        return {
                            ...p,
                            handRank: hand.descr || hand.name
                        };
                    }
                    return p;
                });
            }

            // 🔐 GENERAR FIRMA CRIPTOGRÁFICA
            const finalPlayerStacks: { [uid: string]: number } = {};
            this.players.forEach(p => {
                if (p.uid) finalPlayerStacks[p.uid] = p.chips;
            });

            const authPayload = {
                tableId: this.roomId,
                gameId: `hand_${Date.now()}`,
                winnerUid: winner.uid || null, // ✅ FIX: Nunca undefined, usar null para bots
                potTotal: (finalAmount || 0) + rakeAmount, // Reconstruir pot total
                rakeTaken: rakeAmount,
                finalPlayerStacks: finalPlayerStacks,
                timestamp: Date.now()
            };

            const payloadString = JSON.stringify(authPayload);
            const signature = crypto.createHmac('sha256', GAME_SECRET)
                .update(payloadString)
                .digest('hex');

            if (this.onGameStateChange) {
                this.onGameStateChange({
                    type: 'hand_winner',
                    gameId: authPayload.gameId, // 🆔 Unique Hand ID for Frontend Deduplication
                    winner: {
                        id: winner.id,
                        uid: winner.uid || null, // CRÍTICO: Exponer UID del ganador
                        name: winner.name,
                        amount: finalAmount,
                        handDescription: winnerHand ? (winnerHand.descr || winnerHand.name) : null
                    },
                    rake: rakeAmount,
                    rakeDistribution: distribution,
                    players: this.players.map(p => ({
                        id: p.id,
                        uid: p.uid, // CRÍTICO: Exponer UID
                        name: p.name,
                        isFolded: p.isFolded,
                        hand: p.isFolded ? null : p.hand,
                        handDescription: !p.isFolded && p.hand ?
                            Hand.solve([...p.hand, ...this.communityCards]).descr ||
                            Hand.solve([...p.hand, ...this.communityCards]).name
                            : null
                    })),
                    gameState: gameState,
                    // 🔐 CAMPOS DE SEGURIDAD
                    authPayload: payloadString,
                    securitySignature: signature
                });
            }

            // 🎯 EVENTO EXPLÍCITO: GAME_ENDED - Para integración con Firestore
            // Este evento señala al RoomManager que debe llamar a settleGameRound
            if (this.onSystemEvent) {
                const playersInvolved = this.players
                    .filter(p => p.uid) // Solo jugadores con UID registrado
                    .map(p => p.uid!);

                this.onSystemEvent('GAME_ENDED', {
                    tableId: this.roomId,
                    gameId: `hand_${Date.now()}`,
                    potTotal: (finalAmount || 0) + rakeAmount,
                    rakeTaken: rakeAmount,
                    rakeAmount: rakeAmount,     // [REQUESTED] Lo que se queda la casa
                    winnerAmount: finalAmount || 0, // [REQUESTED] Lo que recibe el jugador
                    winnerUid: winner.uid || null,
                    playersInvolved: playersInvolved,
                    authPayload: payloadString,
                    signature: signature
                });
                console.log(`🎯 [GAME_ENDED] Event emitted - Pot: ${(finalAmount || 0) + rakeAmount}, Rake: ${rakeAmount}`);
            }

            console.log(`🏆 ${winner.name} wins ${finalAmount} chips! Mano terminada.`);

            setTimeout(() => {
                this.checkForBankruptPlayers();
            }, 5000);

        } catch (e) {
            console.error('❌ CRITICAL ERROR in endHand:', e);
        } finally {
            // 🛡️ DEFENSIVE: Release lock
            this.isHandProcessing = false;
        }
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

            // 🎯 EVENTO EXPLÍCITO: PLAYER_EXIT - Para liberar moneyInPlay en Firestore
            if (this.onSystemEvent) {
                this.onSystemEvent('PLAYER_EXIT', {
                    uid: player.uid,
                    playerId: player.id,
                    finalChips: player.chips,
                    reason: 'TIMEOUT'
                });
                console.log(`🎯 [PLAYER_EXIT] Event emitted for ${player.name} - Chips: ${player.chips}`);
            }

            // Mantener evento legacy para compatibilidad
            if (this.onSystemEvent) {
                this.onSystemEvent('kick_player', { playerId: player.id, reason: 'rebuy_timeout' });
            }
        }, this.REBUY_TIMEOUT_SECONDS * 1000);

        this.rebuyTimers.set(player.id, timer);
    }
}

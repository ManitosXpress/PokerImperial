import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';
import { createTableConfig } from '../types/TableConfig';
import * as admin from 'firebase-admin'; // ACCESO A BD REQUERIDO

export class RoomManager {
    private rooms: Map<string, Room> = new Map();
    private games: Map<string, PokerGame> = new Map();
    private cleanupInterval: NodeJS.Timeout | null = null;
    private readonly CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

    // Callbacks
    public emitCallback?: (roomId: string, event: string, data: any, targetPlayerId?: string) => void;

    // Disconnect Timers
    private disconnectTimers: Map<string, NodeJS.Timeout> = new Map();
    private readonly DISCONNECT_GRACE_PERIOD_MS = 60000; // 60s grace period

    constructor() {
        this.startCleanupInterval();
    }

    private startCleanupInterval() {
        if (this.cleanupInterval) clearInterval(this.cleanupInterval);
        this.cleanupInterval = setInterval(() => this.cleanupEmptyRooms(), this.CLEANUP_INTERVAL_MS);
        console.log('🧹 Cleanup interval started');
    }

    private cleanupEmptyRooms() {
        const now = Date.now();
        for (const [roomId, room] of this.rooms.entries()) {
            if (room.players.length === 0) {
                console.log(`🗑️ Cleaning up empty room: ${roomId}`);
                this.deleteRoom(roomId);
            }
        }
    }

    public stopCleanupInterval() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
            this.cleanupInterval = null;
        }
    }

    public setEmitCallback(callback: (roomId: string, event: string, data: any, targetPlayerId?: string) => void) {
        this.emitCallback = callback;
    }

    public async createPracticeRoom(hostId: string, hostName: string): Promise<Room> {
        return await this.createRoom(hostId, hostName, undefined, 1000, undefined, { addHostAsPlayer: true, isPublic: true });
    }

    public async createRoom(hostId: string, hostName: string, sessionId?: string, buyInAmount: number = 1000, customRoomId?: string, options: { addHostAsPlayer?: boolean, isPublic?: boolean, hostUid?: string, isTournament?: boolean, minBuyIn?: number, maxBuyIn?: number, smallBlind?: number, bigBlind?: number, clubId?: string, sellerId?: string, role?: 'admin' | 'club_owner' | 'seller' | 'player' } = {}): Promise<Room> {
        const roomId = customRoomId || this.generateRoomId();
        const { addHostAsPlayer = true, isPublic = true, hostUid, isTournament = false, minBuyIn = 1000, maxBuyIn = 10000, smallBlind = 10, bigBlind = 20, clubId, sellerId, role = 'player' } = options;

        if (this.rooms.has(roomId)) throw new Error(`Room ${roomId} already exists`);

        const players: Player[] = [];
        if (addHostAsPlayer) {
            players.push({
                id: hostId,
                name: hostName,
                chips: buyInAmount,
                isFolded: false,
                currentBet: 0,
                pokerSessionId: sessionId,
                totalRakePaid: 0,
                status: 'PLAYING',
                uid: hostUid || hostId
            });
        }

        const newRoom: Room = {
            id: roomId,
            players: players,
            maxPlayers: 8,
            gameState: 'waiting',
            pot: 0,
            communityCards: [],
            currentTurn: players.length > 0 ? players[0].id : '',
            dealerId: players.length > 0 ? players[0].id : '',
            isPublic: isPublic,
            hostId: hostUid || hostId,
            isTournament: isTournament,
            minBuyIn: minBuyIn,
            maxBuyIn: maxBuyIn,
            clubId: clubId,
            sellerId: sellerId
        };

        // Create immutable TableConfig and attach to Room
        try {
            newRoom.tableConfig = createTableConfig(minBuyIn, maxBuyIn, smallBlind, bigBlind);
            console.log(`📋 [ROOM] TableConfig created: SB=${smallBlind}, BB=${bigBlind}, Min=${minBuyIn}, Max=${maxBuyIn}`);
        } catch (err: any) {
            console.warn(`⚠️ [ROOM] TableConfig validation warning: ${err.message}. Using raw values.`);
        }

        this.rooms.set(roomId, newRoom);
        const game = new PokerGame();
        game.setTableConfig(minBuyIn, maxBuyIn, smallBlind, bigBlind);
        this.games.set(roomId, game);

        // 🔒 PERSIST TO FIRESTORE (prevents null errors in frontend)
        try {
            const db = admin.firestore();
            await db.collection('poker_tables').doc(roomId).set({
                roomId: roomId,
                hostId: hostUid || hostId,
                isPublic: isPublic,
                isTournament: isTournament || false,
                maxPlayers: 8,
                minBuyIn: minBuyIn,
                maxBuyIn: maxBuyIn,
                smallBlind: smallBlind,
                bigBlind: bigBlind,
                clubId: clubId || null,
                sellerId: sellerId || null,
                status: 'waiting',
                players: players.map(p => ({
                    id: p.id,
                    uid: p.uid,
                    name: p.name,
                    chips: p.chips
                })),
                activePlayers: players.map(p => p.id),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                lastActionTime: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`✅ [FIRESTORE] Room ${roomId} persisted to database`);
        } catch (err) {
            console.error(`❌ [FIRESTORE] Failed to persist room ${roomId}:`, err);
            // Continue anyway - room exists in memory
        }

        console.log(`✅ Room created: ${roomId}`);
        return newRoom;
    }

    public joinRoom(roomId: string, playerId: string, playerName: string, sessionId?: string, buyInAmount: number = 1000, uid?: string, metadata?: { role?: 'admin' | 'club_owner' | 'seller' | 'player', clubId?: string, sellerId?: string }): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        // 1. Check for existing player by Socket ID (Standard check)
        const existingPlayerById = room.players.find(p => p.id === playerId);
        if (existingPlayerById) {
            if (sessionId) existingPlayerById.pokerSessionId = sessionId;
            return room;
        }

        // 2. Check for existing player by UID (Reconnection check)
        if (uid) {
            const existingPlayerByUid = room.players.find(p => p.uid === uid);
            if (existingPlayerByUid) {
                console.log(`♻️ RECONNECTION DETECTED: Player ${existingPlayerByUid.name} (UID: ${uid}) reconnected.`);
                console.log(`   Old Socket ID: ${existingPlayerByUid.id}`);
                console.log(`   New Socket ID: ${playerId}`);

                // Update ID in Room
                const oldId = existingPlayerByUid.id;
                existingPlayerByUid.id = playerId;

                // 🔄 RECONNECT: Clear disconnect timer if exists
                if (this.disconnectTimers.has(oldId)) {
                    console.log(`⏱️ Clearing disconnect timer for ${oldId} (New ID: ${playerId})`);
                    clearTimeout(this.disconnectTimers.get(oldId)!);
                    this.disconnectTimers.delete(oldId);
                }
                // Also check if timer was set on the new ID (unlikely but safe)
                if (this.disconnectTimers.has(playerId)) {
                    clearTimeout(this.disconnectTimers.get(playerId)!);
                    this.disconnectTimers.delete(playerId);
                }

                // Update ID in Game Instance
                const game = this.games.get(roomId);
                if (game) {
                    game.updatePlayerId(oldId, playerId);
                }

                if (sessionId) existingPlayerByUid.pokerSessionId = sessionId;
                return room;
            }
        }

        if (room.players.length >= room.maxPlayers) throw new Error('Room is full');

        // 🔥 FORCE STATUS: If game is already playing, new players must wait
        const isGameActive = room.gameState === 'playing';
        let initialStatus: 'PLAYING' | 'WAITING_FOR_NEXT_HAND' | 'spectator';

        if (buyInAmount <= 0) {
            initialStatus = 'spectator';
        } else if (isGameActive) {
            initialStatus = 'WAITING_FOR_NEXT_HAND'; // 🔒 Mid-game join protection
            console.log(`[JOIN_ROOM] ⏳ Player ${playerName} joining mid-game. Status: WAITING_FOR_NEXT_HAND`);
        } else {
            initialStatus = 'PLAYING';
        }
        const isSeated = (buyInAmount > 0);

        const newPlayer: Player = {
            id: playerId,
            uid: uid,
            name: playerName,
            chips: buyInAmount,
            status: initialStatus, // ✅ DYNAMIC STATUS BASED ON GAME STATE
            isSeated: isSeated,
            isFolded: false,
            currentBet: 0,
            pokerSessionId: sessionId,
            totalRakePaid: 0
        };

        room.players.push(newPlayer);

        console.log(`[JOIN_ROOM] ✅ Player added: ${playerName} | UID: ${uid || 'N/A'} | Socket: ${playerId} | Status: ${initialStatus}`);

        // 🔥 SYNC TO FIRESTORE IMMEDIATELY (Critical Fix for Spectator Mode Bug)
        // This ensures poker_tables collection is updated with player status='active'
        setImmediate(async () => {
            try {
                const db = admin.firestore();
                await db.collection('poker_tables').doc(roomId).set({
                    players: room.players.map(p => {
                        const mappedStatus = p.status || 'active';
                        console.log(`[JOIN_ROOM] 🔍 Syncing player ${p.name} (${p.uid}) to Firestore with status: ${mappedStatus}`);
                        return {
                            id: p.uid || p.id,  // Prefer UID for consistency
                            uid: p.uid,
                            name: p.name,
                            chips: p.chips,
                            status: mappedStatus, // Default to active if missing
                            isSeated: p.isSeated !== undefined ? p.isSeated : true,
                            currentBet: p.currentBet || 0,
                            isFolded: p.isFolded || false
                        };
                    }),
                    activePlayers: room.players
                        .filter(p => p.uid && p.status !== 'spectator')  // Only include active players with UID
                        .map(p => p.uid!),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });

                console.log(`[JOIN_ROOM] ✅ Synced to Firestore: poker_tables/${roomId} (${room.players.length} players)`);
            } catch (err) {
                console.error(`[JOIN_ROOM] ❌ Failed to sync to Firestore:`, err);
                // Continue anyway - socket state is source of truth
            }
        });

        return room;
    }

    public removePlayer(playerId: string): { roomId: string, player: Player } | null {
        // Clear disconnect timer if exists
        if (this.disconnectTimers.has(playerId)) {
            clearTimeout(this.disconnectTimers.get(playerId)!);
            this.disconnectTimers.delete(playerId);
        }

        for (const [roomId, room] of this.rooms) {
            const index = room.players.findIndex(p => p.id === playerId);
            if (index !== -1) {
                const player = room.players[index];
                room.players.splice(index, 1);

                const game = this.games.get(roomId);
                if (game) game.removePlayer(playerId);

                if (room.players.length === 0) {
                    this.deleteRoom(roomId);
                }

                return { roomId, player };
            }
        }
        return null;
    }

    public toggleReady(roomId: string, playerId: string, isReady: boolean): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;
        const player = room.players.find(p => p.id === playerId);
        if (player) {
            player.isReady = isReady;
            this.checkAndStartCountdown(roomId);
        }
        return room;
    }

    private checkAndStartCountdown(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room || room.isPublic === false) return;
        room.players.forEach(p => { if (p.isBot) p.isReady = true; });

        const readyCount = room.players.filter(p => p.isReady).length;
        if (room.players.length >= 2 && readyCount === room.players.length) {
            if (this.countdownTimers.has(roomId)) return;
            if (this.emitCallback) this.emitCallback(roomId, 'countdown_start', { seconds: 3 });

            const timer = setTimeout(() => {
                this.countdownTimers.delete(roomId);
                if (room.players.length > 0) {
                    this.startGame(roomId, room.players[0].id, (data) => {
                        if (this.emitCallback) {
                            if (data.type === 'hand_winner') this.emitCallback!(roomId, 'hand_winner', data);
                            else this.emitCallback!(roomId, 'game_update', data);
                        }
                    });
                }
            }, 3000);
            this.countdownTimers.set(roomId, timer);
        } else {
            if (this.countdownTimers.has(roomId)) {
                clearTimeout(this.countdownTimers.get(roomId)!);
                this.countdownTimers.delete(roomId);
                if (this.emitCallback) this.emitCallback(roomId, 'countdown_cancel', {});
            }
        }
    }
    private countdownTimers: Map<string, NodeJS.Timeout> = new Map();

    public getRoom(roomId: string): Room | undefined {
        return this.rooms.get(roomId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LÓGICA CRÍTICA DE GESTIÓN DE JUEGO Y LIQUIDACIÓN
    // ═══════════════════════════════════════════════════════════════════════════

    public startGame(roomId: string, playerId: string, emitCallback?: (data: any) => void) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);

        if (!room || !game) throw new Error('Room or game not found');

        if (emitCallback) {
            // 🔐 SECURITY FIX: Emit personalized game states to each player
            // Instead of broadcasting the same state to everyone, send each player
            // their own version where they can see their cards but others are hidden
            game.onGameStateChange = (data?: any) => {
                // If specific event data is provided (e.g., hand_results), use it!
                if (data && data.type) {
                    if (data.type === 'hand_results' || data.type === 'hand_winner') {
                        // Broadcast hand results to everyone (it's public info at showdown)
                        if (emitCallback) emitCallback(data);
                    } else {
                        // Forward other specific events
                        if (emitCallback) emitCallback(data);
                    }
                    return; // ✅ IMPORTANTE: Detener ejecución para evitar el bucle de game_update
                }

                // Default behavior: Send personalized game_update
                // Iterate over all players in the room and send personalized states
                room.players.forEach(player => {
                    if (player.uid || player.id) {
                        // Get personalized state for this specific player
                        const personalizedState = game.getPublicState(player.uid || player.id);

                        // Emit to this specific player's socket
                        // The emitCallback signature in startGame only accepts 1 argument (data)
                        // so we pass the state, and let the callback handle logic if needed.
                        // However, strictly speaking, index.ts logic re-calculates/iterates.
                        // To preserve behavior and fix TS error:
                        if (emitCallback) emitCallback(personalizedState);
                    }
                });
            };
        }

        // Configuración de Eventos del Sistema (Victoria por Abandono / Rebuys)
        game.onSystemEvent = async (event, data) => {
            console.log(`🔧 System Event in Room ${roomId}: ${event}`, data);

            if (event === 'TABLE_CLOSED') {
                console.log(`🔒 TABLE_CLOSED received for ${roomId}. Reason: ${data.reason}`);

                // 1. Notificar a los clientes
                if (this.emitCallback) {
                    this.emitCallback(roomId, 'room_closed', {
                        reason: data.reason,
                        winnerUid: data.winnerUid,
                        finalChips: data.finalChips
                    });
                }

                // 2. Ejecutar Liquidación REAL
                await this.closeTableAndCashOut(roomId);
            }

            if (event === 'game_finished') {
                if (data.reason === 'last_man_standing' || data.reason === 'walkover') {
                    console.log(`🏆 Last Man Standing: ${data.winnerId}. Iniciando liquidación...`);
                    // ... preserve legacy logic if needed, but table_closed handles most
                    // If 'table_closed' is emitted by PokerGame, this might be redundant, but we keep it for now.
                }
            }

            if (event === 'player_needs_rebuy') {
                if (this.emitCallback) this.emitCallback(roomId, 'player_needs_rebuy', data);
            }
            if (event === 'kick_player') {
                const { playerId } = data;
                this.removePlayer(playerId);
                if (this.emitCallback) this.emitCallback(roomId, 'force_disconnect', { playerId });
            }
        };

        // 🔥 CRITICAL FIX: Pass roomId to PokerGame to prevent "table ." errors
        game.startGame(room.players, room.isPublic, roomId, room.clubId, room.sellerId);
        room.gameState = 'playing';

        if (this.emitCallback) {
            // 🔐 SECURITY: This triggers the SMART EMISSION logic in index.ts (lines 106-132)
            // which sends personalized states to each player
            this.emitCallback(roomId, 'game_started', { roomId });
        }

        return game.getGameState();
    }

    /**
     * LIQUIDACIÓN REAL SERVIDOR -> FIRESTORE
     * Ejecuta una transacción ACID para asegurar que el dinero pase de la mesa a la billetera.
     */
    /**
     * LIQUIDACIÓN ATÓMICA SERVIDOR -> FIRESTORE
     * Ejecuta una transacción ACID para asegurar que el dinero pase de la mesa a la billetera.
     */
    public async liquidateTableAtomic(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room) {
            console.warn(`⚠️ Intento de liquidar mesa inexistente en RAM: ${roomId}`);
            // Intentar marcar en DB como cerrada de todos modos si existe
            return;
        }

        console.log(`🔒 EJECUTANDO LIQUIDACIÓN ATÓMICA PARA MESA ${roomId}`);
        console.log(`🔒 Jugadores en mesa: ${room.players.length}`);

        try {
            const db = admin.firestore();

            // 1. Preparar Autoridad de Jugadores (Socket -> UID válido)
            // Mapa crítico para evitar usar socketId en /users
            const playerAuthorityMap: Map<string, string> = new Map();
            const playersToRefund: { uid: string, chips: number, sessionId?: string, name: string }[] = [];

            for (const p of room.players) {
                if (p.isBot) continue;

                // CRÍTICO: Si no hay UID, buscarlo por todos los medios o loguear error fatal
                if (!p.uid) {
                    console.error(`❌ CRITICAL: Player ${p.name} (${p.id}) has no UID. Skipping liquidation for this user! FUNDS AT RISK.`);
                    continue;
                }

                playerAuthorityMap.set(p.id, p.uid);

                // Preparar datos para la transacción (Lectura en memoria)
                if (p.chips > 0 || p.pokerSessionId) {
                    playersToRefund.push({
                        uid: p.uid,
                        chips: p.chips,
                        sessionId: p.pokerSessionId,
                        name: p.name
                    });
                }
            }

            if (this.emitCallback) {
                this.emitCallback(roomId, 'room_closed', {
                    reason: 'Game Finished',
                    message: 'Partida finalizada. Transfiriendo fondos...'
                });
            }

            // 2. Transacción ACID (Todo o Nada)
            await db.runTransaction(async (transaction) => {
                const timestamp = admin.firestore.FieldValue.serverTimestamp();
                const tableRef = db.collection('poker_tables').doc(roomId);
                const tableDoc = await transaction.get(tableRef);

                if (!tableDoc.exists) {
                    // Si la mesa no existe en DB, es un estado inconsistente grave.
                    // Pero si tenemos los datos en RAM, ¿deberíamos intentar devolver los fondos de todos modos?
                    // Por seguridad, sí. Usaremos los datos de RAM.
                    console.warn(`⚠️ Table ${roomId} not found in DB during liquidation. Proceeding with RAM data.`);
                }

                // A. Procesar Devoluciones
                for (const player of playersToRefund) {
                    const userRef = db.collection('users').doc(player.uid); // USAR UID, NO SOCKET ID
                    const sessionRef = player.sessionId ? db.collection('poker_sessions').doc(player.sessionId) : null;
                    const finalStack = player.chips;

                    // Update User Wallet
                    transaction.update(userRef, {
                        moneyInPlay: 0,                // Reset lock
                        currentTableId: null,          // Free user
                        credit: admin.firestore.FieldValue.increment(finalStack), // Return funds
                        lastUpdated: timestamp
                    });

                    // Close Session History
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: finalStack,
                            endTime: timestamp,
                            closedReason: 'server_atomic_liquidation'
                        });
                    }

                    // Ledger Entry (Audit) - Solo si hay devolución real > 0
                    if (finalStack > 0) {
                        const ledgerRef = db.collection('financial_ledger').doc();
                        transaction.set(ledgerRef, {
                            type: 'TABLE_RETURN',
                            uid: player.uid,
                            tableId: roomId,
                            amount: finalStack,
                            timestamp: timestamp,
                            description: `Return from table ${roomId} (Atomic)`,
                            metadata: {
                                sessionId: player.sessionId || null,
                                playerName: player.name
                            }
                        });
                    }

                    console.log(`💰 [ATOMIC] Scheduled return for ${player.name} (${player.uid}): +${finalStack}`);
                }

                // B. Cerrar Mesa
                transaction.set(tableRef, {
                    status: 'FINISHED',
                    players: [], // Clear players
                    activePlayers: [],
                    lastUpdated: timestamp,
                    closedAt: timestamp
                }, { merge: true });
            });

            console.log(`✅ Liquidación Atómica Completada para ${roomId}`);

            // 3. SOLO AHORA BORRAMOS DE MEMORIA
            this.deleteRoom(roomId);

        } catch (error) {
            console.error(`❌ ERROR CRÍTICO EN LIQUIDACIÓN ATÓMICA (${roomId}):`, error);
            console.error(`⚠️ LA SALA NO SERÁ BORRADA DE LA MEMORIA PARA PERMITIR REINTENTOS.`);
            // NO llamar a deleteRoom(roomId) aquí.
            // Esto permitirá que un administrador o un cron de "resguardo" reintente la operación.
        }
    }

    // Alias wrapper for compatibility
    public async closeTableAndCashOut(roomId: string) {
        return this.liquidateTableAtomic(roomId);
    }

    public handleGameAction(roomId: string, playerId: string, action: 'bet' | 'call' | 'fold' | 'check' | 'allin', amount?: number) {
        const game = this.games.get(roomId);
        if (!game) throw new Error('Game not found');
        game.handleAction(playerId, action, amount);
        return game.getGameState();
    }

    public getGameState(roomId: string) {
        const game = this.games.get(roomId);
        return game ? game.getGameState() : null;
    }

    public getPlayerState(roomId: string, playerId: string) {
        const game = this.games.get(roomId);
        if (!game) return null;
        // Allows passing either UID or Socket ID (assuming PokerGame handles it, currently it expects UID)
        return game.getPublicState(playerId);
    }

    public deleteRoom(roomId: string) {
        const game = this.games.get(roomId);
        if (game && (game as any).turnTimer) clearTimeout((game as any).turnTimer);
        this.rooms.delete(roomId);
        this.games.delete(roomId);
        console.log(`🗑️ Room ${roomId} deleted from RAM.`);
    }

    public addChips(roomId: string, playerId: string, amount: number) {
        const game = this.games.get(roomId);
        if (game) game.addChips(playerId, amount);
    }

    public handleDisconnect(playerId: string) {
        // Find room and player
        for (const [roomId, room] of this.rooms) {
            const player = room.players.find(p => p.id === playerId);
            if (player) {
                console.log(`🔌 Player ${player.name} (${playerId}) disconnected. Starting grace period timer (${this.DISCONNECT_GRACE_PERIOD_MS}ms).`);

                // If timer already exists, define logic (refresh it?)
                if (this.disconnectTimers.has(playerId)) {
                    clearTimeout(this.disconnectTimers.get(playerId)!);
                }

                const timer = setTimeout(() => {
                    console.log(`🔌 Grace period expired for ${player.name} (${playerId}). Removing from room.`);
                    this.disconnectTimers.delete(playerId);

                    const result = this.removePlayer(playerId);

                    if (result && this.emitCallback) {
                        // Notify index.ts to handle Exit Fees and Socket events
                        this.emitCallback(roomId, 'player_timeout_leave', {
                            playerId,
                            player: result.player,
                            roomId
                        });

                        // Notify Room
                        this.emitCallback(roomId, 'player_left', {
                            id: playerId,
                            reason: 'timeout'
                        });
                    }
                }, this.DISCONNECT_GRACE_PERIOD_MS);

                this.disconnectTimers.set(playerId, timer);
                return;
            }
        }
    }

    private generateRoomId(): string {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}

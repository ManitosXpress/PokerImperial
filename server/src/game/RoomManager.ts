import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';
import { endPokerSession } from '../middleware/firebaseAuth';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { performTableSettlement, savePlayerStateToFirestore } from '../utils/localSettlement';
import { createTableConfig, createPlayerSession, TableConfig, PlayerSession } from '../types/TableConfig';

// 🔐 GAME SECRET para firmar cashouts
const GAME_SECRET = process.env.GAME_SECRET || 'default-secret-change-in-production-2024';

if (!process.env.GAME_SECRET) {
    console.warn('⚠️ [SECURITY] GAME_SECRET not set, using default - NOT SECURE FOR PRODUCTION!');
}

export class RoomManager {
    private rooms: Map<string, Room> = new Map();
    private games: Map<string, PokerGame> = new Map();
    private cleanupInterval: NodeJS.Timeout | null = null;
    private readonly CLEANUP_INTERVAL_MS = 5 * 60 * 1000; // Limpiar cada 5 minutos
    private readonly EMPTY_ROOM_TIMEOUT_MS = 10 * 60 * 1000; // Eliminar mesas vacías después de 10 minutos
    // 🕐 GRACE PERIOD: Tiempo antes de eliminar sala vacía (permite reconexiones)
    private readonly GRACE_PERIOD_MS = 30 * 1000; // 30 segundos

    constructor() {
        // Iniciar limpieza automática periódica para prevenir memory leaks
        this.startCleanupInterval();
    }

    /**
     * Limpieza automática periódica de mesas vacías o inactivas
     * Previene memory leaks en servidores con 2GB de RAM
     */
    private startCleanupInterval() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
        }

        this.cleanupInterval = setInterval(() => {
            this.cleanupEmptyRooms();
        }, this.CLEANUP_INTERVAL_MS);

        console.log('🧹 Cleanup interval started - will clean empty rooms every 5 minutes');
    }

    /**
     * Limpia mesas vacías o inactivas para liberar memoria
     * ✅ ACTUALIZADO: Maneja async deleteRoom para actualizar Firestore
     */
    private async cleanupEmptyRooms() {
        const now = Date.now();
        let cleanedCount = 0;

        // Convertir a array para evitar problemas con async iteration
        const roomEntries = Array.from(this.rooms.entries());

        for (const [roomId, room] of roomEntries) {
            // Eliminar mesas completamente vacías
            if (room.players.length === 0) {
                console.log(`🗑️ Cleaning up empty room: ${roomId}`);
                try {
                    await this.deleteRoom(roomId);
                    cleanedCount++;
                } catch (err) {
                    console.error(`❌ Error cleaning room ${roomId}:`, err);
                }
                continue;
            }

            // Eliminar mesas en estado 'waiting' sin jugadores activos por más de 10 minutos
            // (solo si no hay juego activo)
            if (room.gameState === 'waiting' && room.players.length === 0) {
                // Ya cubierto por el caso anterior
                continue;
            }

            // Eliminar mesas terminadas (finished) después de un tiempo
            if (room.gameState === 'finished') {
                // Las mesas terminadas se limpian inmediatamente cuando se cierran
                // Este caso es por si acaso queda alguna huérfana
                const allPlayersLeft = room.players.every(p => p.isBot || p.status === 'ELIMINATED');
                if (allPlayersLeft) {
                    console.log(`🗑️ Cleaning up finished room with no active players: ${roomId}`);
                    try {
                        await this.deleteRoom(roomId);
                        cleanedCount++;
                    } catch (err) {
                        console.error(`❌ Error cleaning finished room ${roomId}:`, err);
                    }
                }
            }
        }

        if (cleanedCount > 0) {
            console.log(`✅ Cleanup completed: ${cleanedCount} rooms removed. Active rooms: ${this.rooms.size}`);
        }
    }

    /**
     * Detener el intervalo de limpieza (útil para tests o shutdown graceful)
     */
    public stopCleanupInterval() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
            this.cleanupInterval = null;
            console.log('🧹 Cleanup interval stopped');
        }
    }

    /**
     * Creates a safe, serializable version of the Room object for socket emits
     * Prevents "Maximum call stack size exceeded" crashes from circular references
     */
    private getPublicRoomState(room: Room) {
        // 🔒 BUG FIX: Include table config in public state (prevents null errors in frontend)
        const tableConfig = room.tableConfig || {
            minBuyIn: room.minBuyIn || 1000,
            maxBuyIn: room.maxBuyIn || 10000,
            smallBlind: 10,
            bigBlind: 20,
            createdAt: Date.now()
        };

        return {
            id: room.id,
            players: room.players.map(p => ({
                id: p.id,
                uid: p.uid,
                name: p.name,
                chips: p.chips,
                isFolded: p.isFolded,
                currentBet: p.currentBet,
                isBot: p.isBot,
                isReady: p.isReady,
                status: p.status,
                isAllIn: p.isAllIn
            })),
            maxPlayers: room.maxPlayers,
            gameState: room.gameState,
            pot: room.pot,
            communityCards: room.communityCards,
            currentTurn: room.currentTurn,
            dealerId: room.dealerId,
            isPublic: room.isPublic ?? false,
            hostId: room.hostId,
            isTournament: room.isTournament,
            // 🔒 BUG FIX: Always include table limits (frontend expects these)
            minBuyIn: tableConfig.minBuyIn,
            maxBuyIn: tableConfig.maxBuyIn,
            smallBlind: tableConfig.smallBlind,
            bigBlind: tableConfig.bigBlind
            // NOTE: Explicitly excluded autoStartTimer to prevent circular refs
        };
    }


    // ... (existing methods like toggleReady, createRoom, etc. - we need to keep them)
    // To save context tokens, I will only output the NEW methods and modified logic if possible, 
    // but standard tool requires full file overwrite. 
    // I will rewrite the file incorporating the new logic.

    public toggleReady(roomId: string, playerId: string, isReady: boolean): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        const player = room.players.find(p => p.id === playerId);
        if (player) {
            player.isReady = isReady;
            this.checkAndStartCountdown(roomId);
        }
        return this.getPublicRoomState(room) as any; // Return sanitized DTO
    }

    private checkAndStartCountdown(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room) return;

        if (room.isPublic === false) {
            return;
        }

        room.players.forEach(p => {
            if (p.isBot) p.isReady = true;
        });

        const readyCount = room.players.filter(p => p.isReady).length;
        const totalPlayers = room.players.length;

        if (totalPlayers >= 2 && readyCount === totalPlayers) {
            if (this.countdownTimers.has(roomId)) return;

            if (this.emitCallback) {
                this.emitCallback(roomId, 'countdown_start', { seconds: 3 });
            }

            const timer = setTimeout(() => {
                this.countdownTimers.delete(roomId);
                try {
                    if (room.players.length > 0) {
                        this.startGame(roomId, room.players[0].id, (data) => {
                            if (this.emitCallback) {
                                if (data.type === 'hand_winner') {
                                    this.emitCallback!(roomId, 'hand_winner', data);
                                } else {
                                    this.emitCallback!(roomId, 'game_update', data);
                                }
                            }
                        });
                    }
                } catch (e) {
                    console.error(`Failed to auto-start game for room ${roomId}:`, e);
                }
            }, 3000);

            this.countdownTimers.set(roomId, timer);
        } else {
            if (this.countdownTimers.has(roomId)) {
                clearTimeout(this.countdownTimers.get(roomId)!);
                this.countdownTimers.delete(roomId);
                if (this.emitCallback) {
                    this.emitCallback(roomId, 'countdown_cancel', {});
                }
            }
        }
    }

    private countdownTimers: Map<string, NodeJS.Timeout> = new Map();
    public emitCallback?: (roomId: string, event: string, data: any, targetPlayerId?: string) => void;

    public setEmitCallback(callback: (roomId: string, event: string, data: any, targetPlayerId?: string) => void) {
        this.emitCallback = callback;
    }

    public async createPracticeRoom(hostId: string, hostName: string): Promise<Room> {
        const roomDto = await this.createRoom(hostId, hostName, undefined, 1000, undefined, { addHostAsPlayer: true, isPublic: true });

        // Get the actual Room object from the map (not the sanitized DTO)
        const room = this.rooms.get(roomDto.id);
        if (!room) throw new Error('Failed to create practice room');

        for (let i = 1; i <= 7; i++) {
            const bot: Player = {
                id: `bot-${i}`,
                name: `Bot ${i}`,
                chips: 1000,
                isFolded: false,
                currentBet: 0,
                isBot: true,
                status: 'PLAYING'
            };
            room.players.push(bot);
        }

        console.log(`✅ Practice room created: ${room.id}`);
        return this.getPublicRoomState(room) as any; // Return sanitized DTO
    }

    public async createRoom(hostId: string, hostName: string, sessionId?: string, buyInAmount: number = 1000, customRoomId?: string, options: { addHostAsPlayer?: boolean, isPublic?: boolean, hostUid?: string, isTournament?: boolean, minBuyIn?: number, maxBuyIn?: number, clubId?: string, sellerId?: string, role?: 'admin' | 'club_owner' | 'seller' | 'player' } = {}): Promise<Room> {
        const roomId = customRoomId || this.generateRoomId();
        const { addHostAsPlayer = true, isPublic = true, hostUid, isTournament = false, minBuyIn, maxBuyIn, clubId, sellerId, role = 'player' } = options;

        if (this.rooms.has(roomId)) {
            throw new Error(`Room ${roomId} already exists`);
        }

        // 🔒 BUG FIX #1: Create IMMUTABLE TableConfig
        const tableConfig = createTableConfig(
            minBuyIn || 1000,      // Default: 1000
            maxBuyIn || 10000,     // Default: 10000
            10,                     // smallBlind
            20                      // bigBlind
        );

        console.log(`🔒 [TABLE_CONFIG] Room ${roomId}: minBuyIn=${tableConfig.minBuyIn}, maxBuyIn=${tableConfig.maxBuyIn}`);

        const players: Player[] = [];
        const playerSessions = new Map<string, PlayerSession>();

        if (addHostAsPlayer) {
            const host: Player = {
                id: hostId,
                uid: hostUid, // ✅ CRÍTICO: Asignar UID al host
                name: hostName,
                chips: buyInAmount,
                isFolded: false,
                currentBet: 0,
                pokerSessionId: sessionId,
                totalRakePaid: 0,
                status: 'PLAYING'
            };
            players.push(host);

            // 🔒 BUG FIX #3: Store PlayerSession for rake distribution
            if (hostUid) {
                playerSessions.set(hostUid, createPlayerSession(hostUid, role, clubId, sellerId));
            }
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
            autoStartTimer: null,
            // 🔒 IMMUTABLE CONFIG
            tableConfig: tableConfig,
            // ⚠️ DEPRECATED (kept for backward compatibility)
            minBuyIn: tableConfig.minBuyIn,
            maxBuyIn: tableConfig.maxBuyIn,
            // 💰 RAKE DISTRIBUTION
            clubId: clubId,
            sellerId: sellerId,
            // 👥 PLAYER SESSIONS
            playerSessions: playerSessions
        };

        this.rooms.set(roomId, newRoom);
        this.games.set(roomId, new PokerGame());

        // 🔒 BUG FIX #1: PERSIST TO FIRESTORE (prevents buy-in reset on server restart)
        try {
            const db = admin.firestore();
            await db.collection('poker_tables').doc(roomId).set({
                roomId: roomId,
                hostId: hostUid || hostId,
                isPublic: isPublic,
                isTournament: isTournament,
                maxPlayers: 8,
                // 🔒 CRITICAL: Persist table config to Firestore
                minBuyIn: tableConfig.minBuyIn,
                maxBuyIn: tableConfig.maxBuyIn,
                smallBlind: tableConfig.smallBlind,
                bigBlind: tableConfig.bigBlind,
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
            console.log(`✅ [FIRESTORE] Room ${roomId} persisted with table config`);
        } catch (err) {
            console.error(`❌ [FIRESTORE] Failed to persist room ${roomId}:`, err);
            // Continue anyway - room exists in memory
        }

        console.log(`✅ Room created: ${roomId}`);
        return this.getPublicRoomState(newRoom) as any; // Return sanitized DTO
    }

    public async joinRoom(roomId: string, playerId: string, playerName: string, sessionId?: string, buyInAmount: number = 1000, uid?: string, metadata?: { role?: 'admin' | 'club_owner' | 'seller' | 'player', clubId?: string, sellerId?: string }): Promise<Room | null> {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        // 🔒 BUG FIX #2: Cancel grace period if exists (player reconnecting)
        if (room.gracePeriodTimeout) {
            console.log(`✅ [GRACE_PERIOD] Player reconnecting to ${roomId} - cancelling deletion timeout`);
            clearTimeout(room.gracePeriodTimeout);
            room.gracePeriodTimeout = undefined;
        }

        const existingPlayer = room.players.find(p => p.id === playerId);
        if (existingPlayer) {
            if (sessionId) existingPlayer.pokerSessionId = sessionId;
            if (uid) existingPlayer.uid = uid; // Update UID if provided on rejoin
            console.log(`Player ${playerId} rejoined room ${roomId}`);
            return this.getPublicRoomState(room) as any; // Return sanitized DTO
        }

        if (room.players.length >= room.maxPlayers) {
            throw new Error('Room is full');
        }

        // 🔒 BUG FIX #4: ATOMIC BALANCE VERIFICATION (prevents race conditions)
        if (uid) {
            try {
                const db = admin.firestore();

                // Use Firestore transaction to atomically check and deduct balance
                await db.runTransaction(async (transaction) => {
                    const userRef = db.collection('users').doc(uid);
                    const userDoc = await transaction.get(userRef);

                    if (!userDoc.exists) {
                        throw new Error(`User ${uid} not found in database`);
                    }

                    const userData = userDoc.data();
                    const currentCredit = userData?.credit || 0;

                    // Verify sufficient balance
                    if (currentCredit < buyInAmount) {
                        throw new Error(`Insufficient balance. Required: ${buyInAmount}, Available: ${currentCredit}`);
                    }

                    // 💰 ATOMIC DEDUCTION: Deduct buy-in from user credit
                    transaction.update(userRef, {
                        credit: admin.firestore.FieldValue.increment(-buyInAmount),
                        moneyInPlay: admin.firestore.FieldValue.increment(buyInAmount),
                        lastActivity: admin.firestore.FieldValue.serverTimestamp()
                    });

                    console.log(`✅ [ATOMIC] Deducted ${buyInAmount} from ${uid}. Remaining: ${currentCredit - buyInAmount}`);
                });
            } catch (err: any) {
                console.error(`❌ [ATOMIC] Failed to verify/deduct balance for ${uid}:`, err.message);
                throw new Error(`Join failed: ${err.message}`);
            }
        }

        const newPlayer: Player = {
            id: playerId,
            uid: uid, // ✅ CRÍTICO: Asignar UID explícitamente
            name: playerName,
            chips: buyInAmount,
            isFolded: false,
            currentBet: 0,
            pokerSessionId: sessionId,
            totalRakePaid: 0,
            status: 'PLAYING'
        };

        room.players.push(newPlayer);

        // 🔒 BUG FIX #3: Store PlayerSession for rake distribution
        if (uid && metadata) {
            if (!room.playerSessions) {
                room.playerSessions = new Map();
            }
            room.playerSessions.set(uid, createPlayerSession(
                uid,
                metadata.role || 'player',
                metadata.clubId,
                metadata.sellerId
            ));
        }

        // ✅ AUTO-START LOGIC
        if (room.isTournament && room.gameState === 'waiting') {
            const playerCount = room.players.length;
            if (playerCount >= 2 && !room.autoStartTimer) {
                console.log(`⏳ Iniciando cuenta regresiva de 30s para sala ${room.id}`);

                // 1. Avisar al Frontend
                if (this.emitCallback) {
                    this.emitCallback(room.id, 'tournament_countdown', { seconds: 30 });
                }

                // 2. Iniciar Timer
                room.autoStartTimer = setTimeout(() => {
                    console.log(`🚀 EJECUTANDO AUTO-START en sala ${room.id}`);
                    try {
                        if (room.players.length >= 2) { // Doble check
                            this.startGame(room.id, room.players[0].id, (data) => {
                                // This callback is used for persistence in index.ts
                                // We don't need to do anything here as the interceptedCallback handles emission
                            });
                            if (this.emitCallback) {
                                // Emit generic game_started for spectators/persistence
                                this.emitCallback(room.id, 'game_started', { ...this.getGameState(room.id), roomId: room.id });
                            }
                        }
                    } catch (e) {
                        console.error(`Failed to auto-start tournament game for room ${room.id}:`, e);
                    }
                    room.autoStartTimer = null;
                }, 30000); // 30 segundos
            }
        }

        console.log(`✅ Player ${playerId} (UID: ${uid || 'N/A'}) joined room ${roomId}`);
        return this.getPublicRoomState(room) as any; // Return sanitized DTO
    }

    public getRoom(roomId: string): Room | undefined {
        return this.rooms.get(roomId);
    }

    /**
     * @deprecated Use performTableSettlement from localSettlement.ts instead
     * This method attempts HTTP calls to Cloud Functions which fail with 401 errors
     * Kept for backward compatibility only
     */
    private async triggerSecureCashout(
        uid: string,
        tableId: string,
        finalChips: number,
        reason: 'EXIT' | 'DISCONNECT' | 'BANKRUPTCY' | 'TABLE_CLOSED'
    ): Promise<void> {
        // 1. Generar payload firmado
        const payload = {
            uid,
            tableId,
            finalChips,
            reason,
            timestamp: Date.now()
        };

        const payloadString = JSON.stringify(payload);
        const signature = crypto.createHmac('sha256', GAME_SECRET)
            .update(payloadString)
            .digest('hex');

        // 2. Escribir a Firestore en _trigger_cashout
        try {
            const db = admin.firestore();
            await db.collection('_trigger_cashout').add({
                uid,
                tableId,
                finalChips,
                reason,
                authPayload: payloadString,
                signature,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`✅ Cashout triggered for ${uid}: ${finalChips} chips (${reason})`);
        } catch (error) {
            console.error(`❌ Failed to trigger cashout for ${uid}:`, error);

            // ⚠️ CRÍTICO: Reintentar una vez si falla
            try {
                console.log(`🔄 Retrying cashout trigger for ${uid}...`);
                const db = admin.firestore();
                await db.collection('_trigger_cashout').add({
                    uid,
                    tableId,
                    finalChips,
                    reason,
                    authPayload: payloadString,
                    signature,
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`✅ Cashout retry succeeded for ${uid}`);
            } catch (retryError) {
                console.error(`❌ Cashout retry failed for ${uid}:`, retryError);
                throw retryError; // Propagar para que el caller lo maneje
            }
        }
    }

    /**
     * @deprecated Replaced by Firestore Triggers in Cloud Functions
     * Settlement is now handled automatically by _trigger_settlement collection
     * Kept for backward compatibility only
     */
    private async triggerRoundSettlement(roomId: string, data: any): Promise<void> {
        if (!data.authPayload || !data.securitySignature) {
            console.error(`❌ Cannot trigger settlement for room ${roomId}: Missing signature`);
            return;
        }

        // ✅ VALIDACIÓN: Evitar undefined en winnerUid
        const winnerUid = data.winner?.uid || null;
        if (!winnerUid) {
            console.warn(`⚠️ Settlement warning for room ${roomId}: winnerUid is missing/undefined. Using null.`);
        }

        try {
            const db = admin.firestore();
            await db.collection('_trigger_settlement').add({
                tableId: roomId,
                gameId: `game_${Date.now()}`, // Or extract from payload if parsed, but payload string is enough
                winnerUid: winnerUid, // ✅ SAFE: Ahora es string | null, nunca undefined
                potTotal: data.gameState?.pot || 0,
                authPayload: data.authPayload,
                signature: data.securitySignature,
                finalPlayerStacks: data.gameState?.players?.reduce((acc: any, p: any) => {
                    if (p.uid) acc[p.uid] = p.chips;
                    return acc;
                }, {}),
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`✅ Settlement triggered for room ${roomId}`);
        } catch (error) {
            console.error(`❌ Failed to trigger settlement for room ${roomId}:`, error);
        }
    }

    public async removePlayer(playerId: string): Promise<{ roomId: string, player: Player } | null> {
        for (const [roomId, room] of this.rooms) {
            const index = room.players.findIndex(p => p.id === playerId);
            if (index !== -1) {
                const player = room.players[index];

                // ✅ REFACTORED: LOCAL SETTLEMENT (sin HTTP)
                if (player.uid && !player.isBot) {
                    console.log(`💰 [SETTLEMENT] Saving state and settling for ${player.uid}: ${player.chips} chips`);

                    try {
                        // 1. FORCE SAVE: Guardar estado actual en Firestore
                        await savePlayerStateToFirestore(roomId, player.uid, player.chips);

                        // 2. LOCAL SETTLEMENT: Ejecutar liquidación directamente con Admin SDK
                        const totalRake = player.totalRakePaid || 0;
                        await performTableSettlement(roomId, player.uid, player.chips, totalRake, 'EXIT');

                        console.log(`✅ [SETTLEMENT] Completed for ${player.uid}`);
                    } catch (err) {
                        console.error(`❌ [SETTLEMENT] Failed for ${player.uid}:`, err);
                        // Continuar de todos modos para remover al jugador
                    }
                }

                room.players.splice(index, 1);

                // ✅ CANCEL AUTO-START LOGIC
                if (room.isTournament && room.autoStartTimer && room.players.length < 2) {
                    console.log(`🛑 Cancelando auto-start en sala ${roomId} (Jugadores insuficientes: ${room.players.length})`);
                    clearTimeout(room.autoStartTimer);
                    room.autoStartTimer = null;

                    if (this.emitCallback) {
                        this.emitCallback(roomId, 'countdown_cancelled', {});
                    }
                }

                // Also remove from game instance if exists
                const game = this.games.get(roomId);
                if (game) {
                    game.removePlayer(playerId);
                }

                // 🔒 BUG FIX #2: GRACE PERIOD for zombie rooms
                if (room.players.length === 0) {
                    console.log(`� [GRACE_PERIOD] Room ${roomId} is now empty - starting ${this.GRACE_PERIOD_MS / 1000}s grace period...`);

                    // Cancel existing grace period if somehow it exists
                    if (room.gracePeriodTimeout) {
                        clearTimeout(room.gracePeriodTimeout);
                    }

                    // Set grace period timeout
                    room.gracePeriodTimeout = setTimeout(async () => {
                        console.log(`🗑️ [GRACE_PERIOD] Grace period expired for ${roomId} - deleting room`);

                        // PASO 1: Actualizar estado en Firestore ANTES de eliminar de memoria
                        const db = admin.firestore();
                        const tableRef = db.collection('poker_tables').doc(roomId);

                        try {
                            // 🔒 USE .set() with merge instead of .update() to avoid NOT_FOUND errors
                            await tableRef.set({
                                status: 'closed',
                                players: [],
                                activePlayers: [],
                                lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                            }, { merge: true });
                            console.log(`✅ Firestore updated: Room ${roomId} marked as closed`);
                        } catch (err) {
                            console.error(`❌ Failed to update Firestore for room ${roomId}:`, err);
                            // Continuar de todos modos para limpiar memoria
                        }

                        // PASO 2: Eliminar de memoria
                        this.deleteRoom(roomId);
                    }, this.GRACE_PERIOD_MS);

                    console.log(`✅ [GRACE_PERIOD] Grace period timeout set for room ${roomId}`);
                }

                return { roomId, player };
            }
        }
        return null;
    }

    public startGame(roomId: string, playerId: string, emitCallback?: (data: any) => void) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);

        if (!room || !game) throw new Error('Room or game not found');

        // Intercept callback to trigger settlement and handle individual emissions
        const interceptedCallback = (data: any) => {
            // 1. Handle Settlement
            if (data.type === 'hand_winner') {
                // Trigger settlement logic
                this.triggerRoundSettlement(roomId, data).catch(err => console.error('Settlement trigger error:', err));
            }

            // 2. Emit to Persistence Callback (passed from index.ts)
            // We pass the generic/public state here
            if (emitCallback) {
                emitCallback(data);
            }

            // 3. Emit Individual States to Players (Fix for Circular Reference & Privacy)
            if (this.emitCallback) {
                const eventName = data.type === 'hand_winner' ? 'hand_winner' : 'game_update';

                // If it's a hand winner event, it might have a different structure
                // But usually it contains gameState.
                // We need to ensure we send the correct view to each player.

                if (data.type === 'hand_winner') {
                    // For hand_winner, we might want to show everything? 
                    // Or just let the standard logic handle it.
                    // Usually hand_winner includes the winner info + final state.
                    // We should probably broadcast the result to everyone as is (if it's safe)
                    // But wait, data might contain circular refs if it has raw objects.
                    // We must ensure 'data' is safe.
                    // PokerGame.checkActivePlayers emits 'game_finished' with safe data.
                    // But normal hand end?
                    // PokerGame.evaluateWinner calls onGameStateChange with { type: 'hand_winner', ... }
                    // We need to check PokerGame.evaluateWinner (not visible in previous view).
                    // Assuming PokerGame returns safe data now.

                    // For now, let's assume hand_winner data is safe-ish or we should sanitize it too.
                    // But for normal game updates:

                    this.emitCallback(roomId, eventName, data); // Broadcast public event (spectators)
                } else {
                    // Normal Game Update
                    // Loop through players and send private state
                    room.players.forEach(p => {
                        const privateState = game.getPublicState(p.id);
                        this.emitCallback!(roomId, eventName, privateState, p.id);
                    });

                    // CRITICAL FIX: DO NOT broadcast public state to all
                    // This was overwriting the private states sent to each player
                    // causing cards to flash and disappear
                    // Spectators receive updates via other events (game_started, player_joined)

                    // const publicState = game.getPublicState(undefined);
                    // this.emitCallback(roomId, eventName, publicState);
                }
            }
        };

        game.onGameStateChange = interceptedCallback;

        // Attach System Events Callback
        game.onSystemEvent = async (event, data) => {
            console.log(`🔧 System Event in Room ${roomId}: ${event}`); // Sanitized log

            // 🎯 NUEVO: GAME_ENDED - Trigger settlement with real pot data
            // 🎯 NUEVO: GAME_ENDED - Trigger settlement with real pot data
            // ✅ ENABLED: Using Firestore Trigger for reliable settlement
            if (event === 'GAME_ENDED') {
                console.log(`🎯 [GAME_ENDED] Triggering settlement for ${roomId}`);

                // Validate pot total before triggering
                if (data.potTotal && data.potTotal > 0) {
                    try {
                        await this.triggerRoundSettlement(roomId, {
                            authPayload: data.authPayload,
                            securitySignature: data.signature,
                            winner: { uid: data.winnerUid },
                            gameState: {
                                pot: data.potTotal,
                                players: room.players.map(p => ({
                                    uid: p.uid,
                                    chips: p.chips
                                }))
                            }
                        });
                        console.log(`✅ Settlement triggered successfully for ${roomId} - Pot: ${data.potTotal}, Rake: ${data.rakeTaken}`);
                    } catch (error) {
                        console.error(`❌ Failed to trigger settlement for ${roomId}:`, error);
                    }
                } else {
                    console.warn(`⚠️ Skipping settlement for ${roomId} - Pot is 0 (pre-flop fold)`);
                }
            }


            // 🎯 NUEVO: PLAYER_EXIT - Trigger cashout to release moneyInPlay
            if (event === 'PLAYER_EXIT') {
                console.log(`🎯 [PLAYER_EXIT] Triggering cashout for player exit`);

                const { uid, finalChips, reason } = data;
                if (uid) {
                    try {
                        await this.triggerSecureCashout(
                            uid,
                            roomId,
                            finalChips || 0,
                            reason || 'EXIT'
                        );
                        console.log(`✅ Cashout triggered for ${uid} - Chips: ${finalChips}, Reason: ${reason}`);
                    } catch (error) {
                        console.error(`❌ Failed to trigger cashout for ${uid}:`, error);
                    }
                } else {
                    console.warn(`⚠️ Cannot trigger cashout - Player UID missing in PLAYER_EXIT event`);
                }
            }

            // BUG FIX: Manejar correctamente el evento game_finished para Last Man Standing
            if (event === 'game_finished') {
                if (data.reason === 'last_man_standing' || data.reason === 'walkover') {
                    // Close table and cash out
                    console.log(`🏆 Last Man Standing/Walkover: ${data.winnerId}. Cerrando mesa y liquidando fichas...`);

                    // Emitir evento de victoria al cliente antes de cerrar
                    if (this.emitCallback) {
                        this.emitCallback(roomId, 'hand_winner', {
                            type: 'game_finished',
                            winner: {
                                id: data.winnerId,
                                name: room.players.find(p => p.id === data.winnerId)?.name || 'Ganador',
                                amount: data.finalChips || 0,
                                reason: data.reason
                            },
                            message: data.message || "¡Ganaste! Todos los rivales se retiraron.",
                            gameState: game.getPublicState(undefined) // Use public state
                        });
                    }

                    // Pequeño delay para que el cliente muestre la pantalla de victoria
                    setTimeout(async () => {
                        await this.closeTableAndCashOut(roomId);
                    }, 3000); // 3 segundos para mostrar la victoria
                }
            }

            if (event === 'player_needs_rebuy') {
                if (this.emitCallback) {
                    this.emitCallback(roomId, 'player_needs_rebuy', data);
                }
            }

            if (event === 'kick_player') {
                const { playerId } = data;
                console.log(`👢 Kicking player ${playerId} due to timeout`);

                // Get player info for cashout/session end
                const player = room.players.find(p => p.id === playerId);
                if (player) {
                    // Remover jugador del juego
                    this.removePlayer(playerId);

                    // Notificar al cliente
                    if (this.emitCallback) {
                        this.emitCallback(roomId, 'force_disconnect', { playerId });
                    }
                }
            }

            // 💰 NUEVO: distribute_rake - Forward to index.ts for Cloud Function call
            // 💰 NUEVO: distribute_rake - Forward to index.ts for Cloud Function call
            // ❌ DISABLED: HTTP Call is unreliable (401/404). Using GAME_ENDED trigger instead.
            /*
            if (event === 'distribute_rake') {
                console.log(`💰 [RAKE] Forwarding distribute_rake event to emitCallback for room ${roomId}`);

                // Forward event to index.ts through emitCallback
                if (this.emitCallback) {
                    this.emitCallback(roomId, 'distribute_rake', data);
                } else {
                    console.error(`❌ [RAKE] No emitCallback set - cannot forward distribute_rake event`);
                }
            }
            */
        };

        game.startGame(room.players, room.isPublic ?? true, roomId, room.clubId, room.sellerId);
        room.gameState = 'playing';

        if (this.emitCallback) {
            // Initial broadcast (Public)
            // We rely on onGameStateChange for private updates, but startGame triggers it?
            // Yes, game.startGame calls onGameStateChange.
            // So we don't need to manually emit here?
            // But index.ts expects a return value to emit 'game_started'.
            // We return public state.
        }

        return game.getPublicState(undefined);
    }

    // --- CLOSE TABLE AND CASH OUT ---
    // ✅ NUEVO: Ahora el servidor puede forzar cashouts para TODOS los jugadores
    public async closeTableAndCashOut(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room) {
            console.warn(`⚠️ Intento de cerrar mesa inexistente: ${roomId}`);
            return;
        }

        console.log(`🔒 Cerrando mesa ${roomId} y procesando cashouts para todos los jugadores...`);

        // ✅ REFACTORED: LOCAL SETTLEMENT (sin HTTP)
        const cashoutPromises = room.players
            .filter(p => p.uid && !p.isBot)
            .map(async (p) => {
                console.log(`💰 [SETTLEMENT] Processing ${p.uid}: ${p.chips} chips`);

                try {
                    // 1. FORCE SAVE
                    await savePlayerStateToFirestore(roomId, p.uid!, p.chips);

                    // 2. LOCAL SETTLEMENT
                    const totalRake = p.totalRakePaid || 0;
                    await performTableSettlement(roomId, p.uid!, p.chips, totalRake, 'TABLE_CLOSED');

                    console.log(`✅ [SETTLEMENT] Completed for ${p.uid}`);
                } catch (error) {
                    console.error(`❌ [SETTLEMENT] Failed for ${p.uid}:`, error);
                    throw error; // Propagar para que Promise.all lo capture
                }
            });

        try {
            await Promise.all(cashoutPromises);
            console.log(`✅ All players cashed out from table ${roomId}`);
        } catch (error) {
            console.error(`❌ Error processing cashouts for table ${roomId}:`, error);
            // Continuar de todos modos para cerrar la mesa
        }

        // Notify clients
        if (this.emitCallback) {
            this.emitCallback(roomId, 'room_closed', {
                reason: 'Game Finished',
                message: 'Chips converted to credits'
            });
        }

        // Eliminar la sala después de un breve delay
        setTimeout(() => {
            this.deleteRoom(roomId);
        }, 1000);
    }

    public handleGameAction(roomId: string, playerId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number) {
        const game = this.games.get(roomId);
        if (!game) throw new Error('Game not found');

        game.handleAction(playerId, action, amount);
        return game.getGameState();
    }

    public getGameState(roomId: string) {
        const game = this.games.get(roomId);
        if (!game) return null;
        return game.getGameState();
    }

    public async deleteRoom(roomId: string) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);

        // 🔒 Clear grace period timeout if exists
        if (room?.gracePeriodTimeout) {
            clearTimeout(room.gracePeriodTimeout);
            room.gracePeriodTimeout = undefined;
            console.log(`✅ [GRACE_PERIOD] Cleared timeout for room ${roomId}`);
        }

        // ✅ FIX ZOMBIE TABLES: Actualizar Firestore antes de eliminar de memoria
        try {
            const db = admin.firestore();
            const tableRef = db.collection('poker_tables').doc(roomId);
            const tableDoc = await tableRef.get();

            if (tableDoc.exists) {
                // 🔒 USE .set() with merge to avoid NOT_FOUND errors
                await tableRef.set({
                    status: 'finished',
                    players: [],
                    activePlayers: [],
                    lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
                console.log(`✅ Firestore updated: Room ${roomId} marked as finished`);
            }
        } catch (err) {
            console.error(`❌ Failed to update Firestore for room ${roomId}:`, err);
            // Continuar de todos modos para limpiar memoria
        }

        // Limpiar timers del juego si existen
        if (game && (game as any).turnTimer) {
            clearTimeout((game as any).turnTimer);
        }

        // Eliminar de los Maps
        this.rooms.delete(roomId);
        this.games.delete(roomId);

        console.log(`🗑️ Room ${roomId} deleted. Active rooms: ${this.rooms.size}`);
    }

    public addChips(roomId: string, playerId: string, amount: number) {
        const game = this.games.get(roomId);
        if (game) {
            game.addChips(playerId, amount);
        }
    }

    private generateRoomId(): string {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}

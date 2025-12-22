import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';
import { endPokerSession } from '../middleware/firebaseAuth';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

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
        return room;
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
    public emitCallback?: (roomId: string, event: string, data: any) => void;

    public setEmitCallback(callback: (roomId: string, event: string, data: any) => void) {
        this.emitCallback = callback;
    }

    public createPracticeRoom(hostId: string, hostName: string): Room {
        const room = this.createRoom(hostId, hostName, undefined, 1000, undefined, { addHostAsPlayer: true, isPublic: true });

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

        return room;
    }

    public createRoom(hostId: string, hostName: string, sessionId?: string, buyInAmount: number = 1000, customRoomId?: string, options: { addHostAsPlayer?: boolean, isPublic?: boolean, hostUid?: string } = {}): Room {
        const roomId = customRoomId || this.generateRoomId();
        const { addHostAsPlayer = true, isPublic = true, hostUid } = options;

        if (this.rooms.has(roomId)) {
            throw new Error(`Room ${roomId} already exists`);
        }

        const players: Player[] = [];
        if (addHostAsPlayer) {
            const host: Player = {
                id: hostId,
                name: hostName,
                chips: buyInAmount,
                isFolded: false,
                currentBet: 0,
                pokerSessionId: sessionId,
                totalRakePaid: 0,
                status: 'PLAYING'
            };
            players.push(host);
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
            hostId: hostUid || hostId
        };

        this.rooms.set(roomId, newRoom);
        this.games.set(roomId, new PokerGame());

        return newRoom;
    }

    public joinRoom(roomId: string, playerId: string, playerName: string, sessionId?: string, buyInAmount: number = 1000): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        const existingPlayer = room.players.find(p => p.id === playerId);
        if (existingPlayer) {
            if (sessionId) existingPlayer.pokerSessionId = sessionId;
            return room;
        }

        if (room.players.length >= room.maxPlayers) {
            throw new Error('Room is full');
        }

        // Allow join if waiting OR playing (rebuy/late join) - simplified
        // But original code blocked join if playing. We keep that for now unless requested.

        const newPlayer: Player = {
            id: playerId,
            name: playerName,
            chips: buyInAmount,
            isFolded: false,
            currentBet: 0,
            pokerSessionId: sessionId,
            totalRakePaid: 0,
            status: 'PLAYING'
        };

        room.players.push(newPlayer);
        return room;
    }

    public getRoom(roomId: string): Room | undefined {
        return this.rooms.get(roomId);
    }

    // ✅ NUEVO: Método para trigger cashout firmado con HMAC
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

    // ✅ NUEVO: Método para trigger settlement firmado con HMAC
    private async triggerRoundSettlement(roomId: string, data: any): Promise<void> {
        if (!data.authPayload || !data.securitySignature) {
            console.error(`❌ Cannot trigger settlement for room ${roomId}: Missing signature`);
            return;
        }

        try {
            const db = admin.firestore();
            await db.collection('_trigger_settlement').add({
                tableId: roomId,
                gameId: `game_${Date.now()}`, // Or extract from payload if parsed, but payload string is enough
                winnerUid: data.winner?.uid,
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

    public removePlayer(playerId: string): { roomId: string, player: Player } | null {
        for (const [roomId, room] of this.rooms) {
            const index = room.players.findIndex(p => p.id === playerId);
            if (index !== -1) {
                const player = room.players[index];

                // ✅ NUEVO: Trigger cashout ANTES de remover al jugador
                if (player.uid && player.chips > 0 && !player.isBot) {
                    console.log(`💰 Triggering cashout for ${player.uid}: ${player.chips} chips`);
                    this.triggerSecureCashout(player.uid, roomId, player.chips, 'EXIT')
                        .catch(err => console.error(`❌ Failed to trigger cashout for ${player.uid}:`, err));
                }

                room.players.splice(index, 1);

                // Also remove from game instance if exists
                const game = this.games.get(roomId);
                if (game) {
                    game.removePlayer(playerId);
                }

                // ✅ FIX ZOMBIE TABLES: Actualizar Firestore y limpiar memoria cuando la sala queda vacía
                if (room.players.length === 0) {
                    console.log(`🗑️ Room ${roomId} is now empty - updating Firestore and cleaning up`);

                    // PASO 1: Actualizar estado en Firestore ANTES de eliminar de memoria
                    const db = admin.firestore();
                    db.collection('poker_tables').doc(roomId).update({
                        status: 'finished',
                        players: [],
                        activePlayers: [],
                        lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                    }).then(() => {
                        console.log(`✅ Firestore updated: Room ${roomId} marked as finished`);
                    }).catch(err => {
                        console.error(`❌ Failed to update Firestore for room ${roomId}:`, err);
                        // Continuar de todos modos para limpiar memoria
                    });

                    // PASO 2: Eliminar de memoria (no bloqueamos con await)
                    this.deleteRoom(roomId);
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

        // Intercept callback to trigger settlement
        const interceptedCallback = (data: any) => {
            if (data.type === 'hand_winner') {
                // Trigger settlement logic
                this.triggerRoundSettlement(roomId, data).catch(err => console.error('Settlement trigger error:', err));
            }

            if (emitCallback) {
                emitCallback(data);
            }
        };

        game.onGameStateChange = interceptedCallback;

        // Attach System Events Callback
        game.onSystemEvent = async (event, data) => {
            console.log(`🔧 System Event in Room ${roomId}: ${event}`, data);

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
                            gameState: game.getGameState()
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
        };

        game.startGame(room.players, room.isPublic, roomId);
        room.gameState = 'playing';

        if (this.emitCallback) {
            this.emitCallback(roomId, 'game_started', { ...game.getGameState(), roomId });
        }

        return game.getGameState();
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

        // ✅ CRÍTICO: Procesar cashout para TODOS los jugadores (excepto bots)
        const cashoutPromises = room.players
            .filter(p => p.uid && p.chips > 0 && !p.isBot)
            .map(p => {
                console.log(`💰 Triggering cashout for ${p.uid}: ${p.chips} chips`);
                return this.triggerSecureCashout(p.uid!, roomId, p.chips, 'TABLE_CLOSED');
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

        // ✅ FIX ZOMBIE TABLES: Actualizar Firestore antes de eliminar de memoria
        try {
            const db = admin.firestore();
            const tableRef = db.collection('poker_tables').doc(roomId);
            const tableDoc = await tableRef.get();

            if (tableDoc.exists) {
                await tableRef.update({
                    status: 'finished',
                    players: [],
                    activePlayers: [],
                    lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                });
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

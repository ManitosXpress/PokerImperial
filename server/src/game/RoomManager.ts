import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';
import * as admin from 'firebase-admin'; // ACCESO A BD REQUERIDO

export class RoomManager {
    private rooms: Map<string, Room> = new Map();
    private games: Map<string, PokerGame> = new Map();
    private cleanupInterval: NodeJS.Timeout | null = null;
    private readonly CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

    // Callbacks
    public emitCallback?: (roomId: string, event: string, data: any, targetPlayerId?: string) => void;

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

    public createPracticeRoom(hostId: string, hostName: string): Room {
        return this.createRoom(hostId, hostName, undefined, 1000, undefined, { addHostAsPlayer: true, isPublic: true });
    }

    public createRoom(hostId: string, hostName: string, sessionId?: string, buyInAmount: number = 1000, customRoomId?: string, options: { addHostAsPlayer?: boolean, isPublic?: boolean, hostUid?: string, isTournament?: boolean, minBuyIn?: number, maxBuyIn?: number, clubId?: string, sellerId?: string, role?: 'admin' | 'club_owner' | 'seller' | 'player' } = {}): Room {
        const roomId = customRoomId || this.generateRoomId();
        const { addHostAsPlayer = true, isPublic = true, hostUid, isTournament = false, minBuyIn = 1000, maxBuyIn = 10000, clubId, sellerId, role = 'player' } = options;

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
            hostId: hostUid || hostId
        };

        this.rooms.set(roomId, newRoom);
        this.games.set(roomId, new PokerGame());

        return newRoom;
    }

    public joinRoom(roomId: string, playerId: string, playerName: string, sessionId?: string, buyInAmount: number = 1000, uid?: string, metadata?: { role?: 'admin' | 'club_owner' | 'seller' | 'player', clubId?: string, sellerId?: string }): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        const existingPlayer = room.players.find(p => p.id === playerId);
        if (existingPlayer) {
            if (sessionId) existingPlayer.pokerSessionId = sessionId;
            return room;
        }

        if (room.players.length >= room.maxPlayers) throw new Error('Room is full');

        const newPlayer: Player = {
            id: playerId,
            name: playerName,
            chips: buyInAmount,
            isFolded: false,
            currentBet: 0,
            pokerSessionId: sessionId,
            totalRakePaid: 0,
            status: 'PLAYING',
            uid: uid
        };

        room.players.push(newPlayer);

        console.log(`✅ Player ${playerId} (UID: ${uid || 'N/A'}) joined room ${roomId}`);
        return room;
    }

    public removePlayer(playerId: string): { roomId: string, player: Player } | null {
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
            game.onGameStateChange = emitCallback;
        }

        // Configuración de Eventos del Sistema (Victoria por Abandono / Rebuys)
        game.onSystemEvent = async (event, data) => {
            console.log(`🔧 System Event in Room ${roomId}: ${event}`, data);

            if (event === 'game_finished') {
                if (data.reason === 'last_man_standing' || data.reason === 'walkover') {
                    console.log(`🏆 Last Man Standing: ${data.winnerId}. Iniciando liquidación...`);

                    // 1. Notificar al Frontend
                    if (this.emitCallback) {
                        this.emitCallback(roomId, 'hand_winner', {
                            type: 'game_finished',
                            winner: {
                                id: data.winnerId,
                                name: room.players.find(p => p.id === data.winnerId)?.name || 'Ganador',
                                amount: data.finalChips || 0,
                                reason: data.reason
                            },
                            message: "¡Victoria por abandono! Liquidando mesa...",
                            gameState: game.getGameState()
                        });
                    }

                    // 2. Ejecutar Liquidación en BD tras delay
                    setTimeout(async () => {
                        await this.closeTableAndCashOut(roomId);
                    }, 2000);
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

        game.startGame(room.players, room.isPublic);
        room.gameState = 'playing';

        if (this.emitCallback) {
            this.emitCallback(roomId, 'game_started', { ...game.getGameState(), roomId });
        }

        return game.getGameState();
    }

    /**
     * LIQUIDACIÓN REAL SERVIDOR -> FIRESTORE
     * Ejecuta una transacción ACID para asegurar que el dinero pase de la mesa a la billetera.
     */
    public async closeTableAndCashOut(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room) {
            console.warn(`⚠️ Intento de cerrar mesa inexistente: ${roomId}`);
            return;
        }

        console.log(`🔒 EJECUTANDO LIQUIDACIÓN SERVIDOR PARA MESA ${roomId}`);

        try {
            const db = admin.firestore();
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            if (this.emitCallback) {
                this.emitCallback(roomId, 'room_closed', {
                    reason: 'Game Finished',
                    message: 'Partida finalizada. Transfiriendo fondos...'
                });
            }

            // Transacción Atómica
            await db.runTransaction(async (transaction) => {
                const tableRef = db.collection('poker_tables').doc(roomId);
                const tableDoc = await transaction.get(tableRef);

                if (!tableDoc.exists) throw new Error("Table not found in DB");

                // Procesar a TODOS los jugadores en memoria (incluyendo ganador)
                for (const player of room.players) {
                    if (!player.id || player.isBot) continue;

                    const userRef = db.collection('users').doc(player.id);
                    const sessionRef = player.pokerSessionId ? db.collection('poker_sessions').doc(player.pokerSessionId) : null;
                    const finalStack = player.chips;

                    // 1. Devolver dinero y liberar usuario (FIX CRÍTICO)
                    transaction.update(userRef, {
                        moneyInPlay: 0,                // Borra los 200 fantasmas
                        currentTableId: null,          // Libera al usuario de la sala
                        credit: admin.firestore.FieldValue.increment(finalStack), // Paga las ganancias
                        lastUpdated: timestamp
                    });

                    // 2. Cerrar sesión histórica
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: finalStack,
                            endTime: timestamp,
                            closedReason: 'server_force_close'
                        });
                    }
                    console.log(`💰 Procesado ${player.name}: +${finalStack} créditos.`);
                }

                // 3. Cerrar Mesa en DB
                transaction.update(tableRef, {
                    status: 'FINISHED',
                    players: [],
                    lastUpdated: timestamp
                });
            });

            console.log(`✅ Liquidación exitosa. Eliminando sala ${roomId} de memoria.`);
            this.deleteRoom(roomId);

        } catch (error) {
            console.error(`❌ ERROR CRÍTICO liquidando mesa ${roomId}:`, error);
            this.deleteRoom(roomId); // Limpiar memoria de todas formas para evitar zombies
        }
    }

    public handleGameAction(roomId: string, playerId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number) {
        const game = this.games.get(roomId);
        if (!game) throw new Error('Game not found');
        game.handleAction(playerId, action, amount);
        return game.getGameState();
    }

    public getGameState(roomId: string) {
        const game = this.games.get(roomId);
        return game ? game.getGameState() : null;
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

    private generateRoomId(): string {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}

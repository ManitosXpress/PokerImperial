import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { RoomManager } from './game/RoomManager';
import { verifyFirebaseToken, getUserBalance, reservePokerSession, endPokerSession, addChipsToSession } from './middleware/firebaseAuth';
import * as admin from 'firebase-admin';

const app = express();
const httpServer = createServer(app);

// CORS configuration for production and development
const allowedOrigins = [
    'http://localhost:3000',
    'http://localhost:5000',
    'https://poker-fa33a.web.app',
    'https://poker-fa33a.firebaseapp.com'
];

const io = new Server(httpServer, {
    cors: {
        origin: (origin, callback) => {
            if (!origin) return callback(null, true);
            if (allowedOrigins.includes(origin)) {
                callback(null, true);
            } else {
                console.log('Blocked origin:', origin);
                callback(new Error('Not allowed by CORS'));
            }
        },
        methods: ["GET", "POST"],
        credentials: true
    },
    // Optimización: Keep-Alive para detectar desconexiones rápidas
    pingInterval: 25000, // Envía ping cada 25 segundos
    pingTimeout: 10000,  // Espera 10 segundos para respuesta antes de considerar desconectado
    transports: ['websocket', 'polling'] // Soporte para ambos transportes
});

const PORT = process.env.PORT || 3000;
const roomManager = new RoomManager();

/**
 * Helper function para persistir estado del juego en Firestore de forma asíncrona
 * NO bloquea la respuesta al cliente - se ejecuta en background
 */
function persistGameStateAsync(roomId: string, gameState: any) {
    // Ejecutar en background sin await
    setImmediate(async () => {
        try {
            const tableRef = admin.firestore().collection('poker_tables').doc(roomId);
            await tableRef.set({
                pot: gameState.pot,
                communityCards: gameState.communityCards,
                currentTurn: gameState.currentTurn,
                dealerId: gameState.dealerId,
                round: gameState.round,
                currentBet: gameState.currentBet,
                players: gameState.players?.map((p: any) => ({
                    id: p.id,
                    name: p.name,
                    chips: p.chips,
                    currentBet: p.currentBet,
                    isFolded: p.isFolded,
                    isAllIn: p.isAllIn,
                    status: p.status
                })),
                lastActionTime: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            
            console.log(`💾 Game state persisted to Firestore for room ${roomId}`);
        } catch (error) {
            // No lanzar error - solo loguear para no interrumpir el flujo
            console.error(`⚠️ Error persisting game state to Firestore for room ${roomId}:`, error);
        }
    });
}

// Set up RoomManager callback to emit events via IO
roomManager.setEmitCallback((roomId, event, data) => {
    // Handle forced disconnects from RoomManager (Kick)
    if (event === 'force_disconnect') {
        const { playerId } = data;
        const socket = io.sockets.sockets.get(playerId);
        if (socket) {
            socket.emit('error', 'You have been kicked for inactivity.');
            socket.disconnect(true);
        }
        io.to(roomId).emit('player_left', { id: playerId, reason: 'kicked' });
        return;
    }
    
    // OPTIMIZACIÓN: Socket First - Emitir inmediatamente
    io.to(roomId).emit(event, data);

    // OPTIMIZACIÓN: Database Later - Persistir en background sin bloquear
    if (event === 'game_started') {
        setImmediate(async () => {
            try {
                await admin.firestore().collection('poker_tables').doc(roomId).set({
                    status: 'active',
                    lastActionTime: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
                console.log(`💾 Game started persisted to Firestore for room ${roomId}`);
            } catch (e) {
                console.error(`⚠️ Could not sync game_started to Firestore for room ${roomId}:`, e);
            }
        });
    } else if (event === 'game_update' || event === 'hand_winner') {
        // Persistir actualizaciones del juego de forma asíncrona
        persistGameStateAsync(roomId, data);
    }
});

io.on('connection', (socket) => {
    console.log('User connected:', socket.id);

    socket.on('authenticate', async (data: { token: string }) => {
        const uid = await verifyFirebaseToken(data.token);
        if (!uid) {
            socket.emit('auth_error', { message: 'Invalid token' });
            return;
        }
        (socket as any).userId = uid;
        socket.emit('authenticated', { uid });
        console.log(`User authenticated: ${uid}`);
    });

    socket.on('create_room', async (data: any) => {
        const playerName = typeof data === 'string' ? data : data.playerName;
        const token = typeof data === 'object' ? data.token : null;
        const customRoomId = typeof data === 'object' ? data.roomId : null;

        try {
            let sessionId: string | undefined;
            let entryFee = 1000;
            let isPublic = false;
            let uid: string | undefined;

            if (customRoomId) {
                try {
                    const roomDoc = await admin.firestore().collection('poker_tables').doc(customRoomId).get();
                    if (roomDoc.exists) {
                        const roomData = roomDoc.data();
                        if (roomData) {
                            isPublic = roomData.isPublic ?? false;
                            if (roomData.minBuyIn) {
                                entryFee = roomData.minBuyIn;
                            }
                        }
                    }
                } catch (err) {
                    console.log(`Could not fetch room data from Firestore for ${customRoomId}, using defaults`);
                }
            }

            if (token) {
                const verifiedUid = await verifyFirebaseToken(token);
                if (verifiedUid) {
                    uid = verifiedUid;
                    const balance = await getUserBalance(uid);
                    if (balance < entryFee) {
                        socket.emit('insufficient_balance', { required: entryFee, current: balance });
                        return;
                    }
                    sessionId = await reservePokerSession(uid, entryFee, customRoomId || 'new_room') || undefined;
                    if (!sessionId) {
                        socket.emit('error', 'Failed to reserve credits');
                        return;
                    }
                    (socket as any).userId = uid;
                }
            } else {
                socket.emit('error', 'Authentication required to create room');
                return;
            }
            
            const room = roomManager.createRoom(socket.id, playerName, sessionId, entryFee, customRoomId || undefined, { addHostAsPlayer: true, isPublic, hostUid: uid });
            
            // Inject UID into player object for the host
            if (uid && room.players.length > 0) {
                room.players[0].uid = uid;
            }

            room.hostId = uid;
            socket.join(room.id);
            
            const roomResponse = { ...room, isPublic, hostId: uid };
            socket.emit('room_created', roomResponse);
            console.log(`Room created: ${room.id} by ${playerName} (UID: ${uid})`);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('create_practice_room', (playerName: string) => {
        try {
            const room = roomManager.createPracticeRoom(socket.id, playerName);
            socket.join(room.id);
            socket.emit('room_created', room);

            console.log(`Practice Room created: ${room.id} by ${playerName}`);

            setTimeout(() => {
                try {
                    const gameState = roomManager.startGame(room.id, socket.id, (data) => {
                        if (data.type === 'hand_winner') {
                            io.to(room.id).emit('hand_winner', data);
                        } else {
                            io.to(room.id).emit('game_update', data);
                        }
                    });
                    io.to(room.id).emit('game_started', { ...gameState, roomId: room.id });
                } catch (e: any) {
                    console.error('Error starting practice game:', e);
                    socket.emit('error', 'Failed to start practice game: ' + e.message);
                }
            }, 500);

        } catch (e: any) {
            console.error(e);
            socket.emit('error', e.message);
        }
    });

    socket.on('join_room', async ({ roomId, playerName, token }: { roomId: string, playerName: string, token?: string }) => {
        try {
            let sessionId: string | undefined;
            let entryFee = 1000;
            let uid: string | undefined;

            try {
                const roomDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                if (roomDoc.exists) {
                    const roomData = roomDoc.data();
                    if (roomData && roomData.minBuyIn) {
                        entryFee = roomData.minBuyIn;
                    }
                }
            } catch (err) {
                console.error(`Error getting minBuyIn for room ${roomId}:`, err);
            }

            if (token) {
                const verifiedUid = await verifyFirebaseToken(token);
                if (verifiedUid) {
                    uid = verifiedUid;
                    const balance = await getUserBalance(uid);
                    if (balance < entryFee) {
                        socket.emit('insufficient_balance', { required: entryFee, current: balance });
                        return;
                    }
                    sessionId = await reservePokerSession(uid, entryFee, roomId) || undefined;
                    if (!sessionId) {
                        socket.emit('error', 'Failed to reserve credits');
                        return;
                    }
                    (socket as any).userId = uid;
                }
            } else {
                socket.emit('error', 'Authentication required to join room');
                return;
            }

            let room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);

            if (!room) {
                try {
                    const roomDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                    if (roomDoc.exists) {
                        const roomData = roomDoc.data();
                        if (roomData && roomData.status !== 'finished') {
                            console.log(`Hydrating room ${roomId} from Firestore...`);
                            const firestoreHostId = roomData.hostId || 'unknown';
                            const hostName = roomData.hostName || 'Host';
                            const isPublic = roomData.isPublic !== undefined ? roomData.isPublic : true;

                            if (!roomManager.getRoom(roomId)) {
                                try {
                                    const tempRoom = roomManager.createRoom('temp-host', hostName, undefined, entryFee, roomId, { addHostAsPlayer: false, isPublic });
                                    tempRoom.hostId = firestoreHostId;
                                } catch (err: any) {
                                    console.log(`Room ${roomId} created concurrently during hydration.`);
                                }
                            }

                            room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);
                        }
                    }
                } catch (err) {
                    console.error(`Error hydrating room ${roomId}:`, err);
                }
            }

            if (room) {
                const player = room.players.find(p => p.id === socket.id);
                if (player && uid) {
                    player.uid = uid;
                }

                socket.join(roomId);
                const roomWithFlags = { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId };
                io.to(roomId).emit('player_joined', roomWithFlags);
                socket.emit('room_joined', roomWithFlags);
                console.log(`${playerName} joined room ${roomId}`);
            } else {
                socket.emit('error', 'Room not found');
            }
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('start_game', ({ roomId }: { roomId: string }) => {
        try {
            console.log(`🎮 Starting game for room ${roomId}...`);
            
            // OPTIMIZACIÓN: Socket First, Database Later
            // 1. Actualizar estado en memoria
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                // 2. Emitir eventos Socket inmediatamente
                if (data.type === 'hand_winner') {
                    console.log(`🏆 Emitting hand_winner for room ${roomId} (Socket First)`);
                    io.to(roomId).emit('hand_winner', data);
                } else {
                    console.log(`📡 Emitting game_update for room ${roomId} (Socket First)`);
                    io.to(roomId).emit('game_update', data);
                }
                
                // 3. Persistir en Firestore después (async, no bloquea)
                if (data.type === 'hand_winner' || data.gameState) {
                    persistGameStateAsync(roomId, data.gameState || data);
                }
            });
            
            console.log(`🃏 Game started! Players: ${gameState.players?.length}`);
            
            // 2. Emitir evento de inicio inmediatamente
            io.to(roomId).emit('game_started', gameState);
            
            // 3. Persistir en Firestore después (async, no bloquea)
            persistGameStateAsync(roomId, gameState);
            
        } catch (e: any) {
            console.error(`❌ Error starting game: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('game_action', ({ roomId, action, amount }: { roomId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number }) => {
        try {
            console.log(`🎲 game_action received: roomId=${roomId}, playerId=${socket.id}, action=${action}, amount=${amount}`);
            
            // OPTIMIZACIÓN: Socket First, Database Later
            // 1. Actualizar estado en memoria (RAM) inmediatamente
            const gameState = roomManager.handleGameAction(roomId, socket.id, action, amount);
            console.log(`✅ Action processed successfully. Current turn: ${gameState.currentTurn}`);
            
            // 2. EMITIR evento Socket INMEDIATAMENTE (sin esperar Firestore)
            io.to(roomId).emit('game_update', gameState);
            console.log(`📡 game_update emitted to room ${roomId} (Socket First)`);
            
            // 3. Persistir en Firestore DESPUÉS (sin await - no bloquea)
            persistGameStateAsync(roomId, gameState);
            
        } catch (e: any) {
            console.error(`❌ Error processing game_action: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('player_ready', ({ roomId, isReady }: { roomId: string, isReady: boolean }) => {
        try {
            const room = roomManager.toggleReady(roomId, socket.id, isReady);
            if (room) {
                const roomWithFlags = { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId };
                io.to(roomId).emit('room_update', roomWithFlags);
            }
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('close_room', async ({ roomId }: { roomId: string }) => {
        try {
            const room = roomManager.getRoom(roomId);
            if (!room) {
                socket.emit('error', 'Room not found');
                return;
            }
            
            const uid = (socket as any).userId;
            if (!uid || room.hostId !== uid) {
                socket.emit('error', 'Only host can close the room');
                return;
            }

            console.log(`🛑 Host ${uid} closing room ${roomId}`);
            await roomManager.closeTableAndCashOut(roomId);
            
        } catch (e: any) {
            console.error(`Error closing room: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('disconnect', async () => {
        console.log('User disconnected:', socket.id);
        const result = roomManager.removePlayer(socket.id);
        if (result) {
            const { roomId, player } = result;
            const uid = (socket as any).userId;

            let minBuyIn = 1000;
            try {
                const tableDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                if (tableDoc.exists) {
                    const tableData = tableDoc.data();
                    if (tableData && tableData.minBuyIn) {
                        minBuyIn = tableData.minBuyIn;
                    }
                }
            } catch (err) {
                console.error(`Error getting minBuyIn for room ${roomId}:`, err);
            }

            if (player.pokerSessionId && uid) {
                // CRÍTICO: Determinar exit fee basado en el estado de la mesa
                // - Si la mesa está 'finished' o 'inactive': No hay exit fee (juego terminó)
                // - Si la mesa está 'active' y jugador tiene 0 chips: No hay exit fee (ya perdió)
                // - Si la mesa está 'active' y jugador tiene fichas: Exit fee aplica (salida temprana)
                
                let exitFee = 0;
                let tableStatus = 'unknown';
                
                try {
                    const tableDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                    if (tableDoc.exists) {
                        tableStatus = tableDoc.data()?.status || 'unknown';
                    }
                } catch (err) {
                    console.error(`[DISCONNECT] Error obteniendo estado de mesa ${roomId}:`, err);
                }
                
                // Si la mesa ya terminó (finished/inactive), no hay exit fee
                if (tableStatus === 'finished' || tableStatus === 'inactive') {
                    exitFee = 0;
                    console.log(`[DISCONNECT] Jugador ${uid} se desconectó - Mesa ${tableStatus}, sin exit fee`);
                } else if (player.chips === 0) {
                    // Ya perdió todo, no hay exit fee
                    exitFee = 0;
                    console.log(`[DISCONNECT] Jugador ${uid} se desconectó con 0 chips - Sin exit fee (ya perdió)`);
                } else {
                    // Mesa activa y jugador tiene fichas - Salida temprana, exit fee aplica
                    exitFee = minBuyIn;
                    console.log(`[DISCONNECT] Jugador ${uid} se desconectó con ${player.chips} chips - Exit fee: ${exitFee} (salida temprana de mesa activa)`);
                }
                
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0, exitFee);
            }

            if (uid) {
                try {
                    const tableRef = admin.firestore().collection('poker_tables').doc(roomId);
                    const tableDoc = await tableRef.get();
                    
                    if (tableDoc.exists) {
                        const tableData = tableDoc.data();
                        if (tableData) {
                            const players = Array.isArray(tableData.players) ? [...tableData.players] : [];
                            const updatedPlayers = players.filter((p: any) => {
                                const playerId = typeof p === 'object' ? p.id : p;
                                return playerId !== uid;
                            });

                            const readyPlayers = Array.isArray(tableData.readyPlayers) ? [...tableData.readyPlayers] : [];
                            const updatedReadyPlayers = readyPlayers.filter((id: string) => id !== uid);

                            await tableRef.update({
                                players: updatedPlayers,
                                readyPlayers: updatedReadyPlayers
                            });

                            console.log(`Removed player ${uid} from Firestore table ${roomId}`);
                        }
                    }
                } catch (error) {
                    console.error(`Error updating Firestore when player left: ${error}`);
                }
            }

            const room = roomManager.getRoom(roomId);
            if (room) {
                const roomWithFlags = { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId };
                io.to(roomId).emit('player_left', roomWithFlags);
            }
        }
    });

    socket.on('request_top_up', async ({ roomId, amount, token }: { roomId: string, amount: number, token?: string }) => {
        try {
            if (!token) throw new Error('Authentication required');
            const uid = await verifyFirebaseToken(token);
            if (!uid) throw new Error('Invalid token');

            const room = roomManager.getRoom(roomId);
            if (!room) throw new Error('Room not found');

            const player = room.players.find(p => p.id === socket.id);
            if (!player || !player.pokerSessionId) throw new Error('Player not found or no active session');

            const success = await addChipsToSession(uid, player.pokerSessionId, amount);
            if (success) {
                roomManager.addChips(roomId, socket.id, amount);
                socket.emit('top_up_success', { amount });
            } else {
                socket.emit('error', { message: 'Failed to add chips. Insufficient balance.' });
            }
        } catch (error) {
            console.error('Top-up error:', error);
            socket.emit('error', { message: error instanceof Error ? error.message : 'Top-up failed' });
        }
    });
});

app.get('/', (req, res) => {
    res.send('Poker Server is running');
});

app.get('/debug/rooms', (req, res) => {
    const rooms = Array.from((roomManager as any).rooms.entries());
    console.log('Debug endpoint called. Current rooms:', rooms.length);
    res.json({
        count: rooms.length,
        rooms: rooms.map((entry: any) => {
            const [id, room] = entry;
            return {
                id,
                players: room.players.map((p: any) => ({
                    id: p.id,
                    name: p.name,
                    isReady: p.isReady,
                    isBot: p.isBot
                })),
                readyCount: room.players.filter((p: any) => p.isReady).length,
                gameState: room.gameState
            };
        })
    });
});

httpServer.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
});

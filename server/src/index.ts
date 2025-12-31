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

            // Crear objeto con valores seguros (nunca undefined)
            const safeGameState: any = {
                pot: gameState.pot ?? 0,
                communityCards: gameState.communityCards ?? [],
                currentTurn: gameState.currentTurn ?? null,
                dealerId: gameState.dealerId ?? null,
                round: gameState.round || gameState.stage || 'waiting',
                currentBet: gameState.currentBet ?? 0,
                lastActionTime: admin.firestore.FieldValue.serverTimestamp()
            };

            // Solo incluir players si existe y tiene contenido
            if (gameState.players && Array.isArray(gameState.players)) {
                safeGameState.players = gameState.players.map((p: any) => ({
                    id: p.id ?? '',
                    name: p.name ?? 'Unknown',
                    chips: p.chips ?? 0,
                    currentBet: p.currentBet ?? p.bet ?? 0,
                    isFolded: p.isFolded ?? false,
                    isAllIn: p.isAllIn ?? false,
                    status: p.status ?? 'waiting'
                }));
            }

            await tableRef.set(safeGameState, { merge: true });

            console.log(`💾 Game state persisted to Firestore for room ${roomId}`);
        } catch (error) {
            // No lanzar error - solo loguear para no interrumpir el flujo
            console.error(`⚠️ Error persisting game state to Firestore for room ${roomId}:`, error);
        }
    });
}

// Set up RoomManager callback to emit events via IO
roomManager.setEmitCallback((roomId, event, data, targetPlayerId) => {
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
    if (targetPlayerId) {
        // Emitir solo al jugador específico (para cartas privadas)
        io.to(targetPlayerId).emit(event, data);
    } else {
        // Emitir a toda la sala (para espectadores o eventos públicos)
        io.to(roomId).emit(event, data);
    }

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
    } else if (event === 'hand_winner') {
        // Persistir actualizaciones del juego de forma asíncrona
        persistGameStateAsync(roomId, data);

        // CRÍTICO: Incrementar contador de manos jugadas (Turnover) para estadísticas diarias
        setImmediate(async () => {
            try {
                const now = new Date();
                const year = now.getFullYear();
                const month = String(now.getMonth() + 1).padStart(2, '0');
                const day = String(now.getDate()).padStart(2, '0');
                const dateId = `${year}-${month}-${day}`;

                await admin.firestore().collection('stats_daily').doc(dateId).set({
                    handsPlayed: admin.firestore.FieldValue.increment(1),
                    date: dateId,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });

                console.log(`📈 Hand count incremented for ${dateId}`);
            } catch (e) {
                console.error(`⚠️ Failed to increment handsPlayed:`, e);
            }
        });
    } else if (event === 'game_update') {
        // Persistir actualizaciones del juego de forma asíncrona
        persistGameStateAsync(roomId, data);
    } else if (event === 'distribute_rake') {
        // 💰 SOCKET FIRST, LEDGER LATER: Distribuir rake a Platform, Club y Seller
        // El servidor de juego calculó los ganadores y emitió este evento
        // Ahora llamamos a la Cloud Function para manejar la contabilidad financiera
        console.log(`💰 [RAKE] distribute_rake event received for room ${roomId}`);
        console.log(`💰 [RAKE] Data:`, data);

        setImmediate(async () => {
            try {
                // Obtener metadata de la mesa (clubId, sellerId)
                const tableRef = admin.firestore().collection('poker_tables').doc(roomId);
                const tableDoc = await tableRef.get();

                let clubId: string | undefined;
                let sellerId: string | undefined;

                if (tableDoc.exists) {
                    const tableData = tableDoc.data();
                    clubId = tableData?.clubId;
                    sellerId = tableData?.sellerId;

                    console.log(`💰 [RAKE] Table metadata: clubId=${clubId}, sellerId=${sellerId}`);
                }

                // Importar helper y llamar a Cloud Function
                const { callDistributeRakeFunction } = await import('./middleware/firebaseAuth');

                const success = await callDistributeRakeFunction({
                    tableId: roomId,
                    gameId: `hand_${Date.now()}`,
                    potTotal: data.potTotal,
                    rakeTotal: data.rakeTotal,
                    rakeDistribution: data.rakeDistribution,
                    winnerIds: data.winnerIds,
                    clubId,
                    sellerId
                });

                if (success) {
                    console.log(`✅ [RAKE] Rake distributed successfully for ${roomId}`);
                } else {
                    console.error(`❌ [RAKE] Failed to distribute rake for ${roomId}`);
                }
            } catch (error) {
                console.error(`❌ [RAKE] Error processing distribute_rake event:`, error);
            }
        });
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

            if (typeof data === 'object') {
                if (data.minBuyIn && typeof data.minBuyIn === 'number') {
                    entryFee = data.minBuyIn;
                } else if (data.buyIn && typeof data.buyIn === 'number') {
                    entryFee = data.buyIn;
                }
            }

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
                    (socket as any).userId = uid;
                } else {
                    socket.emit('error', 'Invalid token');
                    return;
                }
            } else {
                socket.emit('error', 'Authentication required to create room');
                return;
            }

            let minBuyIn: number | undefined;
            let maxBuyIn: number | undefined;

            if (typeof data === 'object') {
                if (data.minBuyIn) minBuyIn = Number(data.minBuyIn);
                if (data.maxBuyIn) maxBuyIn = Number(data.maxBuyIn);
            }

            // PASO 1: Crear el room PRIMERO para obtener el ID real
            const room = roomManager.createRoom(socket.id, playerName, undefined, entryFee, customRoomId || undefined, {
                addHostAsPlayer: true,
                isPublic,
                hostUid: uid,
                minBuyIn,
                maxBuyIn
            });
            const actualRoomId = room.id; // Este es el ID real del room

            // PASO 2: Reservar sesión con el ID REAL del room
            // ✅ CORREGIDO: Llamar a Cloud Function en lugar de crear sesión directamente
            if (uid) {
                // Importar función helper
                const { callJoinTableFunction } = await import('./middleware/firebaseAuth');
                sessionId = await callJoinTableFunction(uid, actualRoomId, entryFee) || undefined;
                if (!sessionId) {
                    // Rollback: eliminar el room creado
                    roomManager.deleteRoom(actualRoomId);
                    socket.emit('error', 'Failed to reserve credits');
                    return;
                }
                // Actualizar el pokerSessionId del jugador en el room
                if (room.players.length > 0) {
                    room.players[0].pokerSessionId = sessionId;
                }
            }

            // Inject UID into player object for the host
            if (uid && room.players.length > 0) {
                room.players[0].uid = uid;
            }

            room.hostId = uid;
            socket.join(room.id);

            // room is already sanitized from roomManager.createRoom
            socket.emit('room_created', room);
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

    socket.on('join_spectator', ({ roomId }: { roomId: string }) => {
        try {
            console.log(`👀 Spectator ${socket.id} joining room ${roomId}`);
            socket.join(roomId);

            const room = roomManager.getRoom(roomId);
            if (room) {
                const roomWithFlags = { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId };
                // Send room info so the client knows it connected
                socket.emit('room_joined', roomWithFlags);

                // Send current game state if game is running
                if (room.gameState) {
                    socket.emit('game_started', room.gameState);
                }
            } else {
                socket.emit('error', 'Room not found');
            }
        } catch (e: any) {
            console.error(`Error joining spectator: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('join_room', async ({ roomId, playerName, token, isSpectator }: { roomId: string, playerName: string, token?: string, isSpectator?: boolean }) => {
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
                console.log(`[JOIN_ROOM] 🔐 Verificando token para usuario...`);
                const verifiedUid = await verifyFirebaseToken(token);
                if (verifiedUid) {
                    uid = verifiedUid;
                    console.log(`[JOIN_ROOM] ✅ Usuario autenticado: ${uid}`);

                    // Si es espectador, no necesitamos verificar balance ni crear sesión de juego
                    if (!isSpectator) {
                        const balance = await getUserBalance(uid);
                        console.log(`[JOIN_ROOM] 💰 Balance del usuario: ${balance}, EntryFee requerido: ${entryFee}`);
                        if (balance < entryFee) {
                            console.log(`[JOIN_ROOM] ❌ Balance insuficiente: ${balance} < ${entryFee}`);
                            socket.emit('insufficient_balance', { required: entryFee, current: balance });
                            return;
                        }
                        // ✅ CORREGIDO: Llamar a Cloud Function en lugar de crear sesión directamente
                        console.log(`[JOIN_ROOM] 📞 Llamando a callJoinTableFunction para usuario ${uid}, mesa ${roomId}, buyIn ${entryFee}`);
                        const { callJoinTableFunction } = await import('./middleware/firebaseAuth');
                        sessionId = await callJoinTableFunction(uid, roomId, entryFee) || undefined;
                        if (!sessionId) {
                            console.error(`[JOIN_ROOM] ❌ callJoinTableFunction retornó null para usuario ${uid}`);
                            socket.emit('error', 'Failed to reserve credits');
                            return;
                        }
                        console.log(`[JOIN_ROOM] ✅ Sesión creada: ${sessionId}`);
                    }
                    (socket as any).userId = uid;
                } else {
                    console.error(`[JOIN_ROOM] ❌ Token inválido o verificación falló`);
                    socket.emit('error', 'Invalid token');
                    return;
                }
            } else {
                console.error(`[JOIN_ROOM] ❌ No se proporcionó token`);
                socket.emit('error', 'Authentication required to join room');
                return;
            }

            // === LÓGICA DE ESPECTADOR (NUEVA) ===
            if (isSpectator === true) {
                console.log(`👀 [JOIN_ROOM] Usuario ${playerName} (${uid}) uniéndose como ESPECTADOR a sala ${roomId}`);
                const room = roomManager.getRoom(roomId);

                if (room) {
                    socket.join(roomId);

                    // Obtener estado actual del juego desde RoomManager
                    const currentGameState = roomManager.getGameState(roomId);

                    // 2. FORZAR LA OBTENCIÓN DE JUGADORES (Fix Crítico)
                    // Asegúrate de usar el método que devuelve TODOS los jugadores sentados
                    const actualPlayers = room.players.map(p => {
                        // Asegúrate de devolver un objeto serializable (PublicProfile)
                        return {
                            id: p.id,
                            name: p.name,
                            chips: p.chips,
                            seatIndex: (p as any).seatIndex ?? room.players.indexOf(p), // Fallback to index if seatIndex missing
                            avatar: (p as any).avatar, // o photoUrl
                            isFolded: p.isFolded,
                            status: p.status // 'PLAYING', 'SIT_OUT', etc
                        };
                    });

                    console.log(`📦 [DEBUG] Enviando ${actualPlayers.length} jugadores al espectador admin.`);

                    // EMITIR EL EVENTO QUE DESBLOQUEA LA APP
                    socket.emit('spectator_joined', {
                        roomId: roomId,
                        gameState: {
                            ...(currentGameState || { roomId, status: room.gameState }),
                            activePlayers: actualPlayers, // <--- AQUÍ ESTÁ LA CLAVE
                            players: actualPlayers        // Enviar en ambos campos por compatibilidad
                        },
                        isSpectator: true
                    });

                    console.log(`✅ [JOIN_ROOM] Espectador unido - Evento spectator_joined emitido con estado: ${room.gameState}`);

                    // Si el juego ya está corriendo, enviar el estado completo
                    if (room.gameState === 'playing' && currentGameState) {
                        socket.emit('game_started', {
                            ...currentGameState,
                            activePlayers: actualPlayers,
                            players: actualPlayers
                        });
                        console.log(`🎮 [JOIN_ROOM] Juego activo - Enviando game_started a espectador`);
                    }
                } else {
                    // Intentar hidratar desde Firestore si no está en memoria
                    console.log(`[JOIN_ROOM] ⚠️ Mesa ${roomId} no encontrada en memoria, intentando hidratar desde Firestore...`);
                    try {
                        const roomDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                        if (roomDoc.exists) {
                            const roomData = roomDoc.data();
                            console.log(`[JOIN_ROOM] Mesa encontrada en Firestore con status: ${roomData?.status}`);

                            // Unir al socket de todas formas para que reciba actualizaciones
                            socket.join(roomId);

                            // Emitir spectator_joined con datos de Firestore
                            socket.emit('spectator_joined', {
                                roomId: roomId,
                                gameState: roomData,
                                isSpectator: true,
                                fromFirestore: true
                            });

                            console.log(`✅ [JOIN_ROOM] Espectador unido a mesa hidratada desde Firestore`);
                        } else {
                            console.error(`[JOIN_ROOM] ❌ Mesa ${roomId} no existe en Firestore`);
                            socket.emit('error', 'Room not found');
                        }
                    } catch (e) {
                        console.error(`[JOIN_ROOM] ❌ Error al hidratar mesa desde Firestore:`, e);
                        socket.emit('error', 'Room not found');
                    }
                }
                return; // IMPORTANTE: No seguir a addPlayer
            }

            // --- LÓGICA DE JUGADOR NORMAL ---
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
                            const isTournament = roomData.isTournament === true;

                            if (!roomManager.getRoom(roomId)) {
                                try {
                                    const tempRoom = roomManager.createRoom('temp-host', hostName, undefined, entryFee, roomId, { addHostAsPlayer: false, isPublic, isTournament });
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
                // room is already sanitized from roomManager.joinRoom
                io.to(roomId).emit('player_joined', room);
                socket.emit('room_joined', room);
                console.log(`${playerName} joined room ${roomId}`);
            } else {
                console.error(`[JOIN_ROOM] ❌ Room no encontrada: ${roomId}`);
                socket.emit('error', 'Room not found');
            }
        } catch (e: any) {
            console.error(`[JOIN_ROOM] ❌ Excepción en join_room:`, e);
            console.error(`[JOIN_ROOM] ❌ Mensaje: ${e.message}`);
            console.error(`[JOIN_ROOM] ❌ Stack: ${e.stack}`);
            socket.emit('error', e.message || 'Error joining room');
        }
    });

    socket.on('start_game', ({ roomId }: { roomId: string }) => {
        try {
            console.log(`🎮 Starting game for room ${roomId}...`);

            // OPTIMIZACIÓN: Socket First, Database Later
            // 1. Actualizar estado en memoria
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                // 2. Persistir en Firestore después (async, no bloquea)
                // NOTA: La emisión por socket ahora la maneja RoomManager para enviar estados individuales
                if (data.type === 'hand_winner' || data.gameState) {
                    persistGameStateAsync(roomId, data.gameState || data);
                }
            });

            console.log(`🃏 Game started! Players: ${gameState.players?.length}`);

            // 3. Persistir en Firestore después (async, no bloquea)
            persistGameStateAsync(roomId, gameState);

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

            // 2. La emisión por socket ahora la maneja RoomManager (handleGameAction -> nextTurn -> onGameStateChange)
            // No emitimos aquí para evitar duplicados y permitir estados privados

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
                // room is already sanitized from roomManager.toggleReady
                io.to(roomId).emit('room_update', room);
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
                // Create sanitized room data
                const roomSafe = {
                    id: room.id,
                    players: room.players.map(p => ({
                        id: p.id,
                        name: p.name,
                        chips: p.chips,
                        isFolded: p.isFolded,
                        currentBet: p.currentBet,
                        status: p.status
                    })),
                    gameState: room.gameState,
                    isPublic: room.isPublic ?? false,
                    hostId: room.hostId
                };
                io.to(roomId).emit('player_left', roomSafe);
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

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
                minBuyIn: gameState.minBuyIn ?? null,
                maxBuyIn: gameState.maxBuyIn ?? null,
                smallBlind: gameState.smallBlind ?? null,
                bigBlind: gameState.bigBlind ?? null,
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
        // 🧠 SMART EMISSION: Handle personalized states for game updates
        if (event === 'game_update' || event === 'game_started') {
            const room = roomManager.getRoom(roomId);
            if (room) {
                const playerSocketIds = room.players.map(p => p.id);

                // 1. Send personalized state to each active player
                room.players.forEach(player => {
                    // CRÍTICO: Usar UID si está disponible, fallback a socket ID
                    // PokerGame usa UID para validar "shouldShowCards"
                    const identity = player.uid || player.id;
                    const personalizedState = roomManager.getPlayerState(roomId, identity);

                    if (personalizedState) {
                        io.to(player.id).emit(event, personalizedState);
                    }
                });

                // 2. Send sanitized (spectator) state to everyone else (Except players)
                if (playerSocketIds.length > 0) {
                    io.to(roomId).except(playerSocketIds).emit(event, data);
                } else {
                    io.to(roomId).emit(event, data);
                }
            } else {
                // Should not happen, but fallback
                io.to(roomId).emit(event, data);
            }
        } else {
            // Standard broadcast for other events (hand_winner, player_joined, etc.)
            io.to(roomId).emit(event, data);
        }
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
                    isPrivate: data.isPrivate ?? false, // 🔒 Use from payload
                    clubId: data.clubId || clubId,      // Prefer payload, fallback to Firestore
                    sellerId: data.sellerId || sellerId // Prefer payload, fallback to Firestore
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

    // 🔌 Handle Delayed Disconnect (Timeout) -> Process Exit Fee
    if (event === 'player_timeout_leave') {
        const { playerId, player, roomId } = data;
        const uid = player.uid; // Prioritize UID from player object

        console.log(`🔌 [TIMEOUT] Processing Exit Fee for ${player.name} (${uid || playerId}) in room ${roomId}`);

        setImmediate(async () => {
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
                    console.log(`[DISCONNECT] Jugador ${uid} eliminado por timeout - Mesa ${tableStatus}, sin exit fee`);
                } else if (player.chips === 0) {
                    // Ya perdió todo, no hay exit fee
                    exitFee = 0;
                    console.log(`[DISCONNECT] Jugador ${uid} eliminado por timeout con 0 chips - Sin exit fee (ya perdió)`);
                } else {
                    // Mesa activa y jugador tiene fichas - Salida temprana, exit fee aplica
                    exitFee = minBuyIn; // Cobrar minBuyIn (ej 1000) como penalidad
                    console.log(`[DISCONNECT] Jugador ${uid} eliminado por timeout con ${player.chips} chips - Exit fee: ${exitFee} (salida temprana)`);
                }

                // Importar helper para finalizar sesión
                const { endPokerSession } = await import('./middleware/firebaseAuth');
                // Llamar a endPokerSession con el exitFee calculado
                // Nota: endPokerSession debe manejar la deducción del exit fee del crédito devuelto
                // Actualmente endPokerSession devuelve los chips restantes.
                // Si queremos cobrar exit fee, debemos deducirlo de los chips O pasarlo como parametro.
                // Asumiremos que endPokerSession maneja credit updates.

                // Si la implementación de endPokerSession no soporta exitFee, debemos manejarlo manualmente aquí o actualizar endPokerSession logic.
                // Por ahora usamos la lógica estándar pero pasando el exitFee como metadata si es posible, o asumiendo que el sistema lo maneja.

                // FIX: El sistema actual parece devolver `player.chips` al usuario.
                // Si hay exitFee, deberíamos restar.
                // const finalCredit = Math.max(0, player.chips - exitFee);

                // Llamar a endPokerSession
                // Signature: (uid, sessionId, currentChips, rakePaid, exitFee)
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0, exitFee);
                console.log(`✅ Session ${player.pokerSessionId} ended. Chips: ${player.chips}, Fee: ${exitFee}`);
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

            console.log('DEBUG: create_room data received:', JSON.stringify(data, null, 2));

            // 🔒 READ isPublic from frontend data (default: false for private, true if specified)
            if (typeof data === 'object' && data.isPublic !== undefined) {
                isPublic = Boolean(data.isPublic);
                console.log(`DEBUG: isPublic from frontend: ${isPublic}`);
            }

            if (typeof data === 'object') {
                if (data.minBuyIn) {
                    const parsedMin = Number(data.minBuyIn);
                    if (!isNaN(parsedMin)) {
                        entryFee = parsedMin;
                        console.log('DEBUG: Set entryFee from minBuyIn:', entryFee);
                    }
                } else if (data.buyIn) {
                    const parsedBuyIn = Number(data.buyIn);
                    if (!isNaN(parsedBuyIn)) {
                        entryFee = parsedBuyIn;
                        console.log('DEBUG: Set entryFee from buyIn:', entryFee);
                    }
                }
            }

            if (customRoomId) {
                try {
                    const roomDoc = await admin.firestore().collection('poker_tables').doc(customRoomId).get();
                    if (roomDoc.exists) {
                        const roomData = roomDoc.data();
                        if (roomData) {
                            isPublic = roomData.isPublic ?? isPublic;  // Keep frontend value if Firestore doesn't have it
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

            let smallBlind: number | undefined;
            let bigBlind: number | undefined;

            if (typeof data === 'object') {
                if (data.smallBlind) smallBlind = Number(data.smallBlind);
                if (data.bigBlind) bigBlind = Number(data.bigBlind);
            }

            // 🔒 ROLE-BASED HOST DETECTION: Admin/Club Owner/Seller should NOT be added as player
            let addHostAsPlayer = true;
            if (uid) {
                try {
                    const userDoc = await admin.firestore().collection('users').doc(uid).get();
                    if (userDoc.exists) {
                        const userData = userDoc.data();
                        const userRole = userData?.role;
                        console.log(`🔍 [JOIN_ROOM] Role check for ${uid}: role='${userRole}' (raw)`);
                        console.log(`🔍 [CREATE_ROOM] Role check for ${uid}: role='${userRole}' (raw)`);

                        // Admin, Club Owners, and Sellers should only spectate
                        if (userRole === 'admin' || userRole === 'club_owner' || userRole === 'seller') {
                            console.log(`👑 [CREATE_ROOM] Usuario ${uid} con role '${userRole}' - NO se agregará como jugador`);
                            addHostAsPlayer = false;
                        }
                    }
                } catch (err) {
                    console.error(`[CREATE_ROOM] Error verificando role del usuario:`, err);
                }
            }

            // PASO 1: Crear el room PRIMERO para obtener el ID real
            const room = await roomManager.createRoom(socket.id, playerName, undefined, entryFee, customRoomId || undefined, {
                addHostAsPlayer,  // Dynamic based on user role
                isPublic,
                hostUid: uid,
                minBuyIn,
                maxBuyIn,
                smallBlind,
                bigBlind
            });
            const actualRoomId = room.id; // Este es el ID real del room

            // PASO 2: Reservar sesión con el ID REAL del room
            // ✅ CORREGIDO: Solo reservar créditos si el host será agregado como jugador
            if (uid && addHostAsPlayer) {
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

            // Inject UID into player object for the host (only if added as player)
            if (uid && addHostAsPlayer && room.players.length > 0) {
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

    socket.on('create_practice_room', async (playerName: string) => {
        try {
            const room = await roomManager.createPracticeRoom(socket.id, playerName);
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

            // 🔒 OPTIMIZATION: Check in-memory room first
            const existingRoom = roomManager.getRoom(roomId);
            if (existingRoom && existingRoom.tableConfig) {
                entryFee = existingRoom.tableConfig.minBuyIn;
                console.log(`[JOIN_ROOM] Using in-memory minBuyIn: ${entryFee}`);
            } else {
                // Fallback to Firestore
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

            // 🔒 ROLE-BASED SPECTATOR AUTO-DETECTION: Force spectator for admin/club_owner/seller
            let forceSpectator = isSpectator;
            if (uid && !isSpectator) {
                try {
                    const userDoc = await admin.firestore().collection('users').doc(uid).get();
                    if (userDoc.exists) {
                        const userData = userDoc.data();
                        const userRole = userData?.role;
                        console.log(`🔍 [JOIN_ROOM] Role check for ${uid}: role='${userRole}' (raw)`);

                        // Admin, Club Owners, and Sellers can only spectate public games
                        if (userRole === 'admin' || userRole === 'club_owner' || userRole === 'seller') {
                            console.log(`👑 [SPECTATOR] Usuario ${uid} con role '${userRole}' - forzando modo espectador`);
                            forceSpectator = true;
                        }
                    }
                } catch (err) {
                    console.error(`[JOIN_ROOM] Error verificando role del usuario:`, err);
                }
            }

            // === LÓGICA DE ESPECTADOR (NUEVA) ===
            if (forceSpectator === true) {
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
            let room = await roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee, uid);

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
                            // 🔒 FIX: Preserve Club/Seller ID during hydration
                            const clubId = roomData.clubId;
                            const sellerId = roomData.sellerId;
                            // 🔒 FIX: Preserve Buy-In Limits during hydration
                            const minBuyIn = roomData.minBuyIn;
                            const maxBuyIn = roomData.maxBuyIn;

                            if (!roomManager.getRoom(roomId)) {
                                try {
                                    const tempRoom = await roomManager.createRoom('temp-host', hostName, undefined, entryFee, roomId, {
                                        addHostAsPlayer: false,
                                        isPublic,
                                        isTournament,
                                        clubId,     // ✅ Pass clubId
                                        sellerId,   // ✅ Pass sellerId
                                        minBuyIn,   // ✅ Pass minBuyIn
                                        maxBuyIn    // ✅ Pass maxBuyIn
                                    });
                                    tempRoom.hostId = firestoreHostId;
                                } catch (err: any) {
                                    console.log(`Room ${roomId} created concurrently during hydration.`);
                                }
                            }

                            room = await roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);

                            // ✅ FIX: Sync player count to Firestore immediately after hydration join
                            if (room) {
                                persistGameStateAsync(roomId, room);
                            }
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

                // ✅ FIX: Sync player count to Firestore immediately after normal join
                persistGameStateAsync(roomId, room);

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
                // ✅ SECURITY FIX: Send personalized state to each player in the room
                const room = roomManager.getRoom(roomId);
                const game = (roomManager as any).games.get(roomId);

                if (data.type === 'hand_winner' || data.type === 'hand_results') {
                    // hand_winner/hand_results shows all cards anyway - broadcast to all
                    io.to(roomId).emit(data.type, data);
                } else if (room && game) {
                    // For game_update, send personalized state to EACH player (including their own cards)
                    room.players.forEach(player => {
                        const personalizedState = game.getPublicState(player.uid || player.id, false);
                        // Send to this specific player's socket
                        const playerSocket = io.sockets.sockets.get(player.id);
                        if (playerSocket) {
                            playerSocket.emit('game_update', personalizedState);
                        }
                    });
                }

                // Persist to Firestore after (async, non-blocking)
                if (data.type === 'hand_winner' || data.gameState) {
                    persistGameStateAsync(roomId, data.gameState || data);
                }
            });


            console.log(`🃏 Game started! Players: ${gameState.players?.length}`);

        } catch (e: any) {
            console.error(`❌ Error starting game: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('game_action', ({ roomId, action, amount }: { roomId: string, action: 'bet' | 'call' | 'fold' | 'check' | 'allin', amount?: number }) => {
        try {
            const userId = (socket as any).userId;
            const playerId = userId || socket.id;

            console.log(`🎲 [GAME_ACTION] ========== ACTION RECEIVED ==========`);
            console.log(`🎲 [GAME_ACTION] Room: ${roomId} | Action: ${action} | Amount: ${amount}`);
            console.log(`🎲 [GAME_ACTION] Socket ID: ${socket.id} | Firebase UID: ${userId}`);
            console.log(`🎲 [GAME_ACTION] Effective Player ID (for validation): ${playerId}`);

            // OPTIMIZACIÓN: Socket First, Database Later
            // 1. Actualizar estado en memoria (RAM) inmediatamente
            // FIX: Usar playerId (que puede ser el UID) en lugar de siempre socket.id
            const gameState = roomManager.handleGameAction(roomId, playerId, action, amount);
            console.log(`✅ [GAME_ACTION] Action processed successfully. Current turn: ${gameState.currentTurn}`);

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

        // 🔄 RECONNECTION RECOVERY:
        // Do NOT remove player immediately. Start grace period timer.
        // If they reconnect, the timer is cleared.
        // If timeout, 'player_timeout_leave' event is emitted which handles Exit Fee.
        roomManager.handleDisconnect(socket.id);
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

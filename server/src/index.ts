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
    }
});

const PORT = process.env.PORT || 3000;
const roomManager = new RoomManager();

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
    
    io.to(roomId).emit(event, data);

    if (event === 'game_started') {
        admin.firestore().collection('poker_tables').doc(roomId).set({
            status: 'active',
            lastActionTime: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true })
        .catch((e) => console.log(`⚠️ Could not sync to Firestore: ${e.message}`));
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
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                if (data.type === 'hand_winner') {
                    console.log(`🏆 Emitting hand_winner for room ${roomId}`);
                    io.to(roomId).emit('hand_winner', data);
                } else {
                    console.log(`📡 Emitting game_update for room ${roomId}`);
                    io.to(roomId).emit('game_update', data);
                }
            });
            console.log(`🃏 Game started! Players: ${gameState.players?.length}`);
            io.to(roomId).emit('game_started', gameState);
        } catch (e: any) {
            console.error(`❌ Error starting game: ${e.message}`);
            socket.emit('error', e.message);
        }
    });

    socket.on('game_action', ({ roomId, action, amount }: { roomId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number }) => {
        try {
            console.log(`🎲 game_action received: roomId=${roomId}, playerId=${socket.id}, action=${action}, amount=${amount}`);
            const gameState = roomManager.handleGameAction(roomId, socket.id, action, amount);
            console.log(`✅ Action processed successfully. Current turn: ${gameState.currentTurn}`);
            io.to(roomId).emit('game_update', gameState);
            console.log(`📡 game_update emitted to room ${roomId}`);
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
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0, minBuyIn);
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

// ... (imports)
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
    'https://poker-fa33a.web.app',  // Replace with your Firebase Hosting URL
    'https://poker-fa33a.firebaseapp.com'  // Replace with your Firebase Hosting URL
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
        // Find socket by socketId (playerId)
        const socket = io.sockets.sockets.get(playerId);
        if (socket) {
            socket.emit('error', 'You have been kicked for inactivity.');
            socket.disconnect(true);
        }
        io.to(roomId).emit('player_left', { id: playerId, reason: 'kicked' });
        return;
    }
    
    io.to(roomId).emit(event, data);

    // Sync Game Start to Firestore
    if (event === 'game_started') {
        admin.firestore().collection('poker_tables').doc(roomId).set({
            status: 'active',
            lastActionTime: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true })
        .catch((e) => console.log(`⚠️ Could not sync to Firestore: ${e.message}`));
    }
});

io.on('connection', (socket) => {
    // ... (authenticate handler remains same)
    console.log('User connected:', socket.id);

    socket.on('authenticate', async (data: { token: string }) => {
        const uid = await verifyFirebaseToken(data.token);
        if (!uid) {
            socket.emit('auth_error', { message: 'Invalid token' });
            return;
        }
        (socket as any).userId = uid;
        socket.emit('authenticated', { uid });
    });

    socket.on('create_room', async (data: any) => {
        // ... (auth and balance check same as before)
        const playerName = typeof data === 'string' ? data : data.playerName;
        const token = typeof data === 'object' ? data.token : null;
        const customRoomId = typeof data === 'object' ? data.roomId : null;

        try {
            let sessionId: string | undefined;
            let entryFee = 1000;
            let isPublic = false;
            let uid: string | undefined;

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
            }

            // Create room - IMPORTANT: Add hostUid to options so it gets added to Player
            const room = roomManager.createRoom(socket.id, playerName, sessionId, entryFee, customRoomId || undefined, { addHostAsPlayer: true, isPublic, hostUid: uid });
            
            // Inject UID into player object for the host
            if (uid && room.players.length > 0) {
                room.players[0].uid = uid;
            }

            room.hostId = uid;
            socket.join(room.id);
            
            const roomResponse = { ...room, isPublic, hostId: uid };
            socket.emit('room_created', roomResponse);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    // ... (create_practice_room same)

    socket.on('join_room', async ({ roomId, playerName, token }: { roomId: string, playerName: string, token?: string }) => {
        try {
            let sessionId: string | undefined;
            let entryFee = 1000;
            let uid: string | undefined;

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
                socket.emit('error', 'Authentication required');
                return;
            }

            const room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);
            
            if (room) {
                // Find the new player and inject UID
                const player = room.players.find(p => p.id === socket.id);
                if (player && uid) {
                    player.uid = uid;
                }

                socket.join(roomId);
                const roomWithFlags = { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId };
                io.to(roomId).emit('player_joined', roomWithFlags);
                socket.emit('room_joined', roomWithFlags);
            } else {
                socket.emit('error', 'Room not found');
            }
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    // ... (rest of handlers: start_game, game_action, player_ready, disconnect, request_top_up)
    // Keep them exactly as they were, they will work with the new RoomManager logic
    
    socket.on('start_game', ({ roomId }: { roomId: string }) => {
        try {
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                if (data.type === 'hand_winner') {
                    io.to(roomId).emit('hand_winner', data);
                } else {
                    io.to(roomId).emit('game_update', data);
                }
            });
            io.to(roomId).emit('game_started', gameState);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('game_action', ({ roomId, action, amount }: any) => {
        try {
            const gameState = roomManager.handleGameAction(roomId, socket.id, action, amount);
            io.to(roomId).emit('game_update', gameState);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('player_ready', ({ roomId, isReady }: any) => {
        const room = roomManager.toggleReady(roomId, socket.id, isReady);
        if (room) {
             io.to(roomId).emit('room_update', { ...room, isPublic: room.isPublic ?? false, hostId: room.hostId });
        }
    });

    socket.on('disconnect', async () => {
        const result = roomManager.removePlayer(socket.id);
        if (result) {
            const { roomId, player } = result;
            const uid = (socket as any).userId;
            
            // End session with exit fee if applicable (minBuyIn logic from previous file)
            if (player.pokerSessionId && uid) {
                // We simplified here, assumes 0 exit fee for now or read from DB as before
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0, 0); 
            }
            
            const room = roomManager.getRoom(roomId);
            if (room) {
                io.to(roomId).emit('player_left', { ...room, isPublic: room.isPublic ?? false });
                if (room.players.length < 2) {
                    // Logic to close room handled here or in RoomManager?
                    // Original code had logic here. We can keep it or rely on RoomManager check.
                    // RoomManager has check logic in removePlayer now? No, I didn't add it there yet to avoid side effects.
                    // But we have closeTableAndCashOut.
                    
                    // If < 2 players remain, close table.
                    if (room.players.length < 2) {
                        roomManager.closeTableAndCashOut(roomId);
                    }
                }
            }
        }
    });

    socket.on('request_top_up', async ({ roomId, amount, token }: any) => {
        try {
            if (!token) throw new Error('Auth required');
            const uid = await verifyFirebaseToken(token);
            if (!uid) throw new Error('Invalid token');
            
            const room = roomManager.getRoom(roomId);
            if (!room) throw new Error('Room not found');
            const player = room.players.find(p => p.id === socket.id);
            if (!player || !player.pokerSessionId) throw new Error('Player not found');

            const success = await addChipsToSession(uid, player.pokerSessionId, amount);
            if (success) {
                roomManager.addChips(roomId, socket.id, amount);
                socket.emit('top_up_success', { amount });
            } else {
                socket.emit('error', { message: 'Insufficient balance' });
            }
        } catch (e: any) {
             socket.emit('error', { message: e.message });
        }
    });
});

httpServer.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
});

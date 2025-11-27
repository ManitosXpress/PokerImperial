import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { RoomManager } from './game/RoomManager';
import { verifyFirebaseToken, getUserBalance, reservePokerSession, endPokerSession } from './middleware/firebaseAuth';

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
            // Allow requests with no origin (mobile apps, Postman, etc.)
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

    socket.on('create_room', async (data: { playerName: string, token?: string }) => {
        // Handle both string (old format) and object (new format)
        const playerName = typeof data === 'string' ? data : data.playerName;
        const token = typeof data === 'object' ? data.token : null;

        try {
            let sessionId: string | undefined;
            const entryFee = 1000; // Standard buy-in

            // Economy Check
            if (token) {
                const uid = await verifyFirebaseToken(token);
                if (uid) {
                    const balance = await getUserBalance(uid);

                    if (balance < entryFee) {
                        socket.emit('insufficient_balance', {
                            required: entryFee,
                            current: balance
                        });
                        return;
                    }

                    const sid = await reservePokerSession(uid, entryFee, 'new_room');
                    if (!sid) {
                        socket.emit('error', 'Failed to reserve credits');
                        return;
                    }
                    sessionId = sid;
                }
            } else {
                // If no token provided, we might want to block or allow for now. 
                // The requirement says "necesites credito para crear sala".
                // So we should probably enforce it if we can, but for backward compatibility during dev, maybe warn?
                // But the user said "necesites credito", so I should enforce it.
                // However, the frontend might not be sending token yet.
                // I will enforce it but handle the case where frontend isn't updated yet by emitting error.
                socket.emit('error', 'Authentication required to create room');
                return;
            }

            const room = roomManager.createRoom(socket.id, playerName, sessionId, entryFee);
            socket.join(room.id);
            socket.emit('room_created', room);
            console.log(`Room created: ${room.id} by ${playerName} (Session: ${sessionId})`);
        } catch (e: any) {
            console.error(e);
            socket.emit('error', e.message);
        }
    });

    socket.on('create_practice_room', (playerName: string) => {
        try {
            const room = roomManager.createPracticeRoom(socket.id, playerName);
            socket.join(room.id);
            socket.emit('room_created', room);

            console.log(`Practice Room created: ${room.id} by ${playerName}`);

            // Auto-start game for practice with a small delay to allow frontend to load
            setTimeout(() => {
                try {
                    const gameState = roomManager.startGame(room.id, socket.id, (data) => {
                        // Emit game state changes to all players in room
                        if (data.type === 'hand_winner') {
                            // Emit winner event
                            io.to(room.id).emit('hand_winner', data);
                        } else {
                            // Regular game update
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
            const entryFee = 1000; // Standard buy-in

            // Economy Check
            if (token) {
                const uid = await verifyFirebaseToken(token);
                if (uid) {
                    const balance = await getUserBalance(uid);

                    if (balance < entryFee) {
                        socket.emit('insufficient_balance', {
                            required: entryFee,
                            current: balance
                        });
                        return;
                    }

                    const sid = await reservePokerSession(uid, entryFee, roomId);
                    if (!sid) {
                        socket.emit('error', 'Failed to reserve credits');
                        return;
                    }
                    sessionId = sid;
                }
            } else {
                socket.emit('error', 'Authentication required to join room');
                return;
            }

            const room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);
            if (room) {
                socket.join(roomId);
                io.to(roomId).emit('player_joined', room); // Notify everyone in room
                socket.emit('room_joined', room); // Notify joiner
                console.log(`${playerName} joined room ${roomId} (Session: ${sessionId})`);
            } else {
                socket.emit('error', 'Room not found');
            }
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('start_game', ({ roomId }: { roomId: string }) => {
        try {
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                // Emit game state changes to all players in room
                if (data.type === 'hand_winner') {
                    // Emit winner event
                    io.to(roomId).emit('hand_winner', data);
                } else {
                    // Regular game update
                    io.to(roomId).emit('game_update', data);
                }
            });
            io.to(roomId).emit('game_started', gameState);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('game_action', ({ roomId, action, amount }: { roomId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number }) => {
        try {
            const gameState = roomManager.handleGameAction(roomId, socket.id, action, amount);
            io.to(roomId).emit('game_update', gameState);
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('disconnect', async () => {
        console.log('User disconnected:', socket.id);
        const result = roomManager.removePlayer(socket.id);
        if (result) {
            const { roomId, player } = result;
            const room = roomManager.getRoom(roomId);
            if (room) {
                io.to(roomId).emit('player_left', room);
            }

            // End Poker Session if exists
            if (player.pokerSessionId && (socket as any).userId) {
                const uid = (socket as any).userId;
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0);
            }
        }
    });
});

app.get('/', (req, res) => {
    res.send('Poker Server is running');
});

httpServer.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
});

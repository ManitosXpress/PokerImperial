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

// Set up RoomManager callback to emit events via IO
roomManager.setEmitCallback((roomId, event, data) => {
    io.to(roomId).emit(event, data);

    // Sync Game Start to Firestore
    if (event === 'game_started') {
        try {
            admin.firestore().collection('poker_tables').doc(roomId).update({
                status: 'active',
                lastActionTime: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`Synced game start to Firestore for room ${roomId}`);
        } catch (e) {
            console.error('Failed to sync game start to Firestore:', e);
        }
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

    socket.on('create_room', async (data: { playerName: string, token?: string, roomId?: string }) => {
        // Handle both string (old format) and object (new format)
        const playerName = typeof data === 'string' ? data : data.playerName;
        const token = typeof data === 'object' ? data.token : null;
        const customRoomId = typeof data === 'object' ? data.roomId : null;

        try {
            // Check if room already exists if custom ID provided
            if (customRoomId && roomManager.getRoom(customRoomId)) {
                // If room exists, treat as join (or error? For now error to be explicit, client should call join)
                // Actually, if client retries create, we might want to tell them it exists.
                socket.emit('error', 'Room already exists');
                return;
            }

            let sessionId: string | undefined;
            let entryFee = 1000; // Default buy-in

            // Get minBuyIn from Firestore if customRoomId is provided
            let isPublic = false; // Default to PRIVATE
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

            // Economy Check - Validate user has enough credits
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

                    const sid = await reservePokerSession(uid, entryFee, customRoomId || 'new_room');
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
            
            const room = roomManager.createRoom(socket.id, playerName, sessionId, entryFee, customRoomId || undefined, { addHostAsPlayer: true, isPublic });
            socket.join(room.id);
            
            // IMPORTANT: Explicitly include isPublic in the response
            const roomResponse = { ...room, isPublic };
            socket.emit('room_created', roomResponse);
            console.log(`Room created: ${room.id} by ${playerName} (Session: ${sessionId}, Public: ${isPublic})`);
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
            
            // Get minBuyIn from Firestore
            let entryFee = 1000; // Default buy-in
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
                // Use default entryFee
            }

            // Economy Check - Validate user has enough credits
            let uid: string | undefined;
            if (token) {
                const verifiedUid = await verifyFirebaseToken(token);
                if (verifiedUid) {
                    uid = verifiedUid;
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

            let room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);

            if (!room) {
                // Room not found in memory, check Firestore (Hydration)
                try {
                    const roomDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                    if (roomDoc.exists) {
                        const roomData = roomDoc.data();
                        // Only hydrate if status is active or waiting (or whatever valid status)
                        // Assuming 'active' or 'waiting' or 'created' are valid.
                        // Let's assume if it exists and not 'finished', we can hydrate.
                        if (roomData && roomData.status !== 'finished') {
                            console.log(`Hydrating room ${roomId} from Firestore...`);
                            // Create room without adding host as player immediately
                            // We need hostId and hostName from Firestore
                            const hostId = roomData.hostId || 'unknown';
                            const hostName = roomData.hostName || 'Host'; // You might need to store hostName in Firestore if not already
                            const isPublic = roomData.isPublic !== undefined ? roomData.isPublic : true; // Default to public if not specified

                            // Double check if room exists (race condition protection)
                            if (!roomManager.getRoom(roomId)) {
                                try {
                                    roomManager.createRoom(hostId, hostName, undefined, entryFee, roomId, { addHostAsPlayer: false, isPublic });
                                } catch (err: any) {
                                    console.log(`Room ${roomId} created concurrently during hydration.`);
                                }
                            }

                            // Now try joining again
                            room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);
                        }
                    }
                } catch (err) {
                    console.error(`Error hydrating room ${roomId}:`, err);
                }
            }

            if (room) {
                // Sync Ready State from Firestore
                try {
                    const roomDoc = await admin.firestore().collection('poker_tables').doc(roomId).get();
                    if (roomDoc.exists) {
                        const data = roomDoc.data();
                        const readyPlayers = data?.readyPlayers || [];
                        if (Array.isArray(readyPlayers) && readyPlayers.includes(socket.id)) { // socket.id might not be the uid? 
                            // Wait, readyPlayers in Firestore stores UIDs (user.uid).
                            // socket.id is the socket connection ID.
                            // We need to check against the Player ID used in RoomManager.
                            // In joinRoom, we passed `socket.id` as the playerId?
                            // Let's check how joinRoom is called:
                            // const room = roomManager.joinRoom(roomId, socket.id, playerName, sessionId, entryFee);
                            // Yes, playerId is socket.id.

                            // BUT Firestore stores User UIDs (e.g. "7Yvkp...")
                            // Socket ID is ephemeral (e.g. "A8200...")
                            // This is a mismatch!

                            // If RoomManager uses socket.id as playerId, but Firestore uses UID...
                            // We have a problem. The game logic seems to rely on socket.id.
                            // But persistence relies on UID.

                            // Let's check how `_toggleReady` works in client:
                            // 'readyPlayers': ... FieldValue.arrayUnion([currentUser.uid])

                            // So Firestore has UIDs.
                            // RoomManager has Socket IDs.

                            // We need to map them.
                            // When joining, we authenticated the user and got `uid`.
                            // We should probably use `uid` as playerId in RoomManager if we want persistence?
                            // OR we need to store the mapping.

                            // In `index.ts`:
                            // const uid = await verifyFirebaseToken(token);
                            // ...
                            // const room = roomManager.joinRoom(roomId, socket.id, ...);

                            // If we change RoomManager to use UID as playerId, it might break other things (like socket emitting to specific socketId).
                            // Usually, we store `socketId` on the player object, but use `uid` as the ID.
                            // OR we store `uid` on the player object.

                            // Let's check Player interface in RoomManager.ts (inferred).
                            // It has `id`.

                            // If I change joinRoom to use `uid` instead of `socket.id`:
                            // roomManager.joinRoom(roomId, uid, ...);
                            // Then `io.to(playerId)` won't work if playerId is UID.
                            // We need to look up socket by UID or store socketId in Player object.

                            // Let's look at `RoomManager.ts` again.
                            // It doesn't seem to use `io.to(player.id)`. It uses `io.to(roomId)`.
                            // But `socket.on('disconnect')` uses `socket.id` to remove player.
                            // `roomManager.removePlayer(socket.id)`

                            // If we use UID as ID, `removePlayer(socket.id)` will fail because it looks for `p.id === socket.id`.

                            // We need to fix this ID mismatch.
                            // Option 1: RoomManager uses SocketID. We store UID in Player object too.
                            // Option 2: RoomManager uses UID. We store SocketID in Player object.

                            // Given the current codebase, `RoomManager` seems designed around SocketID (removePlayer uses it).
                            // So `player.id` IS `socket.id`.

                            // So, to sync with Firestore (which has UIDs), we need to know the UID of the player.
                            // We DO have the UID in `join_room` scope!
                            // `const uid = await verifyFirebaseToken(token);`

                            // So we can check: `readyPlayers.includes(uid)`
                            // If true, we call `roomManager.toggleReady(roomId, socket.id, true)`.

                            // Wait, does `RoomManager` store UID?
                            // `joinRoom` params: `playerId, playerName, sessionId`.
                            // It doesn't take UID explicitly.
                            // But we can pass it?
                            // The `Player` interface has `id` (socketId).
                            // We should probably add `uid` to Player interface if needed, but for now we just need to sync ready state.

                            // So:
                            // 1. Get UID from token (we already have it).
                            // 2. Check if `readyPlayers` contains `uid`.
                            // 3. If yes, `roomManager.toggleReady(roomId, socket.id, true)`.

                            // This seems correct and sufficient for the sync.

                            // One catch: `verifyFirebaseToken` is inside the `if (token)` block.
                            // We need to make sure we have `uid` available.

                            let uid: string | undefined;
                            if (token) {
                                uid = await verifyFirebaseToken(token) ?? undefined;
                            }

                            // ... (existing logic) ...

                            if (uid && data?.readyPlayers && Array.isArray(data.readyPlayers) && data.readyPlayers.includes(uid)) {
                                console.log(`Syncing ready state for ${playerName} (${uid})`);
                                roomManager.toggleReady(roomId, socket.id, true);
                            }
                        }
                    }
                } catch (err) {
                    console.error('Error syncing ready state:', err);
                }

                socket.join(roomId);
                
                // Ensure isPublic is included in the emitted room object
                const roomWithPublicFlag = { ...room, isPublic: room.isPublic ?? false };
                io.to(roomId).emit('player_joined', roomWithPublicFlag); // Notify everyone in room
                socket.emit('room_joined', roomWithPublicFlag); // Notify joiner
                console.log(`${playerName} joined room ${roomId} (Session: ${sessionId}, Public: ${room.isPublic ?? false})`);
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

    socket.on('player_ready', ({ roomId, isReady }: { roomId: string, isReady: boolean }) => {
        try {
            const room = roomManager.toggleReady(roomId, socket.id, isReady);
            if (room) {
                const roomWithPublicFlag = { ...room, isPublic: room.isPublic ?? false };
                io.to(roomId).emit('room_update', roomWithPublicFlag); // Sync room state (including ready status)
            }
        } catch (e: any) {
            socket.emit('error', e.message);
        }
    });

    socket.on('disconnect', async () => {
        console.log('User disconnected:', socket.id);
        const result = roomManager.removePlayer(socket.id);
        if (result) {
            const { roomId, player } = result;
            const uid = (socket as any).userId;

            // 1. Get minBuyIn from Firestore and deduct it when player leaves
            let minBuyIn = 1000; // Default
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

            // Process leaver - deduct minBuyIn as exit fee
            if (player.pokerSessionId && uid) {
                await endPokerSession(uid, player.pokerSessionId, player.chips, player.totalRakePaid || 0, minBuyIn);
            }

            // 2. Update Firestore - Remove player from players array and readyPlayers
            if (uid) {
                try {
                    const tableRef = admin.firestore().collection('poker_tables').doc(roomId);
                    const tableDoc = await tableRef.get();
                    
                    if (tableDoc.exists) {
                        const tableData = tableDoc.data();
                        if (tableData) {
                            // Remove player from players array
                            const players = Array.isArray(tableData.players) ? [...tableData.players] : [];
                            const updatedPlayers = players.filter((p: any) => {
                                // Handle both object format {id: uid} and direct uid string
                                const playerId = typeof p === 'object' ? p.id : p;
                                return playerId !== uid;
                            });

                            // Remove from readyPlayers array
                            const readyPlayers = Array.isArray(tableData.readyPlayers) ? [...tableData.readyPlayers] : [];
                            const updatedReadyPlayers = readyPlayers.filter((id: string) => id !== uid);

                            // Update Firestore
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

            // 3. Check remaining room state
            const room = roomManager.getRoom(roomId);
            if (room) {
                const roomWithPublicFlag = { ...room, isPublic: room.isPublic ?? false };
                io.to(roomId).emit('player_left', roomWithPublicFlag);

                // Check if we should close the room (less than 2 players)
                // Note: Bots count as players in the current implementation, so this works for practice rooms too (1 human + 3 bots = 4, human leaves -> 3 bots remain, room stays open? No, practice room usually ends when human leaves. But for multiplayer, if < 2 players, close.)
                // Actually, for practice room, if the human leaves, we probably want to close it to save resources.
                // But let's stick to the rule: "si son 2 jugadores [total] ... se termine la sala".
                // If I am in a room with 1 other person (2 total), and I leave. 1 remains. Close.
                // If I am in a room with bots (4 total), and I leave. 3 remain. Keep open?
                // The user said "si son 2 jugadores sin son mas de 2 que siga nomas".
                // If I assume "jugadores" means humans?
                // But `room.players` includes bots.
                // Let's assume strict player count < 2.

                if (room.players.length < 2) {
                    console.log(`Room ${roomId} has less than 2 players. Closing room.`);

                    // Refund remaining players
                    for (const remainingPlayer of room.players) {
                        if (remainingPlayer.pokerSessionId && !remainingPlayer.isBot) {
                            // End session for remaining player (no penalty)
                            await endPokerSession(remainingPlayer.id, remainingPlayer.pokerSessionId, remainingPlayer.chips, remainingPlayer.totalRakePaid || 0, 0);
                        }
                    }

                    // Notify and delete room
                    io.to(roomId).emit('room_closed', { reason: 'Not enough players' });
                    roomManager.deleteRoom(roomId);
                }
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
    // Expose internal state for debugging
    // We need to access RoomManager's rooms. 
    // Since roomManager is available in this scope:
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

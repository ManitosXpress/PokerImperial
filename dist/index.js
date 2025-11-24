"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const http_1 = require("http");
const socket_io_1 = require("socket.io");
const RoomManager_1 = require("./game/RoomManager");
const app = (0, express_1.default)();
const httpServer = (0, http_1.createServer)(app);
// CORS configuration for production and development
const allowedOrigins = [
    'http://localhost:3000',
    'http://localhost:5000',
    'https://poker-fa33a.web.app', // Replace with your Firebase Hosting URL
    'https://poker-fa33a.firebaseapp.com' // Replace with your Firebase Hosting URL
];
const io = new socket_io_1.Server(httpServer, {
    cors: {
        origin: (origin, callback) => {
            // Allow requests with no origin (mobile apps, Postman, etc.)
            if (!origin)
                return callback(null, true);
            if (allowedOrigins.includes(origin)) {
                callback(null, true);
            }
            else {
                console.log('Blocked origin:', origin);
                callback(new Error('Not allowed by CORS'));
            }
        },
        methods: ["GET", "POST"],
        credentials: true
    }
});
const PORT = process.env.PORT || 3000;
const roomManager = new RoomManager_1.RoomManager();
io.on('connection', (socket) => {
    console.log('User connected:', socket.id);
    socket.on('create_room', (playerName) => {
        try {
            const room = roomManager.createRoom(socket.id, playerName);
            socket.join(room.id);
            socket.emit('room_created', room);
            console.log(`Room created: ${room.id} by ${playerName}`);
        }
        catch (e) {
            console.error(e);
        }
    });
    socket.on('create_practice_room', (playerName) => {
        try {
            const room = roomManager.createPracticeRoom(socket.id, playerName);
            socket.join(room.id);
            socket.emit('room_created', room);
            // Hook up bot updates
            const game = roomManager['games'].get(room.id); // Access private map
            if (game) {
                game.onGameStateChange = (state) => {
                    io.to(room.id).emit('game_update', state);
                };
            }
            // Auto-start game for practice
            const gameState = roomManager.startGame(room.id, socket.id);
            io.to(room.id).emit('game_started', gameState);
            console.log(`Practice Room created: ${room.id} by ${playerName}`);
        }
        catch (e) {
            console.error(e);
        }
    });
    socket.on('join_room', ({ roomId, playerName }) => {
        try {
            const room = roomManager.joinRoom(roomId, socket.id, playerName);
            if (room) {
                socket.join(roomId);
                io.to(roomId).emit('player_joined', room); // Notify everyone in room
                socket.emit('room_joined', room); // Notify joiner
                console.log(`${playerName} joined room ${roomId}`);
            }
            else {
                socket.emit('error', 'Room not found');
            }
        }
        catch (e) {
            socket.emit('error', e.message);
        }
    });
    socket.on('start_game', ({ roomId }) => {
        try {
            const gameState = roomManager.startGame(roomId, socket.id, (data) => {
                // Emit game state changes to all players in room
                if (data.type === 'hand_winner') {
                    // Emit winner event
                    io.to(roomId).emit('hand_winner', data);
                }
                else {
                    // Regular game update
                    io.to(roomId).emit('game_update', data);
                }
            });
            io.to(roomId).emit('game_started', gameState);
        }
        catch (e) {
            socket.emit('error', e.message);
        }
    });
    socket.on('game_action', ({ roomId, action, amount }) => {
        try {
            const gameState = roomManager.handleGameAction(roomId, socket.id, action, amount);
            io.to(roomId).emit('game_update', gameState);
        }
        catch (e) {
            socket.emit('error', e.message);
        }
    });
    socket.on('disconnect', () => {
        console.log('User disconnected:', socket.id);
        const roomId = roomManager.removePlayer(socket.id);
        if (roomId) {
            const room = roomManager.getRoom(roomId);
            if (room) {
                io.to(roomId).emit('player_left', room);
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

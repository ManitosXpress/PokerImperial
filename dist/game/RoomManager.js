"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RoomManager = void 0;
const PokerGame_1 = require("./PokerGame");
class RoomManager {
    constructor() {
        this.rooms = new Map();
        this.games = new Map();
    }
    createPracticeRoom(hostId, hostName) {
        const room = this.createRoom(hostId, hostName);
        // Add 3 Bots
        for (let i = 1; i <= 3; i++) {
            const bot = {
                id: `bot-${i}`,
                name: `Bot ${i}`,
                chips: 1000,
                isFolded: false,
                currentBet: 0,
                isBot: true
            };
            room.players.push(bot);
        }
        return room;
    }
    createRoom(hostId, hostName) {
        const roomId = this.generateRoomId();
        const host = {
            id: hostId,
            name: hostName,
            chips: 1000, // Default starting chips
            isFolded: false,
            currentBet: 0
        };
        const newRoom = {
            id: roomId,
            players: [host],
            maxPlayers: 6,
            gameState: 'waiting',
            pot: 0,
            communityCards: [],
            currentTurn: hostId,
            dealerId: hostId
        };
        this.rooms.set(roomId, newRoom);
        this.games.set(roomId, new PokerGame_1.PokerGame());
        return newRoom;
    }
    joinRoom(roomId, playerId, playerName) {
        const room = this.rooms.get(roomId);
        if (!room)
            return null;
        if (room.players.length >= room.maxPlayers) {
            throw new Error('Room is full');
        }
        if (room.gameState !== 'waiting') {
            throw new Error('Game already in progress');
        }
        const newPlayer = {
            id: playerId,
            name: playerName,
            chips: 1000,
            isFolded: false,
            currentBet: 0
        };
        room.players.push(newPlayer);
        return room;
    }
    getRoom(roomId) {
        return this.rooms.get(roomId);
    }
    removePlayer(playerId) {
        // Find room with player and remove them
        for (const [roomId, room] of this.rooms) {
            const index = room.players.findIndex(p => p.id === playerId);
            if (index !== -1) {
                room.players.splice(index, 1);
                if (room.players.length === 0) {
                    this.rooms.delete(roomId);
                    this.games.delete(roomId);
                }
                return roomId;
            }
        }
        return null;
    }
    startGame(roomId, playerId, emitCallback) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);
        if (!room || !game)
            throw new Error('Room or game not found');
        if (room.players[0].id !== playerId)
            throw new Error('Only host can start game');
        // Set callback for game state changes (including winner events)
        if (emitCallback) {
            game.onGameStateChange = emitCallback;
        }
        game.startGame(room.players);
        room.gameState = 'playing';
        return game.getGameState();
    }
    handleGameAction(roomId, playerId, action, amount) {
        const game = this.games.get(roomId);
        if (!game)
            throw new Error('Game not found');
        game.handleAction(playerId, action, amount);
        return game.getGameState();
    }
    getGameState(roomId) {
        const game = this.games.get(roomId);
        if (!game)
            return null;
        return game.getGameState();
    }
    generateRoomId() {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}
exports.RoomManager = RoomManager;

import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';

export class RoomManager {
    private rooms: Map<string, Room> = new Map();
    private games: Map<string, PokerGame> = new Map();

    constructor() { }

    public createPracticeRoom(hostId: string, hostName: string): Room {
        const room = this.createRoom(hostId, hostName);

        // Add 3 Bots
        for (let i = 1; i <= 3; i++) {
            const bot: Player = {
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

    public createRoom(hostId: string, hostName: string): Room {
        const roomId = this.generateRoomId();
        const host: Player = {
            id: hostId,
            name: hostName,
            chips: 1000, // Default starting chips
            isFolded: false,
            currentBet: 0
        };

        const newRoom: Room = {
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
        this.games.set(roomId, new PokerGame());

        return newRoom;
    }

    public joinRoom(roomId: string, playerId: string, playerName: string): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        if (room.players.length >= room.maxPlayers) {
            throw new Error('Room is full');
        }

        if (room.gameState !== 'waiting') {
            throw new Error('Game already in progress');
        }

        const newPlayer: Player = {
            id: playerId,
            name: playerName,
            chips: 1000,
            isFolded: false,
            currentBet: 0
        };

        room.players.push(newPlayer);
        return room;
    }

    public getRoom(roomId: string): Room | undefined {
        return this.rooms.get(roomId);
    }

    public removePlayer(playerId: string) {
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

    public startGame(roomId: string, playerId: string, emitCallback?: (data: any) => void) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);

        if (!room || !game) throw new Error('Room or game not found');
        if (room.players[0].id !== playerId) throw new Error('Only host can start game');

        // Set callback for game state changes (including winner events)
        if (emitCallback) {
            game.onGameStateChange = emitCallback;
        }

        game.startGame(room.players);
        room.gameState = 'playing';
        return game.getGameState();
    }

    public handleGameAction(roomId: string, playerId: string, action: 'bet' | 'call' | 'fold' | 'check', amount?: number) {
        const game = this.games.get(roomId);
        if (!game) throw new Error('Game not found');

        game.handleAction(playerId, action, amount);
        return game.getGameState();
    }

    public getGameState(roomId: string) {
        const game = this.games.get(roomId);
        if (!game) return null;
        return game.getGameState();
    }

    private generateRoomId(): string {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}

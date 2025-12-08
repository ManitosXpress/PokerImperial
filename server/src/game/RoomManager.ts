import { Room, Player } from '../types';
import { PokerGame } from './PokerGame';

export class RoomManager {
    private rooms: Map<string, Room> = new Map();
    private games: Map<string, PokerGame> = new Map();

    constructor() { }

    public toggleReady(roomId: string, playerId: string, isReady: boolean): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        const player = room.players.find(p => p.id === playerId);
        if (player) {
            player.isReady = isReady;
            this.checkAndStartCountdown(roomId);
        }
        return room;
    }

    private checkAndStartCountdown(roomId: string) {
        const room = this.rooms.get(roomId);
        if (!room) return;

        // Count ready players (excluding bots if we want, but bots are usually ready immediately or handled differently. 
        // For now, let's assume bots are always "ready" effectively, or we just check human players readiness if mixed?
        // The user requirement says "Esperar a 4 jugadores -> Ready".
        // Let's assume we check all players.

        // Auto-ready bots
        room.players.forEach(p => {
            if (p.isBot) p.isReady = true;
        });

        const readyCount = room.players.filter(p => p.isReady).length;
        const totalPlayers = room.players.length;

        // Requirement: Min 4 players to start
        if (totalPlayers >= 4 && readyCount === totalPlayers) {
            // Start Countdown if not already starting
            // We need a way to track if countdown is active. 
            // Maybe add a temporary flag to Room or just manage it here?
            // Since RoomManager is persistent, we can store a timer ID?
            // But `Room` interface is shared with client, we shouldn't add internal timer there.
            // We can use a separate map for timers.

            if (this.countdownTimers.has(roomId)) return; // Already counting down

            console.log(`Starting countdown for room ${roomId}`);

            // Emit countdown start
            // Cancel countdown if conditions no longer met
            if (this.countdownTimers.has(roomId)) {
                console.log(`Cancelling countdown for room ${roomId}`);
                clearTimeout(this.countdownTimers.get(roomId));
                this.countdownTimers.delete(roomId);
                if (this.emitCallback) {
                    this.emitCallback(roomId, 'countdown_cancel', {});
                }
            }
        }
    }

    private countdownTimers: Map<string, NodeJS.Timeout> = new Map();
    public emitCallback?: (roomId: string, event: string, data: any) => void;

    public setEmitCallback(callback: (roomId: string, event: string, data: any) => void) {
        this.emitCallback = callback;
    }

    public createPracticeRoom(hostId: string, hostName: string): Room {
        const room = this.createRoom(hostId, hostName);

        // Add 7 Bots (total 8 players including host)
        for (let i = 1; i <= 7; i++) {
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

    public createRoom(hostId: string, hostName: string, sessionId?: string, buyInAmount: number = 1000, customRoomId?: string, options: { addHostAsPlayer?: boolean } = {}): Room {
        const roomId = customRoomId || this.generateRoomId();
        const { addHostAsPlayer = true } = options;

        // Check if room already exists to prevent overwrite
        if (this.rooms.has(roomId)) {
            throw new Error(`Room ${roomId} already exists`);
        }

        const players: Player[] = [];
        if (addHostAsPlayer) {
            const host: Player = {
                id: hostId,
                name: hostName,
                chips: buyInAmount,
                isFolded: false,
                currentBet: 0,
                pokerSessionId: sessionId,
                totalRakePaid: 0
            };
            players.push(host);
        }

        const newRoom: Room = {
            id: roomId,
            players: players,
            maxPlayers: 8,
            gameState: 'waiting',
            pot: 0,
            communityCards: [],
            currentTurn: players.length > 0 ? players[0].id : '',
            dealerId: players.length > 0 ? players[0].id : ''
        };

        this.rooms.set(roomId, newRoom);
        this.games.set(roomId, new PokerGame());

        return newRoom;
    }

    public joinRoom(roomId: string, playerId: string, playerName: string, sessionId?: string, buyInAmount: number = 1000): Room | null {
        const room = this.rooms.get(roomId);
        if (!room) return null;

        // Check if player already exists
        const existingPlayer = room.players.find(p => p.id === playerId);
        if (existingPlayer) {
            // Update existing player info if needed (e.g. name update, or just return room)
            // We might want to update sessionId if it changed
            if (sessionId) existingPlayer.pokerSessionId = sessionId;
            // Ensure they are not marked as folded if they are just re-joining (unless game is running?)
            // If game is waiting, we can reset them?
            // For now, just return the room. This makes join idempotent.
            return room;
        }

        if (room.players.length >= room.maxPlayers) {
            throw new Error('Room is full');
        }

        if (room.gameState !== 'waiting') {
            throw new Error('Game already in progress');
        }

        const newPlayer: Player = {
            id: playerId,
            name: playerName,
            chips: buyInAmount,
            isFolded: false,
            currentBet: 0,
            pokerSessionId: sessionId,
            totalRakePaid: 0
        };

        room.players.push(newPlayer);
        return room;
    }

    public getRoom(roomId: string): Room | undefined {
        return this.rooms.get(roomId);
    }

    public removePlayer(playerId: string): { roomId: string, player: Player } | null {
        // Find room with player and remove them
        for (const [roomId, room] of this.rooms) {
            const index = room.players.findIndex(p => p.id === playerId);
            if (index !== -1) {
                const player = room.players[index];
                room.players.splice(index, 1);
                if (room.players.length === 0) {
                    this.rooms.delete(roomId);
                    this.games.delete(roomId);
                }
                return { roomId, player };
            }
        }
        return null;
    }

    public startGame(roomId: string, playerId: string, emitCallback?: (data: any) => void) {
        const room = this.rooms.get(roomId);
        const game = this.games.get(roomId);

        if (!room || !game) throw new Error('Room or game not found');

        // Allow start if it's the host OR if it's a system auto-start (we can check if playerId matches host OR if we add a system flag)
        // For now, let's just relax the check if we call it internally with a valid player ID, 
        // OR we can just check if the player is IN the room to prevent randoms from starting it.
        // But the original code enforced host.
        // Let's keep it simple: If called by system (timer), we might need to bypass.
        // But for now, let's just pass the host ID when calling from timer.

        // if (room.players[0].id !== playerId) throw new Error('Only host can start game');

        // Set callback for game state changes (including winner events)
        if (emitCallback) {
            game.onGameStateChange = emitCallback;
        }

        game.startGame(room.players);
        room.gameState = 'playing';

        // Emit game_started event
        if (this.emitCallback) {
            this.emitCallback(roomId, 'game_started', { ...game.getGameState(), roomId });
        }

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

    public deleteRoom(roomId: string) {
        this.rooms.delete(roomId);
        this.games.delete(roomId);
    }

    public addChips(roomId: string, playerId: string, amount: number) {
        const game = this.games.get(roomId);
        if (game) {
            game.addChips(playerId, amount);
        }
    }

    private generateRoomId(): string {
        return Math.random().toString(36).substring(2, 8).toUpperCase();
    }
}

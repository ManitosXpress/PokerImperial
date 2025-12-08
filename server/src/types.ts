export interface Player {
    id: string;
    name: string;
    chips: number;
    hand?: string[];
    isFolded: boolean;
    currentBet: number;
    isBot?: boolean;
    pokerSessionId?: string;
    totalRakePaid?: number;
    isReady?: boolean;
}

export interface Room {
    id: string;
    players: Player[];
    maxPlayers: number;
    gameState: 'waiting' | 'playing' | 'finished';
    pot: number;
    communityCards: string[];
    currentTurn: string; // Player ID
    dealerId: string;
    isPublic?: boolean; // If true or undefined, auto-start. If false (private), require host to start manually.
    hostId?: string; // ID of the player who created the room (for frontend to determine host privileges)
}

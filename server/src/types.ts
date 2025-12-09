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
    isSitOut?: boolean; // New field for AFK system
}

export interface Room {
    id: string;
    players: Player[];
    maxPlayers: number;
    gameState: 'waiting' | 'playing' | 'finished';
    pot: number;
    communityCards: string[];
    currentTurn: string;
    dealerId: string;
    isPublic?: boolean;
    hostId?: string;
}

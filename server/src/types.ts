export interface Player {
    id: string;
    uid?: string; // Added Firebase UID for cashout
    name: string;
    chips: number;
    hand?: string[];
    isFolded: boolean;
    currentBet: number;
    isBot?: boolean;
    pokerSessionId?: string;
    totalRakePaid?: number;
    isReady?: boolean;
    isSitOut?: boolean;
    isAllIn?: boolean; // Flag para jugadores que apostaron todo
    status?: 'PLAYING' | 'WAITING_FOR_REBUY' | 'ELIMINATED';
    hasActed?: boolean; // CRÍTICO: Rastrea si el jugador ya actuó en esta ronda de apuestas
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
    isTournament?: boolean;
    autoStartTimer?: NodeJS.Timeout | null;
    minBuyIn?: number;
    maxBuyIn?: number;
    clubId?: string;   // 💰 Club ID for rake distribution
    sellerId?: string; // 💰 Seller ID for rake distribution
}

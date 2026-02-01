import { TableConfig, PlayerSession } from './types/TableConfig';

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
    // ⏱️ AFK Detection: Tracks consecutive hands player has been sitting out
    // Auto-kick triggers after 3 consecutive sit-outs
    handCounter?: number;
    isAllIn?: boolean; // Flag para jugadores que apostaron todo
    status?: 'PLAYING' | 'WAITING_FOR_REBUY' | 'ELIMINATED' | 'active' | 'spectator';
    hasActed?: boolean; // CRÍTICO: Rastrea si el jugador ya actuó en esta ronda de apuestas
    isSeated?: boolean;
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

    // 🔒 IMMUTABLE TABLE CONFIGURATION (BUG FIX: Buy-in persistence)
    tableConfig?: TableConfig;

    // ⚠️ DEPRECATED: Use tableConfig instead
    /** @deprecated Use tableConfig.minBuyIn */
    minBuyIn?: number;
    /** @deprecated Use tableConfig.maxBuyIn */
    maxBuyIn?: number;

    // 💰 RAKE DISTRIBUTION
    clubId?: string;   // Club ID for rake distribution
    sellerId?: string; // Seller ID for rake distribution

    // 🕐 GRACE PERIOD (BUG FIX: Zombie rooms)
    gracePeriodTimeout?: NodeJS.Timeout;

    // 👥 PLAYER SESSIONS (BUG FIX: Role-based rake)
    playerSessions?: Map<string, PlayerSession>;
}

export interface User {
    uid: string;
    email: string;
    displayName: string;
    photoURL?: string;
    credits: number;
    clubId?: string;
    sellerId?: string;
    createdAt: any; // Firestore Timestamp
}

export interface Club {
    id: string;
    name: string;
    ownerId: string;
    walletBalance: number; // Accumulated earnings
    createdAt: any;
}

export interface Seller {
    id: string;
    name: string;
    clubId: string; // Seller belongs to a club
    walletBalance: number; // Accumulated earnings
    createdAt: any;
}

export interface SystemWallet {
    id: string; // usually 'main' or 'platform'
    balance: number;
    updatedAt: any;
}

export interface PlayerInvolved {
    uid: string;
    betAmount: number; // Amount contributed to the pot
    clubId?: string;
    sellerId?: string;
}

export interface SettleRoundRequest {
    potTotal: number;
    winnerUid: string;
    playersInvolved: PlayerInvolved[];
    gameId: string; // For audit logs
    tableId: string; // ID de la mesa para actualizar el stack del jugador
}

export interface LedgerEntry {
    type: 'RAKE_DISTRIBUTION' | 'WIN_PRIZE';
    amount: number;
    source: string; // e.g., 'game_round_123'
    destination: string; // e.g., 'club_456', 'platform', 'user_789'
    description: string;
    timestamp: any;
    metadata?: any;
}

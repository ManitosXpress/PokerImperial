/**
 * TableConfig.ts
 * 
 * Immutable configuration for poker tables.
 * Once created, these values CANNOT be changed to prevent inconsistencies.
 * 
 * SECURITY: Prevents dynamic manipulation of buy-in limits mid-game.
 */

export interface TableConfig {
    /** Minimum buy-in amount (immutable) */
    readonly minBuyIn: number;

    /** Maximum buy-in amount (immutable) */
    readonly maxBuyIn: number;

    /** Small blind amount (immutable) */
    readonly smallBlind: number;

    /** Big blind amount (immutable) */
    readonly bigBlind: number;

    /** Anti-tampering: Creation timestamp */
    readonly createdAt: number;
}

/**
 * PlayerSession
 * 
 * Metadata for player authentication and role-based rake distribution.
 * Required for financial transactions.
 */
export interface PlayerSession {
    /** Firebase Authentication UID (REQUIRED) */
    uid: string;

    /** User role for rake distribution */
    role: 'admin' | 'club_owner' | 'seller' | 'player';

    /** Club ID for rake distribution (if applicable) */
    clubId?: string;

    /** Parent seller ID for rake distribution (if applicable) */
    parentSellerId?: string;

    /** Session start timestamp */
    joinedAt: number;
}

/**
 * RakeDistribution
 * 
 * Breakdown of rake allocation for audit trail.
 */
export interface RakeDistribution {
    /** Total rake collected (8% of pot) */
    totalRake: number;

    /** Net pot after rake (goes to winner) */
    netPot: number;

    /** Platform share */
    platformShare: number;

    /** Club owner share (0 if no club) */
    clubShare: number;

    /** Seller share (0 if no seller) */
    sellerShare: number;

    /** Table type for audit */
    isPrivate: boolean;

    /** Timestamp of distribution */
    timestamp: number;
}

/**
 * Factory function to create immutable TableConfig
 * 
 * Validates inputs and returns frozen object.
 */
export function createTableConfig(
    minBuyIn: number,
    maxBuyIn: number,
    smallBlind: number,
    bigBlind: number
): TableConfig {
    // Validation
    if (minBuyIn <= 0) throw new Error('minBuyIn must be positive');
    if (maxBuyIn <= minBuyIn) throw new Error('maxBuyIn must be greater than minBuyIn');
    if (smallBlind <= 0) throw new Error('smallBlind must be positive');
    if (bigBlind <= smallBlind) throw new Error('bigBlind must be greater than smallBlind');
    if (minBuyIn < bigBlind * 10) {
        console.warn(`⚠️ minBuyIn (${minBuyIn}) is less than 10x bigBlind (${bigBlind}). Recommended: ${bigBlind * 10}`);
    }

    const config: TableConfig = {
        minBuyIn,
        maxBuyIn,
        smallBlind,
        bigBlind,
        createdAt: Date.now()
    };

    // Freeze to make truly immutable
    return Object.freeze(config);
}

/**
 * Factory function to create PlayerSession
 */
export function createPlayerSession(
    uid: string,
    role: 'admin' | 'club_owner' | 'seller' | 'player' = 'player',
    clubId?: string,
    parentSellerId?: string
): PlayerSession {
    if (!uid) throw new Error('uid is required for PlayerSession');

    return {
        uid,
        role,
        clubId,
        parentSellerId,
        joinedAt: Date.now()
    };
}

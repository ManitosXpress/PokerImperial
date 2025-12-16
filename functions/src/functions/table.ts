import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Lazy initialization de Firestore para evitar timeout en deploy
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

export const createPublicTable = functions.https.onCall(async (data, context) => {
    // 1. Validate Authentication
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'The function must be called while authenticated.'
        );
    }

    const uid = context.auth.uid;
    const db = admin.firestore();

    // 2. Validate User Role (Must be Club Owner)
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data();

    if (!userData || userData.role !== 'club') {
        throw new functions.https.HttpsError(
            'permission-denied',
            'Only Club Owners can create public tables.'
        );
    }

    // 3. Validate Input Data
    const { name, smallBlind, bigBlind, minBuyIn, maxBuyIn } = data;

    if (!name || !smallBlind || !bigBlind || !minBuyIn || !maxBuyIn) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Missing required fields: name, smallBlind, bigBlind, minBuyIn, maxBuyIn'
        );
    }

    // 4. Check Limits (Optional: Prevent spam)
    const activeTablesQuery = await db.collection('poker_tables')
        .where('createdByClubId', '==', uid)
        .where('status', '==', 'active')
        .get();

    if (activeTablesQuery.size >= 10) { // Limit to 10 active tables per club
        throw new functions.https.HttpsError(
            'resource-exhausted',
            'You have reached the limit of active tables.'
        );
    }

    // 5. Create Table Document
    const tableId = db.collection('poker_tables').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const newTable = {
        id: tableId,
        name: name,
        smallBlind: Number(smallBlind),
        bigBlind: Number(bigBlind),
        minBuyIn: Number(minBuyIn),
        maxBuyIn: Number(maxBuyIn),
        createdByClubId: uid,
        createdByName: userData.displayName || 'Club Owner',
        isPublic: true,
        status: 'active',
        players: [],
        spectators: [],
        createdAt: timestamp,
        currentRound: null,
        pot: 0,
        communityCards: [],
        deck: [],
        dealerIndex: 0,
        currentTurnIndex: 0,
        lastActionTime: timestamp
    };

    await db.collection('poker_tables').doc(tableId).set(newTable);

    return {
        success: true,
        tableId: tableId,
        message: 'Public table created successfully'
    };
});

export const createClubTableFunction = functions.https.onCall(async (data, context) => {
    // 1. Validate Authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const uid = context.auth.uid;
    const db = admin.firestore();

    // 2. Validate Club Ownership
    const { clubId, name, smallBlind, bigBlind, buyInMin, buyInMax } = data;

    if (!clubId || !name || !smallBlind || !bigBlind || !buyInMin || !buyInMax) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    const clubDoc = await db.collection('clubs').doc(clubId).get();
    if (!clubDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Club not found');
    }

    const clubData = clubDoc.data();
    if (clubData?.ownerId !== uid) {
        throw new functions.https.HttpsError('permission-denied', 'Only club owner can create tables');
    }

    // 3. Create Table
    const tableId = db.collection('poker_tables').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const newTable = {
        id: tableId,
        clubId: clubId, // Important: Link to club
        name: name,
        smallBlind: Number(smallBlind),
        bigBlind: Number(bigBlind),
        minBuyIn: Number(buyInMin),
        maxBuyIn: Number(buyInMax),
        hostId: uid, // Owner is host
        createdByClubId: clubId, // Redundant but useful for queries
        createdByName: clubData.name || 'Club',
        isPublic: true, // Club tables are public within the club context usually, or listed in club
        status: 'waiting', // Changed from 'active' to 'waiting'
        players: [],
        spectators: [],
        createdAt: timestamp,
        currentRound: null,
        pot: 0,
        communityCards: [],
        deck: [],
        dealerIndex: 0,
        currentTurnIndex: 0,
        lastActionTime: timestamp
    };

    await db.collection('poker_tables').doc(tableId).set(newTable);

    return {
        success: true,
        message: 'Club table created successfully'
    };
});

export const startGameFunction = functions.https.onCall(async (data, context) => {
    // 1. Validate Authentication
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'The function must be called while authenticated.'
        );
    }

    const uid = context.auth.uid;
    const db = admin.firestore();
    const { tableId } = data;

    if (!tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing tableId');
    }

    const tableRef = db.collection('poker_tables').doc(tableId);

    return db.runTransaction(async (transaction) => {
        const tableDoc = await transaction.get(tableRef);
        if (!tableDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Table not found');
        }

        const tableData = tableDoc.data();

        const players = tableData?.players || [];
        const readyPlayers = tableData?.readyPlayers || [];
        const isHost = tableData?.hostId === uid;
        const isPlayer = players.some((p: any) => p.id === uid);
        // Allow start if host OR if player and all players are ready (min 2 players)
        const allReady = players.length >= 2 && players.every((p: any) => readyPlayers.includes(p.id));

        if (!isHost && !(isPlayer && allReady)) {
            throw new functions.https.HttpsError('permission-denied', 'Only the host or a player (when all are ready) can start the game');
        }

        if (tableData?.status !== 'waiting') {
            throw new functions.https.HttpsError('failed-precondition', 'Table is not in waiting state');
        }

        transaction.update(tableRef, { status: 'active' });

        return { success: true, message: 'Game started' };
    });
});

// joinTable moved to gameEconomy.ts

// processCashOut moved to gameEconomy.ts

// closeTableAndCashOut removed/deprecated in favor of universalTableSettlement in gameEconomy.ts

// universalTableSettlement moved to gameEconomy.ts

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * GET IN-GAME BALANCE (Money In Play)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * Calcula el dinero en juego del usuario desde poker_sessions (fuente de verdad)
 * Suma el buyInAmount de todas las sesiones activas del usuario
 * 
 * @param data - Vacío (el UID se obtiene del contexto de autenticación)
 * @param context - Contexto de autenticación
 * @returns { moneyInPlay: number } - Dinero total en juego
 */
export const getInGameBalance = async (data: any, context: functions.https.CallableContext) => {
    // ════════════════════════════════════════════════════════════════════════
    // 1. VALIDACIÓN DE AUTENTICACIÓN
    // ════════════════════════════════════════════════════════════════════════
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'The function must be called while authenticated.'
        );
    }

    const uid = context.auth.uid;
    const db = getDb();

    try {
        console.log(`[GET_IN_GAME_BALANCE] 🔍 Calculando moneyInPlay para usuario ${uid}...`);

        // ════════════════════════════════════════════════════════════════════════
        // 2. BUSCAR SESIONES ACTIVAS DEL USUARIO
        // ════════════════════════════════════════════════════════════════════════
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('userId', '==', uid)
            .where('status', '==', 'active')
            .get();

        if (activeSessionsQuery.empty) {
            console.log(`[GET_IN_GAME_BALANCE] ✅ Usuario ${uid} no tiene sesiones activas. Retornando 0.`);
            return { moneyInPlay: 0 };
        }

        // ════════════════════════════════════════════════════════════════════════
        // 3. SUMAR BUY-IN DE TODAS LAS SESIONES ACTIVAS
        // ════════════════════════════════════════════════════════════════════════
        let totalMoneyInPlay = 0;
        const sessionDetails: Array<{ sessionId: string; buyInAmount: number; roomId: string }> = [];

        for (const doc of activeSessionsQuery.docs) {
            const sessionData = doc.data();
            const buyInAmount = Number(sessionData.buyInAmount) || 0;
            const roomId = sessionData.roomId || 'unknown';

            totalMoneyInPlay += buyInAmount;
            sessionDetails.push({
                sessionId: doc.id,
                buyInAmount,
                roomId
            });

            console.log(`[GET_IN_GAME_BALANCE] 📊 Sesión ${doc.id}: buyInAmount=${buyInAmount}, roomId=${roomId}`);
        }

        console.log(`[GET_IN_GAME_BALANCE] ✅ Total moneyInPlay calculado: ${totalMoneyInPlay} (${sessionDetails.length} sesión/es activa/s)`);

        return {
            moneyInPlay: totalMoneyInPlay,
            sessionCount: sessionDetails.length,
            sessions: sessionDetails // Opcional: para debugging
        };
    } catch (error: any) {
        console.error(`[GET_IN_GAME_BALANCE] ❌ Error calculando moneyInPlay para usuario ${uid}:`, error);
        throw new functions.https.HttpsError(
            'internal',
            `Failed to calculate in-game balance: ${error.message || 'Unknown error'}`
        );
    }
};

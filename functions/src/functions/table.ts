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

/**
 * Interface for closing table request
 */
interface CloseTableRequest {
    tableId: string;
}

/**
 * PROCESS CASH OUT - Función Maestra de Transferencia
 * 
 * Esta función se ejecuta cuando la mesa cierra y procesa TODOS los jugadores.
 * Garantiza la integridad de los datos mediante transacciones atómicas.
 * 
 * CORRECCIONES CRÍTICAS:
 * 1. Itera sobre TODOS los jugadores (no solo el current user)
 * 2. Maneja correctamente perdedores: calcula LossAmount, actualiza chips a 0, crea GAME_LOSS con amount negativo
 * 3. Acumula todo el rake y crea registro RAKE_COLLECTED en financial_ledger para el admin
 * 4. Asegura que todos los jugadores queden con chips: 0 e inGame: false
 * 
 * PASO A: Iteración sobre todos los jugadores
 * - Para cada jugador:
 *   * Si chips > 0: Calcula Rake, NetWinnings, actualiza créditos
 *   * Si chips == 0: Calcula LossAmount = buyInAmount, actualiza estado, crea GAME_LOSS
 * 
 * PASO B: Acumulación de Rake
 * - Suma todo el rake recolectado de todos los jugadores
 * - Distribuye según tipo de sala (Privada: 100% Platform, Pública: 50-30-20)
 * - Crea registro RAKE_COLLECTED en financial_ledger
 * 
 * PASO C: Actualización de Mesa
 * - Todos los jugadores quedan con chips: 0 e inGame: false
 * - Mesa queda en estado 'inactive'
 */
export const closeTableAndCashOut = async (data: CloseTableRequest, context: functions.https.CallableContext) => {
    // 1. Validación
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tableId } = data;
    if (!tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');
    }

    const db = getDb();
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const RAKE_PERCENTAGE = 0.08;

    try {
        // --- LECTURAS PRE-TRANSACCIÓN (para evitar queries dentro de la transacción) ---
        
        // 1. Leer Mesa
        const tableRef = db.collection('poker_tables').doc(tableId);
        const tableDoc = await tableRef.get();

        if (!tableDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Table not found.');
        }

        const tableData = tableDoc.data();
        const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];
        const isPublic = tableData?.isPublic === true;
        
        if (players.length === 0) {
            // Mesa vacía, solo cerrar
            await tableRef.update({ status: 'inactive' });
            return { success: true, message: 'Table closed (no players).' };
        }

        console.log(`[CASHOUT] Procesando cierre de mesa ${tableId} con ${players.length} jugadores`);

        // 2. Leer todas las sesiones activas de la mesa ANTES de la transacción
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();
        
        // Crear mapa de userId -> sessionData para acceso rápido
        const sessionMap = new Map<string, { ref: admin.firestore.DocumentReference, data: any }>();
        activeSessionsQuery.docs.forEach(doc => {
            const sessionData = doc.data();
            const userId = sessionData.userId;
            if (userId) {
                sessionMap.set(userId, { ref: doc.ref, data: sessionData });
            }
        });

        // 3. Leer todos los usuarios ANTES de la transacción
        const userIds = players.map((p: any) => p.id);
        const userDocs = await Promise.all(
            userIds.map(id => db.collection('users').doc(id).get())
        );
        const userMap = new Map<string, { ref: admin.firestore.DocumentReference, data: any }>();
        userDocs.forEach((doc, index) => {
            if (doc.exists) {
                userMap.set(userIds[index], { ref: doc.ref, data: doc.data() });
            }
        });

        // --- EJECUTAR TRANSACCIÓN ---
        const result = await db.runTransaction(async (transaction) => {
            // Variables para acumular rake total
            let totalRakeCollected = 0;
            let totalPlatformShare = 0;
            const clubRakeMap = new Map<string, number>(); // clubId -> amount
            const sellerRakeMap = new Map<string, number>(); // sellerId -> amount

            // --- ITERAR SOBRE TODOS LOS JUGADORES ---
            for (let i = 0; i < players.length; i++) {
                const player = players[i];
                const playerId = player.id;
                const playerChips = Number(player.chips) || 0;

                console.log(`[CASHOUT] Procesando jugador ${playerId} con ${playerChips} fichas`);

                // 1. Obtener datos del usuario (ya leídos antes)
                const userInfo = userMap.get(playerId);
                if (!userInfo) {
                    console.warn(`[CASHOUT] Usuario ${playerId} no encontrado, saltando...`);
                    continue;
                }

                const userRef = userInfo.ref;
                const userData = userInfo.data;
                const userClubId = userData?.clubId;
                const userSellerId = userData?.sellerId;
                const displayName = userData?.displayName || 'Unknown'; // CRÍTICO: Obtener displayName

                // 2. Obtener sesión activa (ya leída antes)
                const sessionInfo = sessionMap.get(playerId);
                let sessionRef: admin.firestore.DocumentReference | null = null;
                let buyInAmount = 0;
                
                if (sessionInfo) {
                    sessionRef = sessionInfo.ref;
                    buyInAmount = Number(sessionInfo.data.buyInAmount) || 0;
                }

                // 3. Procesar según chips del jugador
                if (playerChips === 0) {
                    // PERDEDOR: Perdió todas sus fichas
                    const lossAmount = buyInAmount; // Monto total perdido
                    
                    console.log(`[CASHOUT] Jugador ${playerId} PERDIÓ. Buy-in: ${buyInAmount}, Chips: ${playerChips}, Pérdida: -${lossAmount}`);

                    // CRÍTICO: Limpieza visual OBLIGATORIA para perdedores
                    // Esto debe pasar SIEMPRE, tenga o no tenga fichas
                    transaction.update(userRef, {
                        moneyInPlay: 0,  // Establecer explícitamente a 0 (no delete)
                        currentTableId: null,  // Establecer explícitamente a null (no delete)
                        lastUpdated: timestamp
                    });

                    // Cerrar sesión
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: 0,
                            totalRakePaid: 0,
                            netResult: 0,
                            endTime: timestamp
                        });
                    }

                    // Crear registro GAME_LOSS con amount negativo (FIX del -0)
                    const lossLedgerRef = db.collection('financial_ledger').doc();
                    transaction.set(lossLedgerRef, {
                        type: 'GAME_LOSS',
                        userId: playerId,
                        userName: displayName, // CRÍTICO: Guardar displayName
                        tableId: tableId,
                        amount: -lossAmount, // FIX: Monto negativo de la pérdida
                        netAmount: -lossAmount,
                        netProfit: -lossAmount, // Pérdida total vs buy-in
                        grossAmount: playerChips,
                        rakePaid: 0,
                        buyInAmount: buyInAmount,
                        timestamp: timestamp,
                        description: `Cierre de Mesa ${tableId}. Pérdida Total: -${lossAmount} (Buy-in: ${buyInAmount}, Chips restantes: ${playerChips}) - Usuario: ${displayName}`
                    });

                    // Actualizar jugador en la mesa: chips a 0
                    players[i] = { ...player, chips: 0, inGame: false };

                } else {
                    // GANADOR O EMPATE: Tiene fichas, calcular rake y netWinnings
                    const totalRake = Math.floor(playerChips * RAKE_PERCENTAGE);
                    const netWinnings = playerChips - totalRake;
                    totalRakeCollected += totalRake;

                    console.log(`[CASHOUT] Jugador ${playerId} GANÓ. Chips: ${playerChips}, Rake: ${totalRake}, Net: ${netWinnings}`);

                    // Determinar distribución de Rake según tipo de sala
                    let platformShare = 0;
                    let clubShare = 0;
                    let sellerShare = 0;

                    if (!isPublic) {
                        // Mesa Privada: 100% Platform
                        platformShare = totalRake;
                    } else {
                        // Mesa Pública: Split 50-30-20
                        platformShare = Math.floor(totalRake * 0.50);
                        clubShare = Math.floor(totalRake * 0.30);
                        sellerShare = Math.floor(totalRake * 0.20);
                        
                        // Ajustar remainder a platform
                        const remainder = totalRake - (platformShare + clubShare + sellerShare);
                        platformShare += remainder;
                    }

                    // Acumular shares
                    totalPlatformShare += platformShare;
                    
                    if (clubShare > 0) {
                        if (userClubId) {
                            const current = clubRakeMap.get(userClubId) || 0;
                            clubRakeMap.set(userClubId, current + clubShare);
                        } else {
                            // Fallback a Platform
                            totalPlatformShare += clubShare;
                        }
                    }

                    if (sellerShare > 0) {
                        if (userSellerId) {
                            const current = sellerRakeMap.get(userSellerId) || 0;
                            sellerRakeMap.set(userSellerId, current + sellerShare);
                        } else if (userClubId) {
                            // Fallback a Club
                            const current = clubRakeMap.get(userClubId) || 0;
                            clubRakeMap.set(userClubId, current + sellerShare);
                        } else {
                            // Fallback a Platform
                            totalPlatformShare += sellerShare;
                        }
                    }

                    // CRÍTICO: Limpieza visual OBLIGATORIA antes de actualizar crédito
                    // Esto debe pasar SIEMPRE, tenga o no tenga fichas
                    transaction.update(userRef, {
                        moneyInPlay: 0,  // Establecer explícitamente a 0 (no delete)
                        currentTableId: null,  // Establecer explícitamente a null (no delete)
                        credit: admin.firestore.FieldValue.increment(netWinnings),
                        lastUpdated: timestamp
                    });

                    // Cerrar sesión
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: playerChips,
                            totalRakePaid: totalRake,
                            netResult: netWinnings,
                            endTime: timestamp
                        });
                    }

                    // Determinar tipo de transacción según resultado
                    const netProfit = netWinnings - buyInAmount;
                    const ledgerType = netWinnings > buyInAmount ? 'GAME_WIN' : 'GAME_LOSS';

                    // Crear entrada en financial_ledger
                    const winLedgerRef = db.collection('financial_ledger').doc();
                    transaction.set(winLedgerRef, {
                        type: ledgerType,
                        userId: playerId,
                        userName: displayName, // CRÍTICO: Guardar displayName
                        tableId: tableId,
                        amount: netWinnings,
                        netAmount: netWinnings,
                        netProfit: netProfit,
                        grossAmount: playerChips,
                        rakePaid: totalRake,
                        buyInAmount: buyInAmount,
                        timestamp: timestamp,
                        description: `Cierre de Mesa ${tableId}. ${ledgerType === 'GAME_WIN' ? 'Ganancia' : 'Pérdida'} Neta: ${netProfit > 0 ? '+' : ''}${netProfit} (Recibido: ${netWinnings}, Rake: ${totalRake}) - Usuario: ${displayName}`
                    });

                    // Actualizar jugador en la mesa: chips a 0
                    players[i] = { ...player, chips: 0, inGame: false };
                }
            }

            // --- DISTRIBUIR RAKE ACUMULADO ---
            if (totalRakeCollected > 0) {
                console.log(`[CASHOUT] Rake total recolectado: ${totalRakeCollected}`);

                // Platform Share
                if (totalPlatformShare > 0) {
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(totalPlatformShare),
                        lastUpdated: timestamp
                    }, { merge: true });
                    console.log(`[CASHOUT] Platform share: ${totalPlatformShare}`);
                }

                // Club Shares
                for (const [clubId, amount] of clubRakeMap.entries()) {
                    if (amount > 0) {
                        transaction.update(db.collection('clubs').doc(clubId), {
                            walletBalance: admin.firestore.FieldValue.increment(amount)
                        });
                        console.log(`[CASHOUT] Club ${clubId} share: ${amount}`);
                    }
                }

                // Seller Shares
                for (const [sellerId, amount] of sellerRakeMap.entries()) {
                    if (amount > 0) {
                        transaction.update(db.collection('users').doc(sellerId), {
                            credit: admin.firestore.FieldValue.increment(amount)
                        });
                        console.log(`[CASHOUT] Seller ${sellerId} share: ${amount}`);
                    }
                }

                // FIX CRÍTICO: Crear registro RAKE_COLLECTED en financial_ledger para el admin
                const rakeLedgerRef = db.collection('financial_ledger').doc();
                transaction.set(rakeLedgerRef, {
                    type: 'RAKE_COLLECTED',
                    userId: null, // Registro del sistema
                    tableId: tableId,
                    amount: totalRakeCollected,
                    platformShare: totalPlatformShare,
                    clubShares: Object.fromEntries(clubRakeMap),
                    sellerShares: Object.fromEntries(sellerRakeMap),
                    timestamp: timestamp,
                    description: `Rake recolectado del cierre de Mesa ${tableId}. Total: ${totalRakeCollected} (Platform: ${totalPlatformShare}, Clubs: ${Array.from(clubRakeMap.values()).reduce((a, b) => a + b, 0)}, Sellers: ${Array.from(sellerRakeMap.values()).reduce((a, b) => a + b, 0)})`
                });
                console.log(`[CASHOUT] Registro RAKE_COLLECTED creado: ${rakeLedgerRef.id}`);
            }

            // --- ACTUALIZAR MESA: Todos los jugadores con chips: 0 e inGame: false ---
            const tableUpdate: any = {
                players: players.map((p: any) => ({ ...p, chips: 0, inGame: false })),
                status: 'inactive'
            };
            transaction.update(tableRef, tableUpdate);

            console.log(`[CASHOUT] Mesa ${tableId} cerrada. Todos los jugadores procesados.`);

            return {
                success: true,
                playersProcessed: players.length,
                totalRakeCollected: totalRakeCollected,
                message: `Table closed. ${players.length} players processed.`
            };
        });

        return result;

    } catch (error: any) {
        console.error('Error en closeTableAndCashOut:', error);
        
        // Si es un error de Firestore conocido, propagarlo
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        
        throw new functions.https.HttpsError('internal', `Failed to close table and cash out: ${error.message || 'Unknown error'}`);
    }
};

/**
 * UNIVERSAL TABLE SETTLEMENT - Liquidación Universal a Prueba de Balas
 * 
 * Esta función garantiza que TODOS los jugadores sean procesados correctamente
 * sin importar el motivo del cierre de mesa. Es la función definitiva para
 * liquidar mesas de forma segura y completa.
 * 
 * CARACTERÍSTICAS CRÍTICAS:
 * - Itera sobre TODOS los jugadores sin asumir nada
 * - Limpia OBLIGATORIAMENTE moneyInPlay y currentTableId para CADA jugador
 * - Calcula correctamente rake y payout
 * - Registra en ledger de forma consistente
 * - Cierra la mesa solo después de procesar todos
 * 
 * @param tableId - ID de la mesa a liquidar
 * @param context - Contexto de autenticación
 * @returns Resumen de liquidación
 */
export const universalTableSettlement = async (data: CloseTableRequest, context: functions.https.CallableContext) => {
    // 1. Validación
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { tableId } = data;
    if (!tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');
    }

    const db = getDb();
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const RAKE_PERCENTAGE = 0.08; // 8% rake

    try {
        console.log(`[UNIVERSAL_SETTLEMENT] Iniciando liquidación universal de mesa ${tableId}`);

        // --- LECTURAS PRE-TRANSACCIÓN ---
        const tableRef = db.collection('poker_tables').doc(tableId);
        const tableDoc = await tableRef.get();

        if (!tableDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Table not found.');
        }

        const tableData = tableDoc.data();
        const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];
        const isPublic = tableData?.isPublic === true;

        if (players.length === 0) {
            // Mesa vacía, solo cerrar
            await tableRef.update({ 
                status: 'FINISHED'
            });
            return { success: true, message: 'Table closed (no players).', playersProcessed: 0 };
        }

        console.log(`[UNIVERSAL_SETTLEMENT] Procesando ${players.length} jugadores`);

        // Leer todas las sesiones activas ANTES de la transacción
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();

        const sessionMap = new Map<string, { ref: admin.firestore.DocumentReference, data: any }>();
        activeSessionsQuery.docs.forEach(doc => {
            const data = doc.data();
            if (data.userId) {
                sessionMap.set(data.userId, { ref: doc.ref, data: data });
            }
        });

        // Leer todos los usuarios ANTES de la transacción
        const userIds = players.map(p => p.id).filter(Boolean);
        const userMap = new Map<string, { ref: admin.firestore.DocumentReference, data: any }>();
        
        if (userIds.length > 0) {
            const userDocs = await Promise.all(
                userIds.map(uid => db.collection('users').doc(uid).get())
            );
            userDocs.forEach((doc, index) => {
                if (doc.exists) {
                    userMap.set(userIds[index], { ref: doc.ref, data: doc.data() });
                }
            });
        }

        // --- EJECUTAR TRANSACCIÓN ATÓMICA ---
        const result = await db.runTransaction(async (transaction) => {
            // Variables para acumular rake
            let totalRakeCollected = 0;
            let totalPlatformShare = 0;
            const clubRakeMap = new Map<string, number>();
            const sellerRakeMap = new Map<string, number>();

            const processedPlayers: Array<{
                userId: string;
                displayName: string;
                finalStack: number;
                initialBuyIn: number;
                netResult: number;
                payout: number;
                rake: number;
                type: 'GAME_WIN' | 'GAME_LOSS';
            }> = [];

            // --- ITERACIÓN OBLIGATORIA SOBRE TODOS LOS JUGADORES ---
            for (let i = 0; i < players.length; i++) {
                const player = players[i];
                const playerId = player.id;
                const finalStack = Number(player.chips) || 0;

                console.log(`[UNIVERSAL_SETTLEMENT] Procesando jugador ${playerId} con ${finalStack} fichas`);

                // Obtener datos del usuario
                const userInfo = userMap.get(playerId);
                if (!userInfo) {
                    console.warn(`[UNIVERSAL_SETTLEMENT] Usuario ${playerId} no encontrado, saltando...`);
                    continue;
                }

                const userRef = userInfo.ref;
                const userData = userInfo.data;
                const displayName = userData?.displayName || 'Unknown';
                const userClubId = userData?.clubId;
                const userSellerId = userData?.sellerId;

                // Obtener sesión activa
                const sessionInfo = sessionMap.get(playerId);
                let sessionRef: admin.firestore.DocumentReference | null = null;
                let initialBuyIn = 0;

                if (sessionInfo) {
                    sessionRef = sessionInfo.ref;
                    initialBuyIn = Number(sessionInfo.data.buyInAmount) || 0;
                } else {
                    // Si no hay sesión, usar el buy-in de la mesa como fallback
                    initialBuyIn = Number(tableData?.minBuyIn) || 1000;
                    console.warn(`[UNIVERSAL_SETTLEMENT] No se encontró sesión para ${playerId}, usando minBuyIn: ${initialBuyIn}`);
                }

                // PASO A: LIMPIEZA VISUAL OBLIGATORIA (CRÍTICO)
                // Esto DEBE pasar para TODOS los jugadores, sin excepción
                transaction.update(userRef, {
                    moneyInPlay: 0,  // Establecer explícitamente a 0
                    currentTableId: null,  // Establecer explícitamente a null
                    lastUpdated: timestamp
                });
                console.log(`[UNIVERSAL_SETTLEMENT] Limpieza visual aplicada a ${playerId}`);

                // PASO B: Cálculo Financiero
                const netResult = finalStack - initialBuyIn;

                // PASO C: Rake y Transferencia
                if (netResult > 0) {
                    // GANADOR: NetResult > 0
                    const rake = Math.floor(finalStack * RAKE_PERCENTAGE);
                    const payout = finalStack - rake;
                    totalRakeCollected += rake;

                    console.log(`[UNIVERSAL_SETTLEMENT] ${playerId} GANÓ. FinalStack: ${finalStack}, BuyIn: ${initialBuyIn}, Rake: ${rake}, Payout: ${payout}`);

                    // Actualizar crédito del usuario
                    transaction.update(userRef, {
                        credit: admin.firestore.FieldValue.increment(payout)
                    });

                    // Determinar distribución de rake
                    let platformShare = 0;
                    let clubShare = 0;
                    let sellerShare = 0;

                    if (!isPublic) {
                        platformShare = rake;
                    } else {
                        platformShare = Math.floor(rake * 0.50);
                        clubShare = Math.floor(rake * 0.30);
                        sellerShare = Math.floor(rake * 0.20);
                        const remainder = rake - (platformShare + clubShare + sellerShare);
                        platformShare += remainder;
                    }

                    totalPlatformShare += platformShare;

                    if (clubShare > 0 && userClubId) {
                        const current = clubRakeMap.get(userClubId) || 0;
                        clubRakeMap.set(userClubId, current + clubShare);
                    } else if (clubShare > 0) {
                        totalPlatformShare += clubShare;
                    }

                    if (sellerShare > 0 && userSellerId) {
                        const current = sellerRakeMap.get(userSellerId) || 0;
                        sellerRakeMap.set(userSellerId, current + sellerShare);
                    } else if (sellerShare > 0 && userClubId) {
                        const current = clubRakeMap.get(userClubId) || 0;
                        clubRakeMap.set(userClubId, current + sellerShare);
                    } else if (sellerShare > 0) {
                        totalPlatformShare += sellerShare;
                    }

                    // Cerrar sesión
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: finalStack,
                            totalRakePaid: rake,
                            netResult: payout,
                            endTime: timestamp
                        });
                    }

                    // Registrar en ledger
                    const ledgerRef = db.collection('financial_ledger').doc();
                    transaction.set(ledgerRef, {
                        type: 'GAME_WIN',
                        userId: playerId,
                        userName: displayName,
                        tableId: tableId,
                        amount: payout,
                        netAmount: payout,
                        netProfit: netResult,
                        grossAmount: finalStack,
                        rakePaid: rake,
                        buyInAmount: initialBuyIn,
                        timestamp: timestamp,
                        description: `Liquidación Universal - Mesa ${tableId}. Ganancia: +${netResult} (FinalStack: ${finalStack}, BuyIn: ${initialBuyIn}, Rake: ${rake}, Payout: ${payout}) - Usuario: ${displayName}`
                    });

                    processedPlayers.push({
                        userId: playerId,
                        displayName,
                        finalStack,
                        initialBuyIn,
                        netResult,
                        payout,
                        rake,
                        type: 'GAME_WIN'
                    });

                } else {
                    // PERDEDOR O EMPATE: NetResult <= 0
                    const lossAmount = initialBuyIn - finalStack; // Pérdida neta

                    console.log(`[UNIVERSAL_SETTLEMENT] ${playerId} PERDIÓ. FinalStack: ${finalStack}, BuyIn: ${initialBuyIn}, Pérdida: -${lossAmount}`);

                    // Si le quedaron fichas (se retiró con la mitad), devolverlas
                    if (finalStack > 0) {
                        transaction.update(userRef, {
                            credit: admin.firestore.FieldValue.increment(finalStack)
                        });
                        console.log(`[UNIVERSAL_SETTLEMENT] ${playerId} recibió ${finalStack} créditos restantes`);
                    }

                    // Cerrar sesión
                    if (sessionRef) {
                        transaction.update(sessionRef, {
                            status: 'completed',
                            currentChips: finalStack,
                            totalRakePaid: 0,
                            netResult: finalStack,
                            endTime: timestamp
                        });
                    }

                    // Registrar en ledger
                    const ledgerRef = db.collection('financial_ledger').doc();
                    transaction.set(ledgerRef, {
                        type: 'GAME_LOSS',
                        userId: playerId,
                        userName: displayName,
                        tableId: tableId,
                        amount: -lossAmount, // Monto negativo de la pérdida
                        netAmount: finalStack, // Lo que recibió (puede ser 0)
                        netProfit: -lossAmount, // Pérdida total
                        grossAmount: finalStack,
                        rakePaid: 0,
                        buyInAmount: initialBuyIn,
                        timestamp: timestamp,
                        description: `Liquidación Universal - Mesa ${tableId}. Pérdida: -${lossAmount} (FinalStack: ${finalStack}, BuyIn: ${initialBuyIn}) - Usuario: ${displayName}`
                    });

                    processedPlayers.push({
                        userId: playerId,
                        displayName,
                        finalStack,
                        initialBuyIn,
                        netResult: -lossAmount,
                        payout: finalStack,
                        rake: 0,
                        type: 'GAME_LOSS'
                    });
                }

                // Actualizar jugador en la mesa: chips a 0
                players[i] = { ...player, chips: 0, inGame: false };
            }

            // --- DISTRIBUIR RAKE ACUMULADO ---
            if (totalRakeCollected > 0) {
                console.log(`[UNIVERSAL_SETTLEMENT] Rake total recolectado: ${totalRakeCollected}`);

                // Platform Share
                if (totalPlatformShare > 0) {
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(totalPlatformShare),
                        lastUpdated: timestamp
                    }, { merge: true });
                }

                // Club Shares
                for (const [clubId, amount] of clubRakeMap.entries()) {
                    if (amount > 0) {
                        transaction.update(db.collection('clubs').doc(clubId), {
                            walletBalance: admin.firestore.FieldValue.increment(amount)
                        });
                    }
                }

                // Seller Shares
                for (const [sellerId, amount] of sellerRakeMap.entries()) {
                    if (amount > 0) {
                        transaction.update(db.collection('users').doc(sellerId), {
                            credit: admin.firestore.FieldValue.increment(amount)
                        });
                    }
                }

                // Registrar rake en ledger
                const rakeLedgerRef = db.collection('financial_ledger').doc();
                transaction.set(rakeLedgerRef, {
                    type: 'RAKE_COLLECTED',
                    userId: null,
                    tableId: tableId,
                    amount: totalRakeCollected,
                    platformShare: totalPlatformShare,
                    clubShares: Object.fromEntries(clubRakeMap),
                    sellerShares: Object.fromEntries(sellerRakeMap),
                    timestamp: timestamp,
                    description: `Rake recolectado del cierre de Mesa ${tableId}. Total: ${totalRakeCollected}`
                });
            }

            // --- CERRAR MESA (Solo después de procesar TODOS) ---
            transaction.update(tableRef, {
                players: players.map((p: any) => ({ ...p, chips: 0, inGame: false })),
                status: 'FINISHED',
                lastUpdated: timestamp
            });

            console.log(`[UNIVERSAL_SETTLEMENT] Mesa ${tableId} cerrada. ${processedPlayers.length} jugadores procesados.`);

            return {
                success: true,
                playersProcessed: processedPlayers.length,
                totalRakeCollected: totalRakeCollected,
                players: processedPlayers,
                message: `Universal settlement completed. ${processedPlayers.length} players processed.`
            };
        });

        return result;

    } catch (error: any) {
        console.error('[UNIVERSAL_SETTLEMENT] Error en liquidación universal:', error);
        
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        
        throw new functions.https.HttpsError('internal', `Failed to perform universal settlement: ${error.message || 'Unknown error'}`);
    }
};

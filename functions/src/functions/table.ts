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
 * ALGORITMO MAESTRO DE LIQUIDACIÓN - Implementación Definitiva
 * 
 * Esta función implementa el algoritmo único de verdad para liquidar mesas de poker.
 * Garantiza integridad financiera mediante transacciones atómicas.
 * 
 * ALGORITMO (Implementado al pie de la letra):
 * 
 * Paso 1: Cálculo del Stack Final (Fuente de Verdad)
 * - Obtén PlayerChips (las fichas que el usuario tiene físicamente frente a él)
 * - Regla de Oro: NUNCA recalcules ganancias sumando botes pasados
 * 
 * Paso 2: Cálculo del Rake (Solo si es Cash Game Público)
 * - Si PlayerChips > BuyIn:
 *   * GrossProfit = PlayerChips - BuyIn
 *   * RakeAmount = GrossProfit * 0.08 (8%)
 *   * NetPayout = PlayerChips - RakeAmount
 *   * DESTINO DEL RAKE: RakeAmount se suma a system_stats/economy (accumulatedRake)
 * - Si PlayerChips <= BuyIn:
 *   * RakeAmount = 0
 *   * NetPayout = PlayerChips
 * 
 * Paso 3: Ejecución de Transacción (Atomic Batch)
 * - Usuario: credit += NetPayout, moneyInPlay = 0, currentTableId = null
 * - Plataforma: accumulatedRake += RakeAmount
 * - Estadísticas Diarias: dailyVolume += NetPayout, dailyGGR += RakeAmount
 * - Ledger: UN SOLO documento con amount = NetPayout, type = GAME_WIN/LOSS
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
    const RAKE_PERCENTAGE = 0.08; // 8%

    try {
        // --- LECTURAS PRE-TRANSACCIÓN ---

        // 1. Leer Mesa
        const tableRef = db.collection('poker_tables').doc(tableId);
        const tableDoc = await tableRef.get();

        if (!tableDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Table not found.');
        }

        const tableData = tableDoc.data();
        const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];
        const isPublic = tableData?.isPublic === true;
        const currentStatus = tableData?.status;

        // CRÍTICO: Verificar si la mesa ya fue procesada para evitar doble liquidación
        if (currentStatus === 'inactive' || currentStatus === 'FINISHED') {
            console.log(`[LIQUIDACION] Mesa ${tableId} ya fue procesada (status: ${currentStatus}). Saltando...`);
            return {
                success: true,
                message: 'Table already processed.',
                alreadyProcessed: true
            };
        }

        if (players.length === 0) {
            // Mesa vacía, solo cerrar
            await tableRef.update({ status: 'inactive' });
            return { success: true, message: 'Table closed (no players).' };
        }

        console.log(`[LIQUIDACION] Procesando cierre de mesa ${tableId} con ${players.length} jugadores (Pública: ${isPublic})`);

        // 2. Leer TODAS las sesiones activas ANTES de la transacción
        // CRÍTICO: Mapeo de TODAS las sesiones por usuario (array en lugar de single)
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();

        const sessionsByUser = new Map<string, Array<{ ref: admin.firestore.DocumentReference, data: any }>>();
        activeSessionsQuery.docs.forEach(doc => {
            const sessionData = doc.data();
            const userId = sessionData.userId;
            if (userId) {
                const existing = sessionsByUser.get(userId) || [];
                existing.push({ ref: doc.ref, data: sessionData });
                sessionsByUser.set(userId, existing);
            }
        });

        // CRÍTICO: Si hay duplicados, loguear warning
        for (const [userId, sessions] of sessionsByUser.entries()) {
            if (sessions.length > 1) {
                console.warn(`[LIQUIDACION] ⚠️ DUPLICADOS DETECTADOS: Usuario ${userId} tiene ${sessions.length} sesiones activas. Cerrando TODAS.`);
            }
        }

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

        // 4. Preparar referencia de estadísticas diarias
        const now = new Date();
        const dateKey = now.toISOString().split('T')[0]; // YYYY-MM-DD
        const dailyStatsRef = db.collection('stats_daily').doc(dateKey);

        // --- EJECUTAR TRANSACCIÓN ATÓMICA ÚNICA ---
        const result = await db.runTransaction(async (transaction) => {
            // Variables para acumular totales
            let totalRakeAmount = 0;
            let totalDailyVolume = 0;
            let totalDailyGGR = 0;

            // --- ITERAR SOBRE TODOS LOS JUGADORES ---
            for (let i = 0; i < players.length; i++) {
                const player = players[i];
                const playerId = player.id;

                // PASO 1: Obtener PlayerChips (Fuente de Verdad - LA MESA, no la sesión)
                const playerChips = Number(player.chips) || 0;

                console.log(`[LIQUIDACION] Jugador ${playerId}: PlayerChips = ${playerChips}`);

                // Obtener datos del usuario
                const userInfo = userMap.get(playerId);
                if (!userInfo) {
                    console.warn(`[LIQUIDACION] Usuario ${playerId} no encontrado, saltando...`);
                    continue;
                }

                const userRef = userInfo.ref;
                const userData = userInfo.data;
                const displayName = userData?.displayName || 'Unknown';

                // Obtener TODAS las sesiones activas para este usuario
                const sessions = sessionsByUser.get(playerId) || [];

                // Usar la sesión más reciente para obtener el buyIn (o fallback a minBuyIn)
                let buyInAmount = 0;
                if (sessions.length > 0) {
                    // Ordenar por startTime descendente y usar la más reciente
                    const sortedSessions = sessions.sort((a, b) =>
                        (b.data.startTime?.toMillis() || 0) - (a.data.startTime?.toMillis() || 0)
                    );
                    buyInAmount = Number(sortedSessions[0].data.buyInAmount) || 0;
                } else {
                    // Fallback: usar minBuyIn de la mesa
                    buyInAmount = Number(tableData?.minBuyIn) || 0;
                    console.warn(`[LIQUIDACION] No se encontró sesión para ${playerId}, usando minBuyIn: ${buyInAmount}`);
                }

                // PASO 2: Cálculo del Rake (Solo si es Cash Game Público)
                let rakeAmount = 0;
                let netPayout = 0;
                let ledgerType: 'GAME_WIN' | 'GAME_LOSS' = 'GAME_LOSS';

                if (isPublic && playerChips > buyInAmount) {
                    // Cash Game Público con ganancia: aplicar rake
                    const grossProfit = playerChips - buyInAmount;
                    rakeAmount = Math.floor(grossProfit * RAKE_PERCENTAGE);
                    netPayout = playerChips - rakeAmount;
                    ledgerType = 'GAME_WIN';

                    console.log(`[LIQUIDACION] ${playerId} GANÓ (Público). BuyIn: ${buyInAmount}, PlayerChips: ${playerChips}, GrossProfit: ${grossProfit}, Rake: ${rakeAmount}, NetPayout: ${netPayout}`);
                } else {
                    // Sin rake: PlayerChips <= BuyIn o mesa privada
                    rakeAmount = 0;
                    netPayout = playerChips;
                    ledgerType = playerChips > buyInAmount ? 'GAME_WIN' : (playerChips < buyInAmount ? 'GAME_LOSS' : 'GAME_LOSS');

                    console.log(`[LIQUIDACION] ${playerId} ${playerChips > buyInAmount ? 'GANÓ' : 'PERDIÓ'} (Sin Rake). BuyIn: ${buyInAmount}, PlayerChips: ${playerChips}, NetPayout: ${netPayout}`);
                }

                // Acumular para estadísticas
                totalRakeAmount += rakeAmount;
                totalDailyVolume += netPayout;
                totalDailyGGR += rakeAmount;

                // PASO 3: Ejecución de Transacción (Atomic Batch)

                // 3.1. Usuario: Actualizar crédito, limpiar estado
                transaction.update(userRef, {
                    credit: admin.firestore.FieldValue.increment(netPayout),
                    moneyInPlay: 0,
                    currentTableId: null,
                    lastUpdated: timestamp
                });

                // 3.2. CRÍTICO: Cerrar TODAS las sesiones del usuario (incluye duplicados)
                for (let j = 0; j < sessions.length; j++) {
                    const session = sessions[j];
                    const isPrimary = j === 0; // La primera (más reciente) es la primaria

                    transaction.update(session.ref, {
                        status: 'completed',
                        currentChips: isPrimary ? playerChips : 0,
                        totalRakePaid: isPrimary ? rakeAmount : 0,
                        netResult: isPrimary ? netPayout : 0,
                        endTime: timestamp,
                        closedReason: isPrimary ? 'primary_cashout' : 'duplicate_cleanup'
                    });

                    if (!isPrimary) {
                        console.log(`[LIQUIDACION] Sesión duplicada ${session.ref.id} cerrada como 'duplicate_cleanup'`);
                    }
                }

                // 3.3. Ledger: UN SOLO documento por jugador (ignora duplicados)
                const ledgerRef = db.collection('financial_ledger').doc();
                const netProfit = netPayout - buyInAmount;
                transaction.set(ledgerRef, {
                    type: ledgerType,
                    userId: playerId,
                    userName: displayName,
                    tableId: tableId,
                    amount: netPayout,
                    netAmount: netPayout,
                    netProfit: netProfit,
                    grossAmount: playerChips,
                    rakePaid: rakeAmount,
                    buyInAmount: buyInAmount,
                    timestamp: timestamp,
                    description: `Cashout Final (Stack: ${playerChips} - Rake: ${rakeAmount})`,
                    duplicateSessionsClosed: sessions.length > 1 ? sessions.length : undefined
                });

                // Actualizar jugador en la mesa: chips a 0
                players[i] = { ...player, chips: 0, inGame: false };
            }

            // 3.4. Plataforma: Actualizar accumulatedRake
            if (totalRakeAmount > 0) {
                transaction.set(db.collection('system_stats').doc('economy'), {
                    accumulated_rake: admin.firestore.FieldValue.increment(totalRakeAmount),
                    lastUpdated: timestamp
                }, { merge: true });
                console.log(`[LIQUIDACION] Rake total enviado a plataforma: ${totalRakeAmount}`);
            }

            // 3.5. Estadísticas Diarias: Actualizar dailyVolume y dailyGGR
            transaction.set(dailyStatsRef, {
                dateKey: dateKey,
                date: admin.firestore.Timestamp.now(),
                totalVolume: admin.firestore.FieldValue.increment(totalDailyVolume),
                dailyGGR: admin.firestore.FieldValue.increment(totalDailyGGR),
                totalRake: admin.firestore.FieldValue.increment(totalDailyGGR),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            console.log(`[LIQUIDACION] Estadísticas diarias actualizadas: Volume: +${totalDailyVolume}, GGR: +${totalDailyGGR}`);

            // 3.6. Actualizar Mesa: Todos los jugadores con chips: 0
            transaction.update(tableRef, {
                players: players.map((p: any) => ({ ...p, chips: 0, inGame: false })),
                status: 'inactive',
                lastUpdated: timestamp
            });

            console.log(`[LIQUIDACION] Mesa ${tableId} cerrada. ${players.length} jugadores procesados.`);

            return {
                success: true,
                playersProcessed: players.length,
                totalRakeCollected: totalRakeAmount,
                totalDailyVolume: totalDailyVolume,
                totalDailyGGR: totalDailyGGR,
                message: `Table closed. ${players.length} players processed.`
            };
        });

        return result;

    } catch (error: any) {
        console.error('[LIQUIDACION] Error en closeTableAndCashOut:', error);

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

        // Leer TODAS las sesiones activas ANTES de la transacción
        // CRÍTICO: Mapeo de TODAS las sesiones por usuario (array en lugar de single)
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();

        const sessionsByUser = new Map<string, Array<{ ref: admin.firestore.DocumentReference, data: any }>>();
        activeSessionsQuery.docs.forEach(doc => {
            const sessionData = doc.data();
            if (sessionData.userId) {
                const existing = sessionsByUser.get(sessionData.userId) || [];
                existing.push({ ref: doc.ref, data: sessionData });
                sessionsByUser.set(sessionData.userId, existing);
            }
        });

        // CRÍTICO: Si hay duplicados, loguear warning
        for (const [userId, sessions] of sessionsByUser.entries()) {
            if (sessions.length > 1) {
                console.warn(`[UNIVERSAL_SETTLEMENT] ⚠️ DUPLICADOS DETECTADOS: Usuario ${userId} tiene ${sessions.length} sesiones activas. Cerrando TODAS.`);
            }
        }

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

                // Obtener TODAS las sesiones activas para este usuario
                const sessions = sessionsByUser.get(playerId) || [];

                // Usar la sesión más reciente para obtener el buyIn (o fallback a minBuyIn)
                let initialBuyIn = 0;
                if (sessions.length > 0) {
                    // Ordenar por startTime descendente y usar la más reciente
                    sessions.sort((a, b) =>
                        (b.data.startTime?.toMillis() || 0) - (a.data.startTime?.toMillis() || 0)
                    );
                    initialBuyIn = Number(sessions[0].data.buyInAmount) || 0;
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
                    // FÓRMULA CORRECTA: rake = 8% de GANANCIA NETA, NO del stack total
                    const rake = Math.floor(netResult * RAKE_PERCENTAGE); // Rake sobre ganancia
                    const payout = finalStack - rake; // Stack total menos rake
                    totalRakeCollected += rake;

                    console.log(`[UNIVERSAL_SETTLEMENT] ${playerId} GANÓ. BuyIn: ${initialBuyIn}, FinalStack: ${finalStack}, NetProfit: ${netResult}, Rake: ${rake}, Payout: ${payout}`);

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

                    // CRÍTICO: Cerrar TODAS las sesiones del usuario (incluye duplicados)
                    for (let j = 0; j < sessions.length; j++) {
                        const session = sessions[j];
                        const isPrimary = j === 0;

                        transaction.update(session.ref, {
                            status: 'completed',
                            currentChips: isPrimary ? finalStack : 0,
                            totalRakePaid: isPrimary ? rake : 0,
                            netResult: isPrimary ? payout : 0,
                            endTime: timestamp,
                            closedReason: isPrimary ? 'primary_cashout' : 'duplicate_cleanup'
                        });

                        if (!isPrimary) {
                            console.log(`[UNIVERSAL_SETTLEMENT] Sesión duplicada ${session.ref.id} cerrada como 'duplicate_cleanup'`);
                        }
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

                    // CRÍTICO: Cerrar TODAS las sesiones del usuario (incluye duplicados)
                    for (let j = 0; j < sessions.length; j++) {
                        const session = sessions[j];
                        const isPrimary = j === 0;

                        transaction.update(session.ref, {
                            status: 'completed',
                            currentChips: isPrimary ? finalStack : 0,
                            totalRakePaid: 0,
                            netResult: isPrimary ? finalStack : 0,
                            endTime: timestamp,
                            closedReason: isPrimary ? 'primary_cashout' : 'duplicate_cleanup'
                        });

                        if (!isPrimary) {
                            console.log(`[UNIVERSAL_SETTLEMENT] Sesión duplicada ${session.ref.id} cerrada como 'duplicate_cleanup'`);
                        }
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

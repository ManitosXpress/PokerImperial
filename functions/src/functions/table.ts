import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

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
 * Esta función se ejecuta cuando un jugador sale o la mesa cierra.
 * Garantiza la integridad de los datos mediante transacciones atómicas.
 * 
 * PASO A: Cálculo
 * - Lee player.chips (Fichas en mesa)
 * - Si es > 0: Calcula Rake según tipo de sala
 *   * Privada: 100% Platform
 *   * Pública: Split 50-30-20 (Platform-Club-Seller)
 * - NetWinnings = player.chips - CalculatedRake
 * 
 * PASO B: Transacción Atómica (OBLIGATORIO)
 * - User Update: credit = FieldValue.increment(NetWinnings)
 * - Clean Up: Cierra sesión en poker_sessions (status: 'completed')
 *   Esto elimina el indicador visual de "+X en mesa"
 * - Table Update: Pone el stack del jugador en 0
 * 
 * PASO C: Generación de Historial (Ledger)
 * - Escribe en financial_ledger:
 *   * Si NetWinnings > BuyIn: Tipo GAME_WIN (Color Verde)
 *   * Si NetWinnings < BuyIn: Tipo GAME_LOSS (Color Rojo)
 * - Incluye: amount, tableId, timestamp, rakePaid
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

    const db = admin.firestore();
    const userId = context.auth.uid;

    try {
        const result = await db.runTransaction(async (transaction) => {
            // --- LECTURAS INICIALES ---
            
            // 1. Leer Mesa
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);

            if (!tableDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Table not found.');
            }

            const tableData = tableDoc.data();
            const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];
            
            // 2. Buscar jugador en la mesa
            const playerIndex = players.findIndex((p: any) => p.id === userId);
            
            if (playerIndex === -1) {
                // Jugador no encontrado, pero puede tener sesión activa que necesita cerrarse
                // Buscar y cerrar sesión activa si existe
                const activeSessionQuery = await db.collection('poker_sessions')
                    .where('userId', '==', userId)
                    .where('roomId', '==', tableId)
                    .where('status', '==', 'active')
                    .limit(1)
                    .get();
                
                if (!activeSessionQuery.empty) {
                    const sessionDoc = activeSessionQuery.docs[0];
                    transaction.update(sessionDoc.ref, {
                        status: 'completed',
                        endTime: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
                
                return { success: true, message: 'Player not found on table. Session closed if existed.' };
            }

            const player = players[playerIndex];
            const playerChips = Number(player.chips) || 0;

            // 3. Leer Usuario
            const userRef = db.collection('users').doc(userId);
            const userDoc = await transaction.get(userRef);
            
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'User not found.');
            }

            const userData = userDoc.data();
            const userClubId = userData?.clubId;
            const userSellerId = userData?.sellerId;

            // 4. Buscar Sesión Activa del Jugador
            const activeSessionQuery = await db.collection('poker_sessions')
                .where('userId', '==', userId)
                .where('roomId', '==', tableId)
                .where('status', '==', 'active')
                .limit(1)
                .get();
            
            let sessionRef: admin.firestore.DocumentReference | null = null;
            let buyInAmount = 0;
            
            if (!activeSessionQuery.empty) {
                sessionRef = activeSessionQuery.docs[0].ref;
                const sessionData = activeSessionQuery.docs[0].data();
                buyInAmount = Number(sessionData.buyInAmount) || 0;
            }

            // --- PASO A: CÁLCULO DE RAKE Y NET WINNINGS ---
            
            if (playerChips === 0) {
                // Sin fichas, solo limpiar
                console.log(`[CASHOUT] Usuario ${userId} sale con 0 fichas. Solo limpieza.`);
                
                // LIMPIEZA DE ESTADO VISUAL incluso con 0 fichas
                transaction.update(userRef, {
                    currentTableId: admin.firestore.FieldValue.delete(),
                    moneyInPlay: admin.firestore.FieldValue.delete()
                });
                
                if (sessionRef) {
                    transaction.update(sessionRef, {
                        status: 'completed',
                        endTime: admin.firestore.FieldValue.serverTimestamp(),
                        currentChips: 0,
                        netResult: 0
                    });
                }
                
                // Crear registro en ledger incluso con 0 fichas (para historial completo)
                const ledgerRef = db.collection('financial_ledger').doc();
                const timestamp = admin.firestore.FieldValue.serverTimestamp();
                transaction.set(ledgerRef, {
                    type: 'GAME_LOSS',
                    userId: userId,
                    tableId: tableId,
                    amount: 0,
                    netAmount: 0,
                    netProfit: -buyInAmount, // Pérdida total del buy-in
                    grossAmount: 0,
                    rakePaid: 0,
                    buyInAmount: buyInAmount,
                    timestamp: timestamp,
                    description: `Retiro de Mesa ${tableId}. Pérdida Total: -${buyInAmount} (sin fichas restantes)`
                });
                
                // Remover jugador de la mesa y poner chips en 0
                players[playerIndex] = { ...player, chips: 0 };
                const tableUpdate: any = { players: players };
                if (players.length === 0) {
                    tableUpdate.status = 'inactive';
                }
                transaction.update(tableRef, tableUpdate);
                
                console.log(`[CASHOUT] Cashout con 0 fichas completado. Registro en ledger creado.`);
                
                return { success: true, message: 'Zero balance cashout completed.' };
            }

            // Calcular Rake (8% del stack final)
            const RAKE_PERCENTAGE = 0.08;
            const totalRake = Math.floor(playerChips * RAKE_PERCENTAGE);
            const netWinnings = playerChips - totalRake;

            // Determinar distribución de Rake según tipo de sala
            const isPublic = tableData?.isPublic === true;
            
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

            // --- PASO B: TRANSACCIÓN ATÓMICA ---
            
            console.log(`[CASHOUT] Usuario: ${userId}, Mesa: ${tableId}`);
            console.log(`[CASHOUT] Chips al salir: ${playerChips}`);
            console.log(`[CASHOUT] Buy-in original: ${buyInAmount}`);
            console.log(`[CASHOUT] Rake calculado: ${totalRake} (${(RAKE_PERCENTAGE * 100).toFixed(1)}%)`);
            console.log(`[CASHOUT] Monto final (netWinnings): ${netWinnings}`);
            
            // 1. Actualizar crédito del usuario (OBLIGATORIO usar increment)
            // CORRECCIÓN CRÍTICA: Sumar netWinnings (lo que tiene AHORA menos rake), NO buyInAmount
            transaction.update(userRef, {
                credit: admin.firestore.FieldValue.increment(netWinnings),
                // LIMPIEZA DE ESTADO VISUAL - Elimina el indicador "+X en mesa"
                currentTableId: admin.firestore.FieldValue.delete(),
                moneyInPlay: admin.firestore.FieldValue.delete()
            });
            
            console.log(`[CASHOUT] Crédito actualizado: +${netWinnings} al saldo del usuario`);

            // 2. Cerrar sesión en poker_sessions (ELIMINA indicador visual)
            if (sessionRef) {
                transaction.update(sessionRef, {
                    status: 'completed',
                    currentChips: playerChips,
                    totalRakePaid: totalRake,
                    netResult: netWinnings, // Guardar resultado neto para referencia
                    endTime: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[CASHOUT] Sesión cerrada: ${sessionRef.id}`);
            }

            // 3. Actualizar mesa: poner stack del jugador en 0 y remover
            players[playerIndex] = { ...player, chips: 0 };
            const tableUpdate: any = { players: players };
            if (players.length === 0) {
                tableUpdate.status = 'inactive';
            }
            transaction.update(tableRef, tableUpdate);

            // 4. Distribuir Rake
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // Platform Share
            if (platformShare > 0) {
                transaction.set(db.collection('system_stats').doc('economy'), {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare)
                }, { merge: true });
            }

            // Club Share
            if (clubShare > 0) {
                if (userClubId) {
                    transaction.update(db.collection('clubs').doc(userClubId), {
                        walletBalance: admin.firestore.FieldValue.increment(clubShare)
                    });
                } else {
                    // Fallback a Platform
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(clubShare)
                    }, { merge: true });
                }
            }

            // Seller Share
            if (sellerShare > 0) {
                if (userSellerId) {
                    transaction.update(db.collection('users').doc(userSellerId), {
                        credit: admin.firestore.FieldValue.increment(sellerShare)
                    });
                } else if (userClubId) {
                    // Fallback a Club si no hay Seller
                    transaction.update(db.collection('clubs').doc(userClubId), {
                        walletBalance: admin.firestore.FieldValue.increment(sellerShare)
                    });
                } else {
                    // Fallback a Platform
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                    }, { merge: true });
                }
            }

            // --- PASO C: GENERACIÓN DE HISTORIAL (LEDGER) ---
            
            // Determinar tipo de transacción según resultado
            const netProfit = netWinnings - buyInAmount; // Ganancia/Pérdida neta vs buy-in
            const ledgerType = netWinnings > buyInAmount ? 'GAME_WIN' : 'GAME_LOSS';
            
            console.log(`[CASHOUT] Tipo de transacción: ${ledgerType}`);
            console.log(`[CASHOUT] Ganancia/Pérdida neta: ${netProfit > 0 ? '+' : ''}${netProfit}`);
            
            // Crear entrada en financial_ledger (OBLIGATORIO - nunca debe estar vacío)
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: ledgerType,
                userId: userId,
                tableId: tableId,
                amount: netWinnings, // Monto final recibido
                netAmount: netWinnings, // Alias para consistencia
                netProfit: netProfit, // Ganancia/Pérdida vs buy-in original
                grossAmount: playerChips, // Fichas antes del rake
                rakePaid: totalRake,
                buyInAmount: buyInAmount,
                timestamp: timestamp,
                description: `Retiro de Mesa ${tableId}. ${ledgerType === 'GAME_WIN' ? 'Ganancia' : 'Pérdida'} Neta: ${netProfit > 0 ? '+' : ''}${netProfit} (Recibido: ${netWinnings}, Rake: ${totalRake})`
            });
            
            console.log(`[CASHOUT] Registro creado en financial_ledger: ${ledgerRef.id}`);

            return { 
                success: true, 
                netWinnings,
                grossAmount: playerChips,
                rakePaid: totalRake,
                ledgerType
            };
        });

        return result;

    } catch (error: any) {
        console.error('Error en processCashOut:', error);
        
        // Si es un error de Firestore conocido, propagarlo
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        
        throw new functions.https.HttpsError('internal', `Failed to cash out: ${error.message || 'Unknown error'}`);
    }
};

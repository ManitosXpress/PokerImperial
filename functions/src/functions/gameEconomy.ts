import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SettleRoundRequest } from "../types";

// Lazy initialization de Firestore
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

/**
 * INTERFACES
 */
interface JoinTableRequest {
    roomId: string;
    buyInAmount?: number;
}

interface ProcessCashOutRequest {
    tableId: string;
    userId?: string;
    playerChips?: number;
}

interface CloseTableRequest {
    tableId: string;
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 1. JOIN TABLE - ENTRADA ROBUSTA
 * ═══════════════════════════════════════════════════════════════════════════
 */
export const joinTable = async (data: JoinTableRequest, context: functions.https.CallableContext) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const uid = context.auth.uid;
    const db = getDb();
    const { roomId, buyInAmount } = data;

    if (!roomId || roomId === 'new_room' || roomId.trim() === '') {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid Room ID.');
    }

    console.log(`[ECONOMY] Player ${uid} joining table ${roomId}`);

    try {
        // 1. Validar existencia de la mesa
        const tableRef = db.collection('poker_tables').doc(roomId);
        const tableDoc = await tableRef.get();

        if (!tableDoc.exists) {
            throw new functions.https.HttpsError('not-found', `Table ${roomId} not found.`);
        }

        const tableData = tableDoc.data();
        const minBuyIn = Number(tableData?.minBuyIn) || 1000;
        const maxBuyIn = Number(tableData?.maxBuyIn) || 10000;
        const maxPlayers = Number(tableData?.maxPlayers) || 9;

        // Validar Buy-In
        let finalBuyIn = minBuyIn;
        if (buyInAmount) {
            if (buyInAmount < minBuyIn) throw new functions.https.HttpsError('invalid-argument', `Buy-in too low. Min: ${minBuyIn}`);
            if (buyInAmount > maxBuyIn) throw new functions.https.HttpsError('invalid-argument', `Buy-in too high. Max: ${maxBuyIn}`);
            finalBuyIn = buyInAmount;
        }

        // 2. Pre-check Idempotencia (Optimización)
        const existingSessionQuery = await db.collection('poker_sessions')
            .where('userId', '==', uid)
            .where('roomId', '==', roomId)
            .where('status', '==', 'active')
            .limit(1)
            .get();

        if (!existingSessionQuery.empty) {
            const existingSession = existingSessionQuery.docs[0];
            console.log(`[ECONOMY] Session exists for ${uid} in ${roomId}. Returning.`);
            await existingSession.ref.update({ lastActive: admin.firestore.FieldValue.serverTimestamp() });
            return {
                success: true,
                sessionId: existingSession.id,
                isExisting: true,
                buyInAmount: existingSession.data().buyInAmount,
                message: 'Session restored.'
            };
        }

        // 3. Transacción Atómica
        const result = await db.runTransaction(async (transaction) => {
            // Leer Usuario
            const userRef = db.collection('users').doc(uid);
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new functions.https.HttpsError('not-found', 'User not found.');

            const userData = userDoc.data();
            const currentCredit = Number(userData?.credit) || 0;
            const currentTableId = userData?.currentTableId || null;
            const moneyInPlay = Number(userData?.moneyInPlay) || 0;

            // Validar Estado
            if (currentTableId === roomId) throw new functions.https.HttpsError('already-exists', 'Session already active (race condition).');
            if (currentTableId !== null) throw new functions.https.HttpsError('failed-precondition', `Already playing in ${currentTableId}.`);

            // Limpieza automática de estado corrupto
            if (moneyInPlay > 0 && currentTableId === null) {
                console.warn(`[ECONOMY] Fixing corrupt state for ${uid}: moneyInPlay reset.`);
                transaction.update(userRef, { moneyInPlay: 0 });
            }

            // Validar Fondos
            if (currentCredit < finalBuyIn) {
                throw new functions.https.HttpsError('failed-precondition', `Insufficient funds. Need ${finalBuyIn}, have ${currentCredit}.`);
            }

            // Validar Espacio en Mesa (Lectura dentro de transacción)
            const tableSnapshot = await transaction.get(tableRef);
            const currentTableData = tableSnapshot.data();
            const currentPlayerCount = Array.isArray(currentTableData?.players) ? currentTableData.players.length : 0;
            if (currentPlayerCount >= maxPlayers) throw new functions.https.HttpsError('resource-exhausted', 'Table is full.');

            // EJECUCIÓN
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // A. Descontar Crédito
            transaction.update(userRef, {
                credit: currentCredit - finalBuyIn,
                moneyInPlay: finalBuyIn,
                currentTableId: roomId,
                lastUpdated: timestamp
            });

            // B. Crear Sesión
            const sessionRef = db.collection('poker_sessions').doc();
            const newSessionId = sessionRef.id;
            transaction.set(sessionRef, {
                userId: uid,
                roomId: roomId,
                buyInAmount: finalBuyIn,
                currentChips: finalBuyIn,
                startTime: timestamp,
                lastActive: timestamp,
                status: 'active',
                totalRakePaid: 0,
                createdAt: timestamp
            });

            // C. Log Transacción
            const txLogRef = db.collection('transaction_logs').doc();
            transaction.set(txLogRef, {
                userId: uid,
                amount: -finalBuyIn,
                type: 'debit',
                reason: `Poker Buy-In - Table ${roomId}`,
                timestamp: timestamp,
                beforeBalance: currentCredit,
                afterBalance: currentCredit - finalBuyIn,
                metadata: { sessionId: newSessionId, roomId, buyInAmount: finalBuyIn }
            });

            return { sessionId: newSessionId, buyInAmount: finalBuyIn };
        });

        console.log(`[ECONOMY] Player ${uid} joined ${roomId} with ${finalBuyIn}`);
        return {
            success: true,
            sessionId: result.sessionId,
            isExisting: false,
            buyInAmount: result.buyInAmount,
            message: 'Joined successfully.'
        };

    } catch (error: any) {
        console.error(`[ECONOMY] Join Error:`, error);
        if (error.code === 'already-exists') {
            // Retry logic could go here, but for now we let the client handle it or just fail
        }
        throw error instanceof functions.https.HttpsError ? error : new functions.https.HttpsError('internal', error.message);
    }
};

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 2. SETTLE GAME ROUND - EL MOTOR FINANCIERO (POT RAKE)
 * ═══════════════════════════════════════════════════════════════════════════
 */
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');

    const db = getDb();
    const { potTotal, winnerUid, gameId, tableId } = data;

    if (!potTotal || !winnerUid || !tableId) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing parameters.');
    }

    console.log(`[ECONOMY] Settling round ${gameId} in ${tableId}. Pot: ${potTotal}, Winner: ${winnerUid}`);

    // CÁLCULO DE RAKE (8%)
    const RAKE_PERCENTAGE = 0.08;
    const rakeAmount = Math.floor(potTotal * RAKE_PERCENTAGE);
    const winnerPrize = potTotal - rakeAmount;

    try {
        await db.runTransaction(async (transaction) => {
            // 1. Leer Mesa
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);
            if (!tableDoc.exists) throw new functions.https.HttpsError('not-found', 'Table not found.');

            const tableData = tableDoc.data();
            const isPublic = tableData?.isPublic === true;
            const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];

            // 2. Actualizar Chips del Ganador (MESA = FUENTE DE VERDAD)
            const winnerIndex = players.findIndex((p: any) => p.id === winnerUid);
            if (winnerIndex === -1) throw new functions.https.HttpsError('not-found', 'Winner not in table.');

            const currentWinnerChips = Number(players[winnerIndex].chips) || 0;
            const newWinnerChips = currentWinnerChips + winnerPrize;

            transaction.update(tableRef, {
                [`players.${winnerIndex}.chips`]: newWinnerChips
            });

            // 3. Distribución del Rake (Inmediata)
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (!isPublic) {
                // Privada: 100% Plataforma
                platformShare = rakeAmount;
            } else {
                // Pública: 50% Plataforma, 30% Club, 20% Seller
                platformShare = Math.floor(rakeAmount * 0.50);
                clubShare = Math.floor(rakeAmount * 0.30);
                sellerShare = Math.floor(rakeAmount * 0.20);
                // Ajuste por redondeo
                platformShare += (rakeAmount - (platformShare + clubShare + sellerShare));
            }

            // Leer datos del ganador para atribución
            const winnerRef = db.collection('users').doc(winnerUid);
            const winnerDoc = await transaction.get(winnerRef);
            const winnerData = winnerDoc.data();
            const winnerClubId = winnerData?.clubId;
            const winnerSellerId = winnerData?.sellerId;

            // A. Plataforma
            if (platformShare > 0) {
                transaction.set(db.collection('system_stats').doc('economy'), {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare),
                    dailyGGR: admin.firestore.FieldValue.increment(platformShare),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }

            // B. Club
            if (clubShare > 0) {
                if (winnerClubId) {
                    transaction.update(db.collection('clubs').doc(winnerClubId), {
                        walletBalance: admin.firestore.FieldValue.increment(clubShare)
                    });
                } else {
                    // Fallback a plataforma
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(clubShare)
                    }, { merge: true });
                }
            }

            // C. Seller
            if (sellerShare > 0) {
                if (winnerSellerId) {
                    transaction.update(db.collection('users').doc(winnerSellerId), {
                        credit: admin.firestore.FieldValue.increment(sellerShare)
                    });
                } else {
                    // Fallback a plataforma (simplificado)
                    transaction.set(db.collection('system_stats').doc('economy'), {
                        accumulated_rake: admin.firestore.FieldValue.increment(sellerShare)
                    }, { merge: true });
                }
            }

            // 4. Ledger (RAKE_COLLECTED)
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'RAKE_COLLECTED',
                tableId,
                handId: gameId,
                potTotal,
                rakeAmount,
                winnerUid,
                distribution: { platform: platformShare, club: clubShare, seller: sellerShare },
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Rake from hand ${gameId}`
            });

            // 5. Stats Diarias
            const dateKey = new Date().toISOString().split('T')[0];
            const dailyStatsRef = db.collection('stats_daily').doc(dateKey);
            transaction.set(dailyStatsRef, {
                dateKey,
                totalVolume: admin.firestore.FieldValue.increment(potTotal),
                dailyGGR: admin.firestore.FieldValue.increment(rakeAmount),
                totalRake: admin.firestore.FieldValue.increment(rakeAmount),
                handsPlayed: admin.firestore.FieldValue.increment(1)
            }, { merge: true });

        });

        return { success: true, potTotal, rakeAmount, winnerPrize };

    } catch (error: any) {
        console.error(`[ECONOMY] Settle Error:`, error);
        throw error instanceof functions.https.HttpsError ? error : new functions.https.HttpsError('internal', error.message);
    }
};

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 3. PROCESS CASH OUT - SALIDA LIMPIA (SIN RAKE)
 * ═══════════════════════════════════════════════════════════════════════════
 */
export const processCashOut = async (data: ProcessCashOutRequest, context: functions.https.CallableContext) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');

    const uid = context.auth.uid;
    const targetUserId = data.userId || uid;
    const db = getDb();
    const { tableId } = data;

    if (!tableId) throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');
    if (targetUserId !== uid) throw new functions.https.HttpsError('permission-denied', 'Cannot cash out other users.');

    console.log(`[ECONOMY] Processing CashOut for ${targetUserId} from ${tableId}`);

    try {
        await db.runTransaction(async (transaction) => {
            // 1. Leer Mesa (FUENTE DE VERDAD)
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);
            if (!tableDoc.exists) throw new functions.https.HttpsError('not-found', 'Table not found.');

            const tableData = tableDoc.data();
            const players = Array.isArray(tableData?.players) ? tableData.players : [];
            const player = players.find((p: any) => p.id === targetUserId);

            // Determinar monto a devolver
            let chipsToTransfer = 0;
            if (player) {
                chipsToTransfer = Number(player.chips) || 0;
            } else if (data.playerChips !== undefined) {
                // Caso especial: jugador ya removido visualmente pero no financieramente
                chipsToTransfer = Number(data.playerChips);
            } else {
                throw new functions.https.HttpsError('failed-precondition', 'Player not found in table and no chips provided.');
            }

            // 2. Leer Usuario
            const userRef = db.collection('users').doc(targetUserId);

            // 3. Buscar Sesión (para auditoría)
            const sessionQuery = await db.collection('poker_sessions')
                .where('userId', '==', targetUserId)
                .where('roomId', '==', tableId)
                .where('status', '==', 'active')
                .get(); // Query fuera de tx si es posible, pero necesitamos consistencia. 
            // Firestore permite queries en tx si están indexadas.
            // Asumimos que processCashOut es llamado infrecuentemente.
            // Para simplificar y evitar limitaciones de query en tx, 
            // podríamos hacer la query fuera y validar dentro con un get().
            // Pero aquí haremos la actualización directa de las sesiones encontradas.

            // 4. EJECUCIÓN
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // A. Transferir Saldo (SIN RAKE)
            transaction.update(userRef, {
                credit: admin.firestore.FieldValue.increment(chipsToTransfer),
                moneyInPlay: 0,
                currentTableId: null,
                lastUpdated: timestamp
            });

            // B. Cerrar Sesiones
            if (!sessionQuery.empty) {
                sessionQuery.docs.forEach(doc => {
                    transaction.update(doc.ref, {
                        status: 'completed',
                        currentChips: chipsToTransfer,
                        endTime: timestamp,
                        closedReason: 'cashout'
                    });
                });
            }

            // C. Actualizar Mesa (Quitar jugador o poner chips a 0)
            if (player) {
                const playerIndex = players.findIndex((p: any) => p.id === targetUserId);
                transaction.update(tableRef, {
                    [`players.${playerIndex}.chips`]: 0,
                    [`players.${playerIndex}.inGame`]: false
                });
            }

            // D. Logs
            const txLogRef = db.collection('transaction_logs').doc();
            transaction.set(txLogRef, {
                userId: targetUserId,
                amount: chipsToTransfer,
                type: 'credit',
                reason: `Poker Cashout - Table ${tableId}`,
                timestamp: timestamp,
                metadata: { tableId, chips: chipsToTransfer }
            });

            console.log(`[ECONOMY] Player ${targetUserId} cashed out ${chipsToTransfer}`);
        });

        return { success: true, amount: 0 }; // Amount is dynamic, but client might not need it returned here if they listen to user doc

    } catch (error: any) {
        console.error(`[ECONOMY] CashOut Error:`, error);
        throw error instanceof functions.https.HttpsError ? error : new functions.https.HttpsError('internal', error.message);
    }
};

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 4. UNIVERSAL TABLE SETTLEMENT - CIERRE DE MESA
 * ═══════════════════════════════════════════════════════════════════════════
 */
export const universalTableSettlement = async (data: CloseTableRequest, context: functions.https.CallableContext) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');

    const db = getDb();
    const { tableId } = data;
    if (!tableId) throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');

    console.log(`[ECONOMY] Universal Settlement for ${tableId}`);

    try {
        // 1. Leer Mesa y Jugadores
        const tableRef = db.collection('poker_tables').doc(tableId);
        const tableDoc = await tableRef.get();
        if (!tableDoc.exists) throw new functions.https.HttpsError('not-found', 'Table not found.');

        const tableData = tableDoc.data();
        const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];

        if (players.length === 0) {
            await tableRef.update({ status: 'FINISHED' });
            return { success: true, message: 'Table closed (empty).' };
        }

        // 2. Iterar y Liquidar (Batch o Serie de Transacciones)
        // Dado que runTransaction tiene límite de escrituras, y universalTableSettlement puede tener muchos jugadores,
        // lo ideal es hacerlo en una sola transacción si son pocos (<500 ops), o iterar.
        // Asumimos mesa de poker max 9 jugadores -> Una sola transacción es segura.

        await db.runTransaction(async (transaction) => {
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            for (const player of players) {
                const uid = player.id;
                const chips = Number(player.chips) || 0;

                if (!uid) continue;

                // A. Devolver Crédito (SIN RAKE)
                const userRef = db.collection('users').doc(uid);
                transaction.update(userRef, {
                    credit: admin.firestore.FieldValue.increment(chips),
                    moneyInPlay: 0,
                    currentTableId: null,
                    lastUpdated: timestamp
                });

                // B. Log
                const txLogRef = db.collection('transaction_logs').doc();
                transaction.set(txLogRef, {
                    userId: uid,
                    amount: chips,
                    type: 'credit',
                    reason: `Table Closed - ${tableId}`,
                    timestamp: timestamp,
                    metadata: { tableId, chips }
                });
            }

            // C. Cerrar Sesiones Activas de esta mesa
            // NOTA: Query dentro de transacción puede ser costosa. 
            // Si confiamos en que processCashOut limpia, aquí es solo remanentes.
            // Para simplificar en esta refactorización estricta:
            // No podemos hacer query dinámica compleja dentro de tx fácilmente sin leer primero.
            // Omitimos el cierre de sesiones en la transacción para evitar complejidad, 
            // O lo hacemos fuera y luego actualizamos.
            // MEJOR OPCIÓN: Actualizar la mesa a FINISHED primero.

            transaction.update(tableRef, {
                status: 'FINISHED',
                players: [], // Vaciar mesa
                lastUpdated: timestamp
            });
        });

        // Limpieza de sesiones fuera de transacción (Best Effort)
        const activeSessions = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();

        const batch = db.batch();
        activeSessions.docs.forEach(doc => {
            batch.update(doc.ref, { status: 'completed', closedReason: 'table_closed' });
        });
        await batch.commit();

        console.log(`[ECONOMY] Table ${tableId} settled and closed.`);
        return { success: true };

    } catch (error: any) {
        console.error(`[ECONOMY] Universal Settlement Error:`, error);
        throw error instanceof functions.https.HttpsError ? error : new functions.https.HttpsError('internal', error.message);
    }
};

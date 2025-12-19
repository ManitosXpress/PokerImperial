import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { SettleRoundRequest } from "../types";

// 🔐 Cargar variables de entorno desde .env SOLO EN DESARROLLO LOCAL
// En producción, usar functions.config() o environment variables de Firebase
// NOTA: Comentado para evitar timeouts durante deployment
// Para desarrollo local, configurar variables de entorno manualmente o usar .env con otra estrategia
/*
if (process.env.FUNCTIONS_EMULATOR === 'true' || !process.env.K_SERVICE) {
    // Estamos en desarrollo local
    try {
        require('dotenv').config();
        console.log('[ENV] Loaded .env for local development');
    } catch (e) {
        console.warn('[ENV] dotenv not available, using environment variables');
    }
}
*/

// 🔐 GAME SECRET para verificación de firmas HMAC-SHA256
// CRÍTICO: Debe coincidir con el secret en el Game Server
// Prioridad: 1. Environment variable, 2. Firebase config, 3. Default (solo para dev)
const GAME_SECRET = process.env.GAME_SECRET ||
    functions.config().game?.secret ||
    'default-secret-change-in-production-2024';

if (!process.env.GAME_SECRET && !functions.config().game?.secret) {
    console.warn('⚠️ [SECURITY] Using default GAME_SECRET - NOT SECURE FOR PRODUCTION!');
}

// Lazy initialization de Firestore
export const getDb = () => {
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
    uid: string;
    finalChips: number;
    reason: 'EXIT' | 'DISCONNECT' | 'BANKRUPTCY' | 'TABLE_CLOSED';
    authPayload?: string;  // JSON signed payload from server
    signature?: string;    // HMAC-SHA256 signature
    // Legacy support
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
 * 
 * ARQUITECTURA: Game Server = Fuente de Verdad para Stacks, Firebase = Contabilidad de Rake
 * 
 * IMPORTANTE: Esta función NO modifica users/{uid}/moneyInPlay.
 * 
 * El campo moneyInPlay representa el Buy-In inicial bloqueado y solo se modifica en:
 * - joinTable: Se establece al monto del buy-in
 * - processCashOut: Se resetea a 0 cuando el jugador sale de la mesa
 * 
 * Durante el juego, las fichas fluctúan en poker_tables/{tableId}/players[i]/chips,
 * pero moneyInPlay permanece constante hasta el cash-out.
 */

/**
 * 🔐 Verifica la firma HMAC-SHA256 del payload
 * Usa comparación segura (timingSafeEqual) para prevenir ataques de timing
 */
function verifySignature(authPayload: string, receivedSignature: string): boolean {
    try {
        const hmac = crypto.createHmac('sha256', GAME_SECRET);
        hmac.update(authPayload);
        const computedSignature = hmac.digest('hex');

        // Comparación segura contra timing attacks
        return crypto.timingSafeEqual(
            Buffer.from(computedSignature, 'hex'),
            Buffer.from(receivedSignature, 'hex')
        );
    } catch (error) {
        console.error('Signature verification error:', error);
        return false;
    }
}

/**
 * Core logic for settling a game round.
 * Can be called by the client (via Callable) or the server (via Trigger).
 */
export const settleGameRoundCore = async (data: SettleRoundRequest, injectedDb?: admin.firestore.Firestore) => {
    const db = injectedDb || getDb();
    const { potTotal, winnerUid, gameId, tableId, finalPlayerStacks, authPayload, signature } = data;

    // 🔐 VERIFICACIÓN DE FIRMA CRIPTOGRÁFICA (Opcional pero recomendado)
    if (authPayload && signature) {
        console.log(`[SECURITY] Verifying signature for game ${gameId}...`);

        if (!verifySignature(authPayload, signature)) {
            console.error(`🚫 [SECURITY] Signature verification FAILED for game ${gameId}`);
            throw new functions.https.HttpsError(
                'permission-denied',
                'Data integrity check failed - signature mismatch'
            );
        }

        // Verificar que el payload contenga los datos correctos
        try {
            const payload = JSON.parse(authPayload);
            if (payload.winnerUid !== winnerUid || payload.potTotal !== potTotal) {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'Payload mismatch - data does not match signature'
                );
            }
        } catch (parseError) {
            console.error('Failed to parse authPayload:', parseError);
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Invalid authPayload format'
            );
        }

        console.log(`✅ [SECURITY] Signature verified successfully for game ${gameId}`);
    } else {
        console.warn(`⚠️ [SECURITY] No signature provided for game ${gameId} - operating in legacy mode`);
    }

    if (!potTotal || !winnerUid || !tableId || !finalPlayerStacks) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing parameters.');
    }

    console.log(`[ECONOMY] Settling round ${gameId} in ${tableId}. Pot: ${potTotal}, Winner: ${winnerUid}`);
    console.log(`[ECONOMY] Final Player Stacks from Server:`, finalPlayerStacks);

    // CÁLCULO DE RAKE (Server Authority)
    let rakeAmount = 0;

    if (authPayload) {
        try {
            const trustedPayload = JSON.parse(authPayload);
            if (trustedPayload.rakeTaken !== undefined) {
                rakeAmount = Number(trustedPayload.rakeTaken);
                console.log(`[ECONOMY] Using trusted rake amount from server: ${rakeAmount}`);
            } else {
                // Fallback (no debería ocurrir con el nuevo servidor)
                rakeAmount = Math.floor(potTotal * 0.08);
                console.warn('[ECONOMY] Rake not in payload, calculated locally.');
            }
        } catch (e) {
            rakeAmount = Math.floor(potTotal * 0.08);
        }
    } else {
        // Legacy mode
        rakeAmount = Math.floor(potTotal * 0.08);
    }

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

            // 2. ACTUALIZAR STACKS DIRECTAMENTE DESDE EL SERVIDOR
            // ✅ CORRECCIÓN CRÍTICA: Escribir valores exactos del servidor en lugar de calcular con datos desactualizados
            // El Game Server ya calculó los stacks finales en memoria (fuente de verdad)
            // Firebase solo persiste esos valores y procesa el rake

            // 🔐 SEGURIDAD: Usar stacks del payload firmado si está disponible
            let stacksToUse = finalPlayerStacks;
            if (authPayload) {
                try {
                    const trustedPayload = JSON.parse(authPayload);
                    if (trustedPayload.finalPlayerStacks) {
                        stacksToUse = trustedPayload.finalPlayerStacks;
                        console.log('[SECURITY] Using trusted stacks from signed payload');
                    }
                } catch (e) {
                    console.error('[SECURITY] Error parsing payload for stacks, falling back to insecure param', e);
                }
            }

            for (const [uid, finalChips] of Object.entries(stacksToUse)) {
                const playerIndex = players.findIndex((p: any) => p.uid === uid);

                if (playerIndex === -1) {
                    console.warn(`[ECONOMY] Player ${uid} not found in table. Skipping.`);
                    continue;
                }

                // Escribir directamente el stack final calculado por el servidor
                transaction.update(tableRef, {
                    [`players.${playerIndex}.chips`]: finalChips
                });

                console.log(`[ECONOMY] ✅ Synced ${uid}: ${finalChips} chips`);
            }

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
                    total_volume: admin.firestore.FieldValue.increment(potTotal),
                    hands_played: admin.firestore.FieldValue.increment(1),
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
                        accumulated_rake: admin.firestore.FieldValue.increment(clubShare),
                        total_volume: admin.firestore.FieldValue.increment(potTotal),
                        hands_played: admin.firestore.FieldValue.increment(1)
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
                        accumulated_rake: admin.firestore.FieldValue.increment(sellerShare),
                        total_volume: admin.firestore.FieldValue.increment(potTotal),
                        hands_played: admin.firestore.FieldValue.increment(1)
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

export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    return settleGameRoundCore(data);
};

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 3. PROCESS CASH OUT - SALIDA LIMPIA (SIN RAKE)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * IMPORTANTE: Ahora soporta cashouts iniciados por el servidor con firma HMAC.
 * El servidor puede forzar el cierre de sesión sin depender del cliente.
 */
export const processCashOut = async (data: ProcessCashOutRequest, context?: functions.https.CallableContext) => {
    const db = getDb();
    const { tableId, authPayload, signature } = data;

    if (!tableId) throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');

    // Determinar el UID del jugador
    let targetUserId: string;
    let chipsToTransfer: number;
    let cashoutReason: string;

    // 🔐 VERIFICACIÓN DE FIRMA (Server-Initiated Cashout)
    if (authPayload && signature) {
        console.log(`[CASHOUT] 🔐 Server-initiated cashout with signature verification`);

        if (!verifySignature(authPayload, signature)) {
            console.error(`[CASHOUT] ❌ Invalid signature! Possible fraud attempt.`);
            throw new functions.https.HttpsError('permission-denied', 'Invalid signature');
        }

        // Parsear el payload firmado (fuente de verdad)
        try {
            const trustedPayload = JSON.parse(authPayload);
            targetUserId = trustedPayload.uid;
            chipsToTransfer = Number(trustedPayload.finalChips) || 0;
            cashoutReason = trustedPayload.reason || 'server_initiated';

            console.log(`[CASHOUT] ✅ Signature verified. Processing ${cashoutReason} for ${targetUserId}: ${chipsToTransfer} chips`);
        } catch (e) {
            console.error(`[CASHOUT] ❌ Error parsing authPayload:`, e);
            throw new functions.https.HttpsError('invalid-argument', 'Invalid authPayload format');
        }
    } else {
        // Client-initiated cashout (legacy)
        if (!context || !context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'Authentication required for client cashout.');
        }

        const uid = context.auth.uid;
        targetUserId = data.userId || data.uid || uid;
        cashoutReason = data.reason || 'manual_cashout';

        if (targetUserId !== uid) {
            throw new functions.https.HttpsError('permission-denied', 'Cannot cash out other users.');
        }

        console.log(`[CASHOUT] 📱 Client-initiated cashout for ${targetUserId}`);
    }

    try {
        const result = await db.runTransaction(async (transaction) => {
            // 1. IDEMPOTENCY CHECK - Verificar si ya fue procesado
            const sessionQuery = await db.collection('poker_sessions')
                .where('userId', '==', targetUserId)
                .where('roomId', '==', tableId)
                .limit(1)
                .get();

            if (!sessionQuery.empty) {
                const sessionDoc = sessionQuery.docs[0];
                const sessionData = sessionDoc.data();

                if (sessionData.status === 'completed') {
                    console.log(`[CASHOUT] ⚠️ Session already completed. Skipping duplicate cashout.`);
                    return { success: true, skipped: true, reason: 'already_completed' };
                }
            }

            // 2. Determinar monto si no viene del payload firmado
            if (!authPayload) {
                const tableRef = db.collection('poker_tables').doc(tableId);
                const tableDoc = await transaction.get(tableRef);

                if (tableDoc.exists) {
                    const tableData = tableDoc.data();
                    const players = Array.isArray(tableData?.players) ? tableData.players : [];
                    const player = players.find((p: any) => p.id === targetUserId || p.uid === targetUserId);

                    if (player) {
                        chipsToTransfer = Number(player.chips) || 0;
                    } else if (data.playerChips !== undefined || data.finalChips !== undefined) {
                        chipsToTransfer = Number(data.playerChips || data.finalChips) || 0;
                    } else {
                        console.warn(`[CASHOUT] ⚠️ Player ${targetUserId} not found in table ${tableId}`);
                        chipsToTransfer = 0;
                    }
                } else {
                    console.warn(`[CASHOUT] ⚠️ Table ${tableId} not found, using fallback chips`);
                    chipsToTransfer = Number(data.playerChips || data.finalChips) || 0;
                }
            }

            // 3. TRANSFERENCIA FINANCIERA
            const userRef = db.collection('users').doc(targetUserId);
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // ✅ CRÍTICO: Resetear moneyInPlay a 0 y currentTableId a null
            transaction.update(userRef, {
                credit: admin.firestore.FieldValue.increment(chipsToTransfer),
                moneyInPlay: 0,
                currentTableId: null,
                lastUpdated: timestamp
            });

            // 4. CERRAR SESIONES
            if (!sessionQuery.empty) {
                sessionQuery.docs.forEach(doc => {
                    transaction.update(doc.ref, {
                        status: 'completed',
                        currentChips: chipsToTransfer,
                        endTime: timestamp,
                        closedReason: cashoutReason
                    });
                });
            }

            // 5. ACTUALIZAR MESA (marcar jugador como fuera)
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);

            if (tableDoc.exists) {
                const tableData = tableDoc.data();
                const players = Array.isArray(tableData?.players) ? tableData.players : [];
                const playerIndex = players.findIndex((p: any) => p.id === targetUserId || p.uid === targetUserId);

                if (playerIndex !== -1) {
                    transaction.update(tableRef, {
                        [`players.${playerIndex}.chips`]: 0,
                        [`players.${playerIndex}.inGame`]: false
                    });
                }
            }

            // 6. LOGS DE TRANSACCIÓN
            const txLogRef = db.collection('transaction_logs').doc();
            transaction.set(txLogRef, {
                userId: targetUserId,
                amount: chipsToTransfer,
                type: 'credit',
                reason: `Poker Cashout - ${cashoutReason}`,
                timestamp: timestamp,
                metadata: { tableId, chips: chipsToTransfer, reason: cashoutReason }
            });

            console.log(`[CASHOUT] ✅ Successfully cashed out ${targetUserId}: ${chipsToTransfer} chips (${cashoutReason})`);

            return { success: true, amount: chipsToTransfer, skipped: false };
        });

        return result;
    } catch (error: any) {
        console.error(`[CASHOUT] ❌ Error:`, error);
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

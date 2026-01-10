import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { SettleRoundRequest } from "../types";
// import { onCall, HttpsError } from "firebase-functions/v2/https"; // Revertido a v1 por error de upgrade
import { logToLiveFeed, FeedEventPayload } from "../utils/liveFeed";

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
// 🔐 GAME SECRET para verificación de firmas HMAC-SHA256
// CRÍTICO: Debe coincidir con el secret en el Game Server
// Prioridad: 1. Environment variable, 2. Firebase config, 3. Default (solo para dev)
const getGameSecret = () => {
    try {
        const secret = process.env.GAME_SECRET ||
            functions.config().game?.secret ||
            'default-secret-change-in-production-2024';

        if (secret === 'default-secret-change-in-production-2024') {
            console.warn('⚠️ [SECURITY] Using default GAME_SECRET - NOT SECURE FOR PRODUCTION!');
        }
        return secret;
    } catch (e) {
        console.warn('⚠️ [CONFIG] Failed to read game secret, using default');
        return 'default-secret-change-in-production-2024';
    }
};

// Lazy initialization de Firestore
export const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

/**
 * 🏦 BILLETERA DE TESORERÍA (VERSATECH)
 * UID del Administrador Principal que recibe el platformShare del rake.
 */
const TREASURY_ADMIN_UID = "g2ISanL5eJVfkNijF8l8jFiA5v52";

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
            if (buyInAmount < minBuyIn) {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    `El Buy-In debe ser al menos ${minBuyIn}. Recibido: ${buyInAmount}`
                );
            }
            if (buyInAmount > maxBuyIn) {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    `El Buy-In no puede exceder ${maxBuyIn}. Recibido: ${buyInAmount}`
                );
            }
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
        const hmac = crypto.createHmac('sha256', getGameSecret());
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
            // 1. LEER DATOS (Reads before Writes)
            const tableRef = db.collection('poker_tables').doc(tableId);
            const tableDoc = await transaction.get(tableRef);
            if (!tableDoc.exists) throw new functions.https.HttpsError('not-found', 'Table not found.');

            const tableData = tableDoc.data();
            const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];

            // Datos para Rake Distribution
            const clubId = tableData?.clubId || null;
            const sellerId = tableData?.sellerId || null;
            let clubOwnerId: string | null = null;

            // Leer Club si aplica
            if (clubId) {
                const clubRef = db.collection('clubs').doc(clubId);
                const clubDoc = await transaction.get(clubRef);
                if (clubDoc.exists) {
                    clubOwnerId = clubDoc.data()?.ownerId || null;
                }
            }

            // Leer Ganador (para Live Feed y stats)
            const winnerRef = db.collection('users').doc(winnerUid);
            const winnerDoc = await transaction.get(winnerRef);
            const winnerData = winnerDoc.data();

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

            // 3. Distribución del Rake (Revenue Share) - NUEVA LÓGICA
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (clubId && clubOwnerId) {
                // MESA DE CLUB: 30% Club, 20% Seller (si existe), 50% Platform
                clubShare = Math.floor(rakeAmount * 0.30);

                if (sellerId) {
                    sellerShare = Math.floor(rakeAmount * 0.20);
                }

                // Platform se lleva el resto
                platformShare = rakeAmount - clubShare - sellerShare;

                // Pagar al Dueño del Club
                const ownerRef = db.collection('users').doc(clubOwnerId);
                transaction.update(ownerRef, {
                    credit: admin.firestore.FieldValue.increment(clubShare),
                    // Opcional: stats de ganancias del club owner si se trackean en el user
                });

                // Pagar al Seller (si existe)
                if (sellerId && sellerShare > 0) {
                    const sellerRef = db.collection('users').doc(sellerId);
                    transaction.update(sellerRef, {
                        credit: admin.firestore.FieldValue.increment(sellerShare),
                        commissionEarned: admin.firestore.FieldValue.increment(sellerShare)
                    });
                }

                // Actualizar wallet del club (para registro)
                transaction.update(db.collection('clubs').doc(clubId), {
                    walletBalance: admin.firestore.FieldValue.increment(clubShare),
                    totalRakeEarned: admin.firestore.FieldValue.increment(clubShare)
                });

            } else {
                // MESA GLOBAL / PRIVADA (Sin Club válido): 100% Plataforma
                platformShare = rakeAmount;
            }

            // A. Plataforma (Siempre recibe algo)
            if (platformShare > 0) {
                transaction.set(db.collection('system_stats').doc('economy'), {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare),
                    dailyGGR: admin.firestore.FieldValue.increment(platformShare),
                    total_volume: admin.firestore.FieldValue.increment(potTotal),
                    hands_played: admin.firestore.FieldValue.increment(1),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }

            // 4. Ledger (RAKE)
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'RAKE',
                amount: rakeAmount,  // Normalized amount field for queries
                tableId,
                handId: gameId,
                potTotal,
                rakeAmount,  // Keep for backward compatibility
                winnerUid,
                distribution: { platform: platformShare, club: clubShare, seller: sellerShare },
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Rake from hand ${gameId}`,
                metadata: {
                    clubId: clubId || null,
                    sellerId: sellerId || null,
                    clubOwnerId: clubOwnerId || null
                }
            });

            // 5. Stats Diarias
            const dateKey = new Date().toISOString().split('T')[0];
            const dailyStatsRef = db.collection('stats_daily').doc(dateKey);
            transaction.set(dailyStatsRef, {
                dateKey,
                totalVolume: admin.firestore.FieldValue.increment(potTotal),
                dailyGGR: admin.firestore.FieldValue.increment(rakeAmount),
                totalRake: admin.firestore.FieldValue.increment(rakeAmount),
                handsPlayed: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // 6. LIVE FEED (BIG POT)
            const bigBlind = Number(tableData?.bigBlind) || 20;
            if (potTotal >= bigBlind * 50) {
                const winnerName = winnerData?.name || 'Player';
                const feedPayload: FeedEventPayload = {
                    type: 'BIG_POT',
                    title: `${winnerName} ganó un bote de ${potTotal}`,
                    subtitle: `Mesa ${tableData?.name || 'Poker'} - Big Win`,
                    amount: potTotal,
                    clubId: clubId || undefined
                };
                await logToLiveFeed(feedPayload, transaction);
            }

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

            // [AUDIT FIX] Calcular NetProfit para fines informativos (sin afectar payout)
            let initialBuyIn = 0;
            let totalRebuys = 0;
            let netProfit = 0;

            if (!sessionQuery.empty) {
                const sData = sessionQuery.docs[0].data();
                initialBuyIn = Number(sData.buyInAmount) || 0;
                totalRebuys = Number(sData.totalRebuys) || 0; // [AUDIT FIX] Leer rebuys
                netProfit = chipsToTransfer - (initialBuyIn + totalRebuys);
            } else {
                // Si no hay sesión, asumimos que todo es profit (o error), pero no bloqueamos
                netProfit = chipsToTransfer;
            }

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
                metadata: {
                    tableId,
                    chips: chipsToTransfer,
                    reason: cashoutReason,
                    // [AUDIT FIX] Datos informativos de rentabilidad
                    initialBuyIn,
                    totalRebuys,
                    netProfit
                }
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
 * 4. UNIVERSAL TABLE SETTLEMENT - CIERRE DE MESA (TAX-FREE)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * IMPORTANTE: Esta función NO cobra Rake. El Rake ya fue cobrado mano a mano
 * en settleGameRound/processRakeLocal. Esta función solo devuelve las fichas
 * finales del jugador a su billetera (credit).
 */
export const universalTableSettlement = async (data: CloseTableRequest, context: functions.https.CallableContext) => {
    // 1. Validación
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    const { tableId } = data;
    if (!tableId) throw new functions.https.HttpsError('invalid-argument', 'Missing tableId.');

    const db = getDb();
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    try {
        console.log(`[UNIVERSAL_SETTLEMENT] (FIXED) Iniciando liquidación Tax-Free mesa ${tableId}`);

        // --- LECTURAS PRE-TRANSACCIÓN ---
        const tableRef = db.collection('poker_tables').doc(tableId);
        const tableDoc = await tableRef.get();

        if (!tableDoc.exists) throw new functions.https.HttpsError('not-found', 'Table not found.');

        const tableData = tableDoc.data();
        // Si la mesa ya está finalizada, abortar para mantener idempotencia
        if (tableData?.status === 'FINISHED') {
            return { success: true, message: 'Table already finished.', playersProcessed: 0 };
        }

        // Obtener sesiones activas
        const activeSessionsQuery = await db.collection('poker_sessions')
            .where('roomId', '==', tableId)
            .where('status', '==', 'active')
            .get();

        const sessionsByUser = new Map<string, Array<{ ref: admin.firestore.DocumentReference, data: any }>>();
        activeSessionsQuery.docs.forEach(doc => {
            const d = doc.data();
            if (d.userId) {
                const existing = sessionsByUser.get(d.userId) || [];
                existing.push({ ref: doc.ref, data: d });
                sessionsByUser.set(d.userId, existing);
            }
        });

        // Obtener referencias de usuarios
        const players = Array.isArray(tableData?.players) ? [...tableData.players] : [];
        const userIds = players.map((p: any) => p.id).filter(Boolean);
        const userMap = new Map();
        if (userIds.length > 0) {
            const userDocs = await Promise.all(userIds.map((uid: string) => db.collection('users').doc(uid).get()));
            userDocs.forEach((doc, index) => {
                if (doc.exists) userMap.set(userIds[index], { ref: doc.ref, data: doc.data() });
            });
        }

        // --- TRANSACCIÓN ATÓMICA ---
        const result = await db.runTransaction(async (transaction) => {
            const processedPlayers: any[] = [];

            for (const player of players) {
                const playerId = player.id;
                // FUENTE DE VERDAD: Chips en la mesa
                const finalStack = Number(player.chips) || 0;

                const userInfo = userMap.get(playerId);
                if (!userInfo) continue;

                // 1. Devolución ÍNTEGRA (Tax-Free)
                transaction.update(userInfo.ref, {
                    credit: admin.firestore.FieldValue.increment(finalStack),
                    moneyInPlay: 0,
                    currentTableId: null,
                    lastUpdated: timestamp
                });

                // 2. Cerrar sesiones
                const sessions = sessionsByUser.get(playerId) || [];
                let initialBuyIn = 0;
                if (sessions.length > 0) {
                    sessions.sort((a, b) => (b.data.startTime?.toMillis() || 0) - (a.data.startTime?.toMillis() || 0));
                    initialBuyIn = Number(sessions[0].data.buyInAmount) || 0;
                } else {
                    initialBuyIn = Number(tableData?.minBuyIn) || 0;
                }
                const netResult = finalStack - initialBuyIn;

                sessions.forEach((session, idx) => {
                    transaction.update(session.ref, {
                        status: 'completed',
                        currentChips: idx === 0 ? finalStack : 0,
                        netResult: idx === 0 ? netResult : 0,
                        endTime: timestamp,
                        closedReason: 'table_settlement'
                    });
                });

                // 3. Ledger de Cierre
                const ledgerRef = db.collection('financial_ledger').doc();
                transaction.set(ledgerRef, {
                    type: 'SESSION_END',
                    userId: playerId,
                    userName: userInfo.data.displayName || 'Unknown',
                    tableId: tableId,
                    amount: finalStack,
                    netAmount: finalStack,
                    netProfit: netResult,
                    grossAmount: finalStack,
                    rakePaid: 0, // YA SE PAGÓ EN CADA MANO
                    buyInAmount: initialBuyIn,
                    timestamp: timestamp,
                    description: `Cierre Mesa (Tax-Free) - Retorno: ${finalStack}`
                });

                processedPlayers.push({ userId: playerId, finalStack });
            }

            // Cerrar la mesa
            transaction.update(tableRef, {
                players: players.map((p: any) => ({ ...p, chips: 0, inGame: false })),
                status: 'FINISHED',
                lastUpdated: timestamp
            });

            return { success: true, players: processedPlayers };
        });

        return result;

    } catch (error: any) {
        console.error('[UNIVERSAL_SETTLEMENT] Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
};



/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 5. DISTRIBUTE HAND RAKE - Distribución de Rake por Mano (IDEMPOTENTE)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * Called by the game server after each hand to distribute rake to:
 * - Platform (always)
 * - Club (if public table and player has club)
 * - Seller (if public table and player has seller)
 * 
 * RULE: Private tables → 100% to Platform
 * RULE: Public tables → 50% Platform / 30% Club / 20% Seller
 * 
 * 🔒 IDEMPOTENCY: Uses deterministic doc ID `rake_${tableId}_${handId}`
 *    to prevent duplicate processing. Transaction-based duplicate detection.
 */
export const distributeHandRake = functions.https.onCall(async (data, context) => {
    // v1 onCall recibe (data, context) directamente
    // const data = request.data; // v2 style removed

    // Validar autenticación si es necesario (opcional para server-to-server si se usa admin sdk, pero onCall requiere auth context usualmente)
    // Si el Game Server llama sin auth user, onCall puede fallar si se espera context.auth.
    // Pero el Game Server suele tener credenciales.
    // Para simplificar y mantener compatibilidad con la llamada anterior (que era onRequest),
    // si el cliente cambió a onCall, enviará el formato correcto.

    const db = getDb();

    // Validaciones básicas
    if (!data.tableId || !data.handId || typeof data.rakeTotal !== 'number') {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required data parameters');
    }

    const ledgerId = `rake_${data.tableId}_${data.handId}`;
    const ledgerRef = db.collection('financial_ledger').doc(ledgerId);
    const treasuryRef = db.collection('users').doc(TREASURY_ADMIN_UID);

    try {
        await db.runTransaction(async (transaction) => {
            // 1. 🔒 IDEMPOTENCIA: Si ya cobramos esta mano, abortar silenciosamente.
            const doc = await transaction.get(ledgerRef);
            if (doc.exists) {
                console.log(`[IDEMPOTENCY] Rake for hand ${data.handId} already processed.`);
                return;
            }

            // 2. 🧮 CALCULAR SHARE (100% Plataforma en Privadas, Split en Públicas)
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (data.isPrivate === true) {
                platformShare = data.rakeTotal;
            } else {
                platformShare = Math.floor(data.rakeTotal * 0.50);
                clubShare = Math.floor(data.rakeTotal * 0.30);
                sellerShare = data.rakeTotal - platformShare - clubShare;
            }

            // 3. 💸 EJECUTAR TRANSFERENCIA AL ADMIN (TESORERÍA)
            if (platformShare > 0) {
                transaction.update(treasuryRef, {
                    credit: admin.firestore.FieldValue.increment(platformShare)
                });
            }

            // 4. 📝 REGISTRAR EN EL LEDGER (Consolidado)
            transaction.set(ledgerRef, {
                type: 'RAKE_COLLECTED',
                amount: data.rakeTotal,
                breakdown: {
                    platform: platformShare,
                    club: clubShare,
                    seller: sellerShare
                },
                tableId: data.tableId,
                handId: data.handId,
                isPrivate: !!data.isPrivate,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
                treasuryUid: TREASURY_ADMIN_UID // Referencia cruzada
            });

            // (Opcional) Aquí agregarías la lógica para pagar al Club/Seller si corresponde
            // Mantenemos la lógica existente para Club y Seller si están presentes en data
            if (clubShare > 0 && data.clubId) {
                const clubRef = db.collection('clubs').doc(data.clubId);
                transaction.set(clubRef, {
                    walletBalance: admin.firestore.FieldValue.increment(clubShare),
                    totalRakeEarned: admin.firestore.FieldValue.increment(clubShare)
                }, { merge: true });
            }

            if (sellerShare > 0 && data.sellerId) {
                const sellerRef = db.collection('users').doc(data.sellerId);
                transaction.update(sellerRef, {
                    credit: admin.firestore.FieldValue.increment(sellerShare),
                    commissionEarned: admin.firestore.FieldValue.increment(sellerShare)
                });
            }
        });

        return { success: true, message: "Rake processed and transferred to Treasury." };

    } catch (error) {
        console.error("❌ Error processing rake transaction:", error);
        throw new functions.https.HttpsError('internal', 'Transaction failed');
    }
});

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 6. DISTRIBUTE POT - UNIFIED ATOMIC POT DISTRIBUTION (IDEMPOTENT)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * 🔒 CRITICAL SECURITY FIX: This function prevents race conditions and double payments.
 * 
 * FEATURES:
 * 1. IDEMPOTENCY: Uses `hands/{handId}` document with `status: 'DISTRIBUTED'` to prevent re-processing
 * 2. ATOMIC: All operations in single Firestore transaction (all-or-nothing)
 * 3. RAKE: 8% of pot (capped at 50), distributed according to table type
 * 4. WINNER CHIPS: Updated in `poker_tables/{tableId}/players[].chips` (NOT in wallet)
 * 
 * BUSINESS RULES:
 * - Rake = 8% of Total Pot (max 50)
 * - Private Table: 100% Platform
 * - Public Table: 50% Platform / 30% Club / 20% Seller (if missing, goes to platform)
 * 
 * WORKFLOW:
 * 1. Check if hand already distributed → abort if yes
 * 2. Calculate rake and netPot
 * 3. Transfer rake to Treasury/Club/Seller wallets
 * 4. Update winner's chips in table document
 * 5. Mark hand as DISTRIBUTED
 * 
 * @param data.handId - Unique hand identifier (REQUIRED for idempotency)
 * @param data.tableId - Table document ID
 * @param data.potTotal - Total pot amount before rake
 * @param data.winnerUid - Winner's Firebase UID
 * @param data.winnerSeatIndex - Winner's seat index in players array (for chip update)
 * @param data.isPrivate - true for private tables (100% platform rake)
 * @param data.clubId - Optional club ID for rake distribution
 * @param data.sellerId - Optional seller ID for rake distribution
 */
interface DistributePotRequest {
    handId: string;
    tableId: string;
    potTotal: number;
    winnerUid: string;
    winnerSeatIndex?: number; // Optional: if provided, updates chips at this index
    isPrivate: boolean;
    clubId?: string;
    sellerId?: string;
    // For split pots (multiple winners)
    winners?: Array<{
        uid: string;
        seatIndex: number;
        amount: number; // Net amount after rake split
    }>;
    rakeAmount?: number;   // [NEW] Exact rake amount calculated by server
    winnerAmount?: number; // [NEW] Exact winner amount calculated by server
}

export const distributePot = functions.https.onCall(async (data: DistributePotRequest, context) => {
    const db = getDb();

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION
    // ═══════════════════════════════════════════════════════════════════════
    if (!data.handId || !data.tableId || typeof data.potTotal !== 'number') {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters: handId, tableId, potTotal');
    }

    if (data.potTotal <= 0) {
        console.log(`[DISTRIBUTE_POT] ⚠️ Pot is ${data.potTotal}. Nothing to distribute.`);
        return { success: true, skipped: true, reason: 'zero_pot' };
    }

    console.log(`[DISTRIBUTE_POT] 🎯 Processing hand ${data.handId} | Pot: ${data.potTotal} | Winner: ${data.winnerUid}`);

    // ═══════════════════════════════════════════════════════════════════════
    // REFERENCES
    // ═══════════════════════════════════════════════════════════════════════
    const handRef = db.collection('hands').doc(data.handId);
    const tableRef = db.collection('poker_tables').doc(data.tableId);
    const treasuryRef = db.collection('users').doc(TREASURY_ADMIN_UID);
    const ledgerId = `pot_${data.tableId}_${data.handId}`;
    const ledgerRef = db.collection('financial_ledger').doc(ledgerId);

    try {
        const result = await db.runTransaction(async (transaction) => {
            // ═══════════════════════════════════════════════════════════════
            // 1. 🔒 IDEMPOTENCY CHECK - Prevent double distribution
            // ═══════════════════════════════════════════════════════════════
            const handDoc = await transaction.get(handRef);
            if (handDoc.exists && handDoc.data()?.status === 'DISTRIBUTED') {
                console.log(`[DISTRIBUTE_POT] ⚠️ Hand ${data.handId} already DISTRIBUTED. Aborting (idempotency).`);
                return { success: true, skipped: true, reason: 'already_distributed' };
            }

            // Also check ledger for extra safety
            const ledgerDoc = await transaction.get(ledgerRef);
            if (ledgerDoc.exists) {
                console.log(`[DISTRIBUTE_POT] ⚠️ Ledger entry ${ledgerId} already exists. Aborting (idempotency).`);
                return { success: true, skipped: true, reason: 'ledger_exists' };
            }

            // ═══════════════════════════════════════════════════════════════
            // 2. Read table to find winner's seat index
            // ═══════════════════════════════════════════════════════════════
            const tableDoc = await transaction.get(tableRef);
            if (!tableDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Table ${data.tableId} not found`);
            }

            const tableData = tableDoc.data();
            const players: any[] = Array.isArray(tableData?.players) ? tableData.players : [];

            // ═══════════════════════════════════════════════════════════════
            // 3. 🧮 CALCULATE RAKE (8% capped at 50) OR USE PROVIDED
            // ═══════════════════════════════════════════════════════════════
            const RAKE_PERCENTAGE = 0.08;
            const MAX_RAKE_CAP = 50;

            let rakeAmount = 0;

            if (data.rakeAmount !== undefined) {
                // TRUST THE SERVER (No Flop No Drop rule applied there)
                rakeAmount = data.rakeAmount;
                console.log(`[DISTRIBUTE_POT] 🛡️ Using provided rake amount: ${rakeAmount}`);
            } else {
                // Fallback calculation
                rakeAmount = Math.min(Math.floor(data.potTotal * RAKE_PERCENTAGE), MAX_RAKE_CAP);
            }

            const netPot = data.potTotal - rakeAmount;

            console.log(`[DISTRIBUTE_POT] 💰 Pot: ${data.potTotal} | Rake: ${rakeAmount} (8%, cap 50) | Net: ${netPot}`);

            // ═══════════════════════════════════════════════════════════════
            // 4. 📊 CALCULATE RAKE DISTRIBUTION
            // ═══════════════════════════════════════════════════════════════
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;

            if (data.isPrivate === true) {
                // PRIVATE TABLE: 100% to Platform
                platformShare = rakeAmount;
                console.log(`[DISTRIBUTE_POT] 🔒 Private table: 100% (${platformShare}) to platform`);
            } else {
                // PUBLIC TABLE: 50% Platform / 30% Club / 20% Seller
                platformShare = Math.floor(rakeAmount * 0.50);

                if (data.clubId) {
                    clubShare = Math.floor(rakeAmount * 0.30);
                } else {
                    // No club → 30% goes to platform
                    platformShare += Math.floor(rakeAmount * 0.30);
                }

                if (data.sellerId) {
                    sellerShare = Math.floor(rakeAmount * 0.20);
                } else {
                    // No seller → 20% goes to platform
                    platformShare += Math.floor(rakeAmount * 0.20);
                }

                // Handle rounding (remaining centavos go to platform)
                const allocated = platformShare + clubShare + sellerShare;
                if (allocated < rakeAmount) {
                    platformShare += (rakeAmount - allocated);
                }

                console.log(`[DISTRIBUTE_POT] 🌐 Public table: Platform=${platformShare}, Club=${clubShare}, Seller=${sellerShare}`);
            }

            // ═══════════════════════════════════════════════════════════════
            // 5. 💸 TRANSFER RAKE TO WALLETS
            // ═══════════════════════════════════════════════════════════════

            // A. Platform (Treasury)
            if (platformShare > 0) {
                transaction.update(treasuryRef, {
                    credit: admin.firestore.FieldValue.increment(platformShare),
                    totalRakeReceived: admin.firestore.FieldValue.increment(platformShare),
                    lastRakeReceived: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[DISTRIBUTE_POT] 💵 Treasury receives: ${platformShare}`);
            }

            // B. Club
            if (clubShare > 0 && data.clubId) {
                const clubRef = db.collection('clubs').doc(data.clubId);
                transaction.set(clubRef, {
                    walletBalance: admin.firestore.FieldValue.increment(clubShare),
                    totalRakeEarned: admin.firestore.FieldValue.increment(clubShare),
                    lastRakeReceived: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
                console.log(`[DISTRIBUTE_POT] 🏠 Club ${data.clubId} receives: ${clubShare}`);
            }

            // C. Seller
            if (sellerShare > 0 && data.sellerId) {
                const sellerRef = db.collection('users').doc(data.sellerId);
                transaction.update(sellerRef, {
                    credit: admin.firestore.FieldValue.increment(sellerShare),
                    commissionEarned: admin.firestore.FieldValue.increment(sellerShare),
                    lastCommissionReceived: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[DISTRIBUTE_POT] 👤 Seller ${data.sellerId} receives: ${sellerShare}`);
            }

            // ═══════════════════════════════════════════════════════════════
            // 6. 🏆 UPDATE WINNER'S CHIPS IN TABLE
            //    CRITICAL: We update chips, NOT credit (wallet)
            // ═══════════════════════════════════════════════════════════════

            if (data.winners && data.winners.length > 0) {
                // SPLIT POT: Multiple winners
                for (const winner of data.winners) {
                    const winnerIndex = winner.seatIndex ?? players.findIndex((p: any) =>
                        p.uid === winner.uid || p.id === winner.uid
                    );

                    if (winnerIndex !== -1) {
                        transaction.update(tableRef, {
                            [`players.${winnerIndex}.chips`]: admin.firestore.FieldValue.increment(winner.amount)
                        });
                        console.log(`[DISTRIBUTE_POT] 🏆 Winner ${winner.uid} (seat ${winnerIndex}): +${winner.amount} chips`);
                    } else {
                        console.warn(`[DISTRIBUTE_POT] ⚠️ Winner ${winner.uid} not found in table. Skipping chip update.`);
                    }
                }
            } else if (data.winnerUid) {
                // SINGLE WINNER
                let winnerIndex = data.winnerSeatIndex;

                if (winnerIndex === undefined) {
                    // Find winner in players array
                    winnerIndex = players.findIndex((p: any) =>
                        p.uid === data.winnerUid || p.id === data.winnerUid
                    );
                }

                if (winnerIndex !== -1) {
                    transaction.update(tableRef, {
                        [`players.${winnerIndex}.chips`]: admin.firestore.FieldValue.increment(netPot)
                    });
                    console.log(`[DISTRIBUTE_POT] 🏆 Winner ${data.winnerUid} (seat ${winnerIndex}): +${netPot} chips`);
                } else {
                    console.warn(`[DISTRIBUTE_POT] ⚠️ Winner ${data.winnerUid} not found in table. Skipping chip update.`);
                    // Still continue with rake distribution and hand marking
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // 7. 📝 CREATE LEDGER ENTRY (Audit Trail)
            // ═══════════════════════════════════════════════════════════════
            transaction.set(ledgerRef, {
                type: 'POT_DISTRIBUTED',
                handId: data.handId,
                tableId: data.tableId,
                potTotal: data.potTotal,
                rakeAmount: rakeAmount,
                netPotDistributed: netPot,
                winnerUid: data.winnerUid || null,
                winners: data.winners || null,
                isPrivate: !!data.isPrivate,
                rakeBreakdown: {
                    platform: platformShare,
                    club: clubShare,
                    seller: sellerShare
                },
                clubId: data.clubId || null,
                sellerId: data.sellerId || null,
                treasuryUid: TREASURY_ADMIN_UID,
                processedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // ═══════════════════════════════════════════════════════════════
            // 8. 🔒 MARK HAND AS DISTRIBUTED (Idempotency Lock)
            // ═══════════════════════════════════════════════════════════════
            transaction.set(handRef, {
                status: 'DISTRIBUTED',
                tableId: data.tableId,
                potTotal: data.potTotal,
                rakeCollected: rakeAmount,
                netPotDistributed: netPot,
                winnerUid: data.winnerUid || null,
                distributedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // ═══════════════════════════════════════════════════════════════
            // 9. 📊 UPDATE SYSTEM STATS
            // ═══════════════════════════════════════════════════════════════
            transaction.set(db.collection('system_stats').doc('economy'), {
                accumulated_rake: admin.firestore.FieldValue.increment(rakeAmount),
                total_volume: admin.firestore.FieldValue.increment(data.potTotal),
                hands_played: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // Daily stats
            const dateKey = new Date().toISOString().split('T')[0];
            transaction.set(db.collection('stats_daily').doc(dateKey), {
                dateKey,
                totalVolume: admin.firestore.FieldValue.increment(data.potTotal),
                totalRake: admin.firestore.FieldValue.increment(rakeAmount),
                handsPlayed: admin.firestore.FieldValue.increment(1),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            console.log(`[DISTRIBUTE_POT] ✅ Successfully distributed pot for hand ${data.handId}`);

            return {
                success: true,
                skipped: false,
                handId: data.handId,
                potTotal: data.potTotal,
                rakeAmount: rakeAmount,
                netPotDistributed: netPot,
                rakeBreakdown: { platform: platformShare, club: clubShare, seller: sellerShare }
            };
        });

        return result;

    } catch (error: any) {
        console.error(`[DISTRIBUTE_POT] ❌ CRITICAL ERROR:`, error);
        throw error instanceof functions.https.HttpsError
            ? error
            : new functions.https.HttpsError('internal', error.message);
    }
});

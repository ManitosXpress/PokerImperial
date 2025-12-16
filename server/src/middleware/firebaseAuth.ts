import * as admin from 'firebase-admin';
import * as path from 'path';
import * as fs from 'fs';

// Initialize Firebase Admin
// Check if serviceAccountKey.json exists
const serviceAccountPath = path.join(__dirname, '../../serviceAccountKey.json');

if (fs.existsSync(serviceAccountPath)) {
    try {
        if (!admin.apps.length) {
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccountPath)
            });
            console.log('Firebase Admin initialized successfully');
        }
    } catch (error) {
        console.error('Error initializing Firebase Admin:', error);
    }
} else {
    console.warn('WARNING: serviceAccountKey.json not found in server root. Firebase features will not work.');
}

export async function verifyFirebaseToken(token: string): Promise<string | null> {
    if (!admin.apps.length) {
        console.error('Firebase Admin not initialized');
        return null;
    }

    try {
        const decodedToken = await admin.auth().verifyIdToken(token);
        const uid = decodedToken.uid;
        const db = admin.firestore();
        const userRef = db.collection('users').doc(uid);

        // Check if user exists, if not create
        const userDoc = await userRef.get();

        if (!userDoc.exists) {
            // Fetch latest user data from Auth to ensure we get the updated displayName
            let displayName = decodedToken.name || 'Player';
            try {
                const userRecord = await admin.auth().getUser(uid);
                if (userRecord.displayName) {
                    displayName = userRecord.displayName;
                }
            } catch (e) {
                console.warn('Could not fetch user record for displayName update:', e);
            }

            const now = admin.firestore.FieldValue.serverTimestamp();

            const userData = {
                uid: uid,
                email: decodedToken.email || '',
                displayName: displayName,
                photoURL: decodedToken.picture || '',
                credit: 0, // New users start with 0 credits - no welcome bonus
                createdAt: now,
                lastLogin: now
            };

            await userRef.set(userData);

            // No initial transaction - users start with 0 credits
            // Credits must be added explicitly via Admin or Bot

            console.log(`Created new user ${uid} with 0 credits (no welcome bonus)`);
        } else {
            // Update last login only - no automatic refills
            await userRef.update({
                lastLogin: admin.firestore.FieldValue.serverTimestamp()
            });
        }

        return uid;
    } catch (error: any) {
        console.error('[VERIFY_TOKEN] ❌ Error verificando token:', error);
        console.error('[VERIFY_TOKEN] ❌ Mensaje:', error.message);
        console.error('[VERIFY_TOKEN] ❌ Código:', error.code);
        // No lanzar error - solo retornar null para que el cliente pueda manejar
        return null;
    }
}

export async function getUserBalance(uid: string): Promise<number> {
    if (!admin.apps.length) return 0;

    try {
        const userDoc = await admin.firestore().collection('users').doc(uid).get();
        return userDoc.data()?.credit || 0; // Changed from walletBalance to credit
    } catch (error) {
        console.error('Error getting balance:', error);
        return 0;
    }
}

export async function reservePokerSession(uid: string, amount: number, roomId: string): Promise<string | null> {
    if (!admin.apps.length) {
        console.error('[RESERVE_SESSION] ❌ Firebase Admin not initialized');
        return null;
    }

    const db = admin.firestore();

    console.log(`[RESERVE_SESSION] 🎯 Iniciando reserva de sesión: usuario=${uid}, mesa=${roomId}, amount=${amount}`);

    try {
        // VALIDACIÓN CRÍTICA: Rechazar 'new_room' o roomId inválido
        if (!roomId || roomId === 'new_room' || roomId.trim() === '') {
            console.error(`[RESERVE_SESSION] ❌ BLOCKED: Invalid Room ID: "${roomId}"`);
            throw new Error('Invalid Room ID. Cannot reserve session with placeholder ID.');
        }

        // PARTE 1: IDEMPOTENCIA - Verificación inicial (rápida, pero no atómica)
        // Esta verificación es una optimización para evitar transacciones innecesarias.
        // La protección real está DENTRO de la transacción.
        const existingSessionQuery = await db.collection('poker_sessions')
            .where('userId', '==', uid)
            .where('roomId', '==', roomId)
            .where('status', '==', 'active')
            .limit(1)
            .get();

        if (!existingSessionQuery.empty) {
            const existingId = existingSessionQuery.docs[0].id;
            console.log(`[IDEMPOTENCY] User ${uid} already has active session ${existingId} in room ${roomId}. Returning existing.`);

            // Actualizar lastActive para mantener la sesión viva
            await db.collection('poker_sessions').doc(existingId).update({
                lastActive: admin.firestore.FieldValue.serverTimestamp()
            });

            return existingId;
        }

        // PARTE 2: TRANSACCIÓN ATÓMICA - Verificación + Creación
        const result = await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(uid);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error('User not found');
            }

            const userData = userDoc.data();
            const currentBalance = userData?.credit || 0;
            const currentTableId = userData?.currentTableId;
            const moneyInPlay = userData?.moneyInPlay || 0;

            // VERIFICACIÓN CRÍTICA DENTRO DE LA TRANSACCIÓN
            // CASO 1: Usuario ya está en ESTA MISMA sala
            if (currentTableId === roomId) {
                console.log(`[IDEMPOTENCY] User ${uid} already registered in room ${roomId} (currentTableId check). Signaling to find existing session.`);
                return { type: 'existing_same_room', sessionId: null };
            }

            // CASO 2: Usuario tiene dinero en juego pero en OTRA sala (estado sucio/stuck)
            // Esto puede pasar si el settlement no limpió correctamente
            if (moneyInPlay > 0 && currentTableId && currentTableId !== roomId) {
                console.warn(`[IDEMPOTENCY] ⚠️ User ${uid} has stuck state: moneyInPlay=${moneyInPlay}, currentTableId=${currentTableId}. Auto-cleaning...`);

                // Buscar y cerrar sesiones huérfanas en la mesa anterior
                // NOTA: No podemos hacer queries en transacciones, así que solo limpiamos el usuario
                transaction.update(userRef, {
                    moneyInPlay: 0,
                    currentTableId: null,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });

                console.log(`[IDEMPOTENCY] Auto-cleaned stuck state for user ${uid}. Proceeding with new session.`);
                // Continuar con la creación de sesión normal - el balance no cambia
            } else if (moneyInPlay > 0 && !currentTableId) {
                // Dinero en juego pero sin mesa asignada - estado corrupto
                console.warn(`[IDEMPOTENCY] ⚠️ User ${uid} has moneyInPlay=${moneyInPlay} but no currentTableId. Cleaning corrupt state.`);
                transaction.update(userRef, {
                    moneyInPlay: 0,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            if (currentBalance < amount) {
                throw new Error('Insufficient balance');
            }

            // Crear nueva sesión - Usuario está limpio o fue limpiado
            const sessionRef = db.collection('poker_sessions').doc();
            const newSessionId = sessionRef.id;

            // Deducir balance y marcar estado
            transaction.update(userRef, {
                credit: currentBalance - amount,
                moneyInPlay: amount,
                currentTableId: roomId,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Crear documento de sesión
            transaction.set(sessionRef, {
                userId: uid,
                roomId: roomId,
                buyInAmount: amount,
                currentChips: amount,
                startTime: admin.firestore.FieldValue.serverTimestamp(),
                lastActive: admin.firestore.FieldValue.serverTimestamp(),
                status: 'active',
                totalRakePaid: 0
            });

            const timestamp = admin.firestore.FieldValue.serverTimestamp();
            const newBalance = currentBalance - amount;

            // Registro en sub-colección de transacciones
            const transactionRef = userRef.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'poker_buyin',
                amount: -amount,
                reason: `Poker Room Buy-in: ${roomId}`,
                sessionId: newSessionId,
                timestamp: timestamp
            });

            // Registro en colección principal de logs
            const logRef = db.collection('transaction_logs').doc();
            transaction.set(logRef, {
                userId: uid,
                amount: -amount,
                type: 'debit',
                reason: `Poker Room Buy-in: ${roomId}`,
                timestamp: timestamp,
                beforeBalance: currentBalance,
                afterBalance: newBalance,
                metadata: {
                    sessionId: newSessionId,
                    roomId: roomId,
                    buyInAmount: amount
                }
            });

            console.log(`[NEW_SESSION] Created session ${newSessionId} for user ${uid} in room ${roomId}`);
            return { type: 'new', sessionId: newSessionId };
        });

        // PARTE 3: MANEJO DE RESULTADO
        if (result.type === 'new') {
            console.log(`Reserved poker session ${result.sessionId} for user ${uid} in room ${roomId}`);
            return result.sessionId;
        }

        // Usuario ya estaba en ESTA MISMA mesa - buscar sesión existente
        if (result.type === 'existing_same_room') {
            console.log(`[IDEMPOTENCY] Transaction detected user in same room. Searching for active session...`);
            const retryQuery = await db.collection('poker_sessions')
                .where('userId', '==', uid)
                .where('roomId', '==', roomId)
                .where('status', '==', 'active')
                .orderBy('startTime', 'desc')
                .limit(1)
                .get();

            if (!retryQuery.empty) {
                const existingId = retryQuery.docs[0].id;
                console.log(`[IDEMPOTENCY] Found existing session ${existingId} for user ${uid}`);

                // Actualizar lastActive
                await db.collection('poker_sessions').doc(existingId).update({
                    lastActive: admin.firestore.FieldValue.serverTimestamp()
                });

                return existingId;
            }

            console.error(`[IDEMPOTENCY] User ${uid} marked as in room ${roomId} but no session found. Possible data corruption.`);
            return null;
        }

        // No debería llegar aquí
        return result.sessionId;

    } catch (error: any) {
        console.error(`[RESERVE_SESSION] ❌ Error reservando sesión:`, error);
        console.error(`[RESERVE_SESSION] ❌ Mensaje: ${error.message}`);
        console.error(`[RESERVE_SESSION] ❌ Stack: ${error.stack}`);
        return null;
    }
}



/**
 * Helper function to call Cloud Function joinTable from server
 * This ensures server uses the same logic as Cloud Functions (single source of truth)
 * 
 * IMPORTANTE: Esta función ahora es un wrapper que llama a la Cloud Function.
 * La creación real de sesiones se hace en functions/src/functions/table.ts
 * 
 * NOTA: Para producción, esta función debe hacer una llamada HTTP a la Cloud Function.
 * Para desarrollo local, puede importar directamente la función si está en el mismo proyecto.
 */
/**
 * ✅ CORREGIDO: Usa reservePokerSession directamente (sin llamada HTTP)
 * 
 * PROBLEMA RESUELTO: Las Cloud Functions callable requieren ID token de usuario,
 * no custom token. La llamada HTTP fallaba con error 401 (Unauthenticated).
 * 
 * SOLUCIÓN: Usar reservePokerSession directamente, que tiene la misma lógica
 * de negocio que joinTable pero ejecuta en el servidor con Admin SDK.
 * 
 * NOTA: reservePokerSession ya tiene:
 * - Idempotencia (verifica sesiones existentes)
 * - Transacciones atómicas
 * - Validaciones de balance y estado
 * - Misma lógica que joinTable pero adaptada para servidor
 */
export async function callJoinTableFunction(uid: string, roomId: string, buyInAmount: number): Promise<string | null> {
    if (!admin.apps.length) {
        console.error('[CALL_JOIN_TABLE] ❌ Firebase Admin not initialized');
        return null;
    }

    // Usar reservePokerSession directamente
    // Esta función tiene la misma lógica que joinTable pero ejecuta en el servidor
    console.log(`[CALL_JOIN_TABLE] 📞 Ejecutando reservePokerSession para usuario ${uid}, mesa ${roomId}, buyIn ${buyInAmount}`);
    
    try {
        const sessionId = await reservePokerSession(uid, buyInAmount, roomId);
        if (sessionId) {
            console.log(`[CALL_JOIN_TABLE] ✅ Sesión creada exitosamente: ${sessionId}`);
        } else {
            console.error(`[CALL_JOIN_TABLE] ❌ reservePokerSession retornó null (sin error lanzado)`);
        }
        return sessionId;
    } catch (error: any) {
        console.error(`[CALL_JOIN_TABLE] ❌ Error en reservePokerSession:`, error);
        console.error(`[CALL_JOIN_TABLE] ❌ Stack trace:`, error.stack);
        return null;
    }
}

/**
 * ✅ MIGRADO: Llama a processCashOut Cloud Function
 * 
 * Esta función ahora delega a processCashOutFunction vía HTTP,
 * asegurando que la lógica de cashout esté centralizada
 * en functions/src/functions/table.ts
 * 
 * @deprecated Mantiene compatibilidad pero ahora llama a Cloud Function
 */
export async function endPokerSession(uid: string, sessionId: string, finalChips: number, totalRake: number, exitFee: number = 0): Promise<boolean> {
    if (!admin.apps.length) {
        console.error('[END_POKER_SESSION] Firebase Admin not initialized');
        return false;
    }

    // Obtener roomId de la sesión para llamar a processCashOut
    const db = admin.firestore();
    let roomId: string | null = null;
    
    try {
        const sessionDoc = await db.collection('poker_sessions').doc(sessionId).get();
        if (sessionDoc.exists) {
            roomId = sessionDoc.data()?.roomId || null;
        }
    } catch (error) {
        console.error('[END_POKER_SESSION] Error obteniendo roomId:', error);
    }

    if (!roomId) {
        console.error('[END_POKER_SESSION] No se pudo obtener roomId de la sesión');
        // Fallback a implementación antigua
        return await endPokerSessionLegacy(uid, sessionId, finalChips, totalRake, exitFee);
    }

    // Intentar llamar a Cloud Function processCashOut
    const projectId = admin.app().options.projectId || 'poker-fa33a';
    const region = process.env.FUNCTIONS_REGION || 'us-central1';
    const functionUrl = process.env.FUNCTIONS_URL || `https://${region}-${projectId}.cloudfunctions.net/processCashOutFunction`;

    try {
        console.log(`[END_POKER_SESSION] 📞 Llamando a Cloud Function: ${functionUrl}`);
        
        const customToken = await admin.auth().createCustomToken(uid);
        
        const response = await fetch(functionUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${customToken}`
            },
            body: JSON.stringify({
                data: {
                    tableId: roomId,
                    userId: uid,
                    playerChips: finalChips
                }
            })
        });

        if (response.ok) {
            const result = await response.json();
            if (result.result && result.result.success) {
                console.log(`[END_POKER_SESSION] ✅ Cashout procesado vía Cloud Function`);
                return true;
            }
        } else {
            const errorText = await response.text();
            console.warn(`[END_POKER_SESSION] ⚠️ HTTP Error ${response.status}: ${errorText}`);
        }
    } catch (httpError: any) {
        console.warn(`[END_POKER_SESSION] ⚠️ Error en llamada HTTP: ${httpError.message}`);
    }

    // FALLBACK: Si la llamada HTTP falla, usar implementación legacy
    console.log(`[END_POKER_SESSION] 🔄 Usando fallback: implementación legacy`);
    return await endPokerSessionLegacy(uid, sessionId, finalChips, totalRake, exitFee);
}

/**
 * Implementación legacy de endPokerSession (mantenida como fallback)
 * @private
 */
async function endPokerSessionLegacy(uid: string, sessionId: string, finalChips: number, totalRake: number, exitFee: number = 0): Promise<boolean> {
    if (!admin.apps.length) return false;

    const db = admin.firestore();

    try {
        await db.runTransaction(async (transaction) => {
            const sessionRef = db.collection('poker_sessions').doc(sessionId);
            const userRef = db.collection('users').doc(uid);

            const sessionDoc = await transaction.get(sessionRef);
            if (!sessionDoc.exists) {
                throw new Error('Session not found');
            }

            const sessionData = sessionDoc.data();
            if (sessionData?.status !== 'active') {
                // Already closed, maybe duplicate call
                console.log(`Session ${sessionId} already closed. Status: ${sessionData?.status}`);
                return;
            }

            const roomId = sessionData?.roomId;

            // ════════════════════════════════════════════════════════════════════════
            // CRÍTICO: LEER FICHAS DESDE FIRESTORE (ÚNICA FUENTE DE VERDAD)
            // No confiar en finalChips del servidor que puede estar desactualizado
            // ════════════════════════════════════════════════════════════════════════
            let actualFinalChips = finalChips; // Fallback al parámetro

            if (roomId) {
                const tableRef = db.collection('poker_tables').doc(roomId);
                const tableDoc = await transaction.get(tableRef);

                if (tableDoc.exists) {
                    const tableData = tableDoc.data();
                    const players = Array.isArray(tableData?.players) ? tableData.players : [];
                    const playerInTable = players.find((p: any) => p.id === uid || p.uid === uid);

                    if (playerInTable) {
                        actualFinalChips = Number(playerInTable.chips) || 0;
                        console.log(`[CASHOUT] ✅ Fichas leídas de Firestore: ${actualFinalChips} (servidor reportó: ${finalChips})`);
                    } else {
                        console.warn(`[CASHOUT] ⚠️ Jugador ${uid} no encontrado en mesa ${roomId}, usando valor del servidor: ${finalChips}`);
                    }
                }
            }

            // Obtener datos del usuario (incluyendo displayName)
            const userDoc = await transaction.get(userRef);
            const userData = userDoc.data();
            const displayName = userData?.displayName || 'Unknown';

            // Obtener buy-in original de la sesión
            const buyInAmount = Number(sessionData?.buyInAmount) || 0;

            // Calcular monto neto (fichas finales - exit fee)
            const netWinnings = Math.max(0, actualFinalChips - exitFee);

            // Calcular ganancia/pérdida vs buy-in
            const netProfit = netWinnings - buyInAmount;

            console.log(`[CASHOUT] Usuario: ${uid} (${displayName}), Sesión: ${sessionId}`);
            console.log(`[CASHOUT] Fichas finales (Firestore): ${actualFinalChips}`);
            console.log(`[CASHOUT] Buy-in original: ${buyInAmount}`);
            console.log(`[CASHOUT] Exit fee: ${exitFee}`);
            console.log(`[CASHOUT] Rake pagado: ${totalRake}`);
            console.log(`[CASHOUT] Monto neto a transferir: ${netWinnings}`);
            console.log(`[CASHOUT] Ganancia/Pérdida: ${netProfit > 0 ? '+' : ''}${netProfit}`);

            // Actualizar sesión
            transaction.update(sessionRef, {
                currentChips: actualFinalChips,
                totalRakePaid: totalRake,
                exitFee: exitFee,
                netResult: netWinnings,
                endTime: admin.firestore.FieldValue.serverTimestamp(),
                status: 'completed'
            });

            // CRÍTICO: LIMPIEZA DE ESTADO VISUAL OBLIGATORIA
            const userUpdate: any = {
                moneyInPlay: 0,
                currentTableId: null,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            };

            // Actualizar crédito del usuario
            if (netWinnings > 0) {
                userUpdate.credit = admin.firestore.FieldValue.increment(netWinnings);
                console.log(`[CASHOUT] Crédito actualizado: +${netWinnings} al saldo del usuario`);
            }

            transaction.update(userRef, userUpdate);
            console.log(`[CASHOUT] Limpieza visual aplicada: moneyInPlay=0, currentTableId=null`);

            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // Registrar rake en plataforma (si hay)
            if (totalRake > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(totalRake),
                    lastUpdated: timestamp
                }, { merge: true });
                console.log(`[CASHOUT] Rake registrado en plataforma: +${totalRake}`);
            }

            // ════════════════════════════════════════════════════════════════════════
            // LEDGER UNIFICADO: SESSION_END (en lugar de GAME_WIN/GAME_LOSS)
            // ════════════════════════════════════════════════════════════════════════
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: 'SESSION_END', // Tipo unificado
                userId: uid,
                userName: displayName,
                tableId: roomId || null,
                amount: netWinnings,      // Lo que recibe en su wallet
                profit: netProfit,        // Ganancia neta (puede ser negativo)
                grossAmount: actualFinalChips,
                buyInAmount: buyInAmount,
                rakePaid: totalRake,
                exitFee: exitFee,
                timestamp: timestamp,
                description: `Session ended. Final chips: ${actualFinalChips}, Buy-in: ${buyInAmount}, Net: ${netProfit > 0 ? '+' : ''}${netProfit}`
            });
            console.log(`[CASHOUT] Ledger SESSION_END creado`);

            // Registrar en transaction_logs para UI de wallet
            if (netWinnings > 0) {
                const transactionRef = userRef.collection('transactions').doc();
                transaction.set(transactionRef, {
                    type: 'poker_cashout',
                    amount: netWinnings,
                    reason: `Poker Cashout${netProfit >= 0 ? ' - Winner' : ' - Loss'}`,
                    sessionId: sessionId,
                    metadata: {
                        finalChips: actualFinalChips,
                        buyInAmount: buyInAmount,
                        netProfit: netProfit,
                        rakePaid: totalRake,
                        exitFee: exitFee
                    },
                    timestamp: timestamp
                });

                // Transaction log principal
                const logRef = db.collection('transaction_logs').doc();
                transaction.set(logRef, {
                    userId: uid,
                    amount: netWinnings,
                    type: 'credit',
                    reason: `Poker Cashout - ${roomId}`,
                    timestamp: timestamp,
                    beforeBalance: userData?.credit || 0,
                    afterBalance: (userData?.credit || 0) + netWinnings,
                    metadata: {
                        sessionId: sessionId,
                        tableId: roomId,
                        finalChips: actualFinalChips,
                        buyInAmount: buyInAmount,
                        profit: netProfit
                    }
                });
            }
        });

        console.log(`✅ Ended poker session ${sessionId} for user ${uid}. Chips from Firestore returned.`);
        return true;
    } catch (error) {
        console.error('❌ Error ending poker session:', error);
        return false;
    }
}

export async function addChipsToSession(uid: string, sessionId: string, amount: number): Promise<boolean> {
    if (!admin.apps.length) return false;

    const db = admin.firestore();

    try {
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(uid);
            const sessionRef = db.collection('poker_sessions').doc(sessionId);

            const userDoc = await transaction.get(userRef);
            const sessionDoc = await transaction.get(sessionRef);

            if (!userDoc.exists || !sessionDoc.exists) {
                throw new Error('User or Session not found');
            }

            if (sessionDoc.data()?.status !== 'active') {
                throw new Error('Session is not active');
            }

            const currentBalance = userDoc.data()?.credit || 0;

            if (currentBalance < amount) {
                throw new Error('Insufficient balance');
            }

            // Deduct from wallet
            transaction.update(userRef, {
                credit: currentBalance - amount,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Add to session
            const currentChips = sessionDoc.data()?.currentChips || 0;
            const currentBuyIn = sessionDoc.data()?.buyInAmount || 0;

            transaction.update(sessionRef, {
                currentChips: currentChips + amount,
                buyInAmount: currentBuyIn + amount,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            const timestamp = admin.firestore.FieldValue.serverTimestamp();
            const newBalance = currentBalance - amount;

            // Log transaction in sub-collection (for backward compatibility)
            const transactionRef = userRef.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'poker_topup',
                amount: -amount,
                reason: 'Poker Room Top-Up',
                sessionId: sessionId,
                timestamp: timestamp
            });

            // Record in transaction_logs (main collection for history)
            const logRef = db.collection('transaction_logs').doc();
            transaction.set(logRef, {
                userId: uid,
                amount: -amount, // Negative for debit
                type: 'debit',
                reason: 'Poker Room Top-Up',
                timestamp: timestamp,
                beforeBalance: currentBalance,
                afterBalance: newBalance,
                metadata: {
                    sessionId: sessionId,
                    topUpAmount: amount
                }
            });
        });

        console.log(`Added ${amount} chips to session ${sessionId} for user ${uid}`);
        return true;
    } catch (error) {
        console.error('Error adding chips to session:', error);
        return false;
    }
}

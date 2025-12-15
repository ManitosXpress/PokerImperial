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
    } catch (error) {
        console.error('Error verifying token:', error);
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
    if (!admin.apps.length) return null;

    const db = admin.firestore();

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

    } catch (error) {
        console.error('Error reserving poker session:', error);
        return null;
    }
}



export async function endPokerSession(uid: string, sessionId: string, finalChips: number, totalRake: number, exitFee: number = 0): Promise<boolean> {
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

            // Obtener datos del usuario (incluyendo displayName)
            const userDoc = await transaction.get(userRef);
            const userData = userDoc.data();
            const displayName = userData?.displayName || 'Unknown';

            // Obtener buy-in original de la sesión
            const buyInAmount = Number(sessionData?.buyInAmount) || 0;

            // Calcular monto neto (fichas finales - exit fee)
            const netWinnings = Math.max(0, finalChips - exitFee);

            // Calcular ganancia/pérdida vs buy-in
            const netProfit = netWinnings - buyInAmount;

            // Determinar tipo de transacción
            const ledgerType = netWinnings > buyInAmount ? 'GAME_WIN' : 'GAME_LOSS';

            console.log(`[CASHOUT] Usuario: ${uid} (${displayName}), Sesión: ${sessionId}`);
            console.log(`[CASHOUT] Fichas finales: ${finalChips}`);
            console.log(`[CASHOUT] Buy-in original: ${buyInAmount}`);
            console.log(`[CASHOUT] Exit fee: ${exitFee}`);
            console.log(`[CASHOUT] Rake pagado: ${totalRake}`);
            console.log(`[CASHOUT] Monto neto a transferir: ${netWinnings}`);
            console.log(`[CASHOUT] Ganancia/Pérdida: ${netProfit > 0 ? '+' : ''}${netProfit}`);
            console.log(`[CASHOUT] Tipo: ${ledgerType}`);

            // Actualizar sesión
            transaction.update(sessionRef, {
                currentChips: finalChips,
                totalRakePaid: totalRake,
                exitFee: exitFee,
                netResult: netWinnings, // Guardar resultado neto
                endTime: admin.firestore.FieldValue.serverTimestamp(),
                status: 'completed'
            });

            // CRÍTICO: LIMPIEZA DE ESTADO VISUAL OBLIGATORIA
            // Esto DEBE ejecutarse SIEMPRE, sin importar si tiene fichas o no
            // Separar la lógica: el cálculo de crédito depende de fichas, pero la limpieza es incondicional
            const userUpdate: any = {
                moneyInPlay: 0,  // Establecer explícitamente a 0 (no delete)
                currentTableId: null,  // Establecer explícitamente a null (no delete)
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            };

            // Actualizar crédito del usuario SOLO si tiene fichas para devolver
            if (netWinnings > 0) {
                userUpdate.credit = admin.firestore.FieldValue.increment(netWinnings);
                console.log(`[CASHOUT] Crédito actualizado: +${netWinnings} al saldo del usuario`);
            }

            // Ejecutar update con limpieza incondicional
            transaction.update(userRef, userUpdate);
            console.log(`[CASHOUT] Limpieza visual aplicada: moneyInPlay=0, currentTableId=null`);

            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // CRÍTICO: Registrar rake en plataforma (system_stats/economy)
            if (totalRake > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(totalRake),
                    lastUpdated: timestamp
                }, { merge: true });
                console.log(`[CASHOUT] Rake registrado en plataforma: +${totalRake}`);

                // Crear registro RAKE_COLLECTED en financial_ledger para la plataforma
                const rakeLedgerRef = db.collection('financial_ledger').doc();
                transaction.set(rakeLedgerRef, {
                    type: 'RAKE_COLLECTED',
                    userId: uid,
                    userName: displayName, // CRÍTICO: Guardar displayName
                    tableId: sessionData?.roomId || null,
                    amount: totalRake,
                    timestamp: timestamp,
                    description: `Rake recolectado de sesión ${sessionId} - Usuario: ${displayName} (${uid})`,
                    sessionId: sessionId,
                    metadata: {
                        finalChips: finalChips,
                        buyInAmount: buyInAmount,
                        netWinnings: netWinnings
                    }
                });
                console.log(`[CASHOUT] Registro RAKE_COLLECTED creado: ${rakeLedgerRef.id}`);
            }

            // Escribir en financial_ledger (OBLIGATORIO - nunca debe estar vacío)
            // CRÍTICO: Para perdedores (finalChips === 0), usar -buyInAmount en lugar de 0
            const ledgerAmount = finalChips === 0 && netWinnings === 0
                ? -buyInAmount  // Perdedor: registrar pérdida total del buy-in
                : netWinnings;   // Ganador o empate: registrar monto recibido

            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: ledgerType,
                userId: uid,
                userName: displayName, // CRÍTICO: Guardar displayName para evitar "Unknown"
                tableId: sessionData?.roomId || null,
                amount: ledgerAmount,  // Usar ledgerAmount corregido (negativo para perdedores)
                netAmount: netWinnings,  // Lo que realmente recibió (puede ser 0)
                netProfit: netProfit,
                grossAmount: finalChips, // Fichas antes del exit fee
                rakePaid: totalRake,
                exitFee: exitFee,
                buyInAmount: buyInAmount,
                timestamp: timestamp,
                description: `Cashout de sesión ${sessionId}. ${ledgerType === 'GAME_WIN' ? 'Ganancia' : 'Pérdida'} Neta: ${netProfit > 0 ? '+' : ''}${netProfit} (Recibido: ${netWinnings}, Buy-in: ${buyInAmount}, Rake: ${totalRake}${exitFee > 0 ? `, Exit Fee: ${exitFee}` : ''})`
            });
            console.log(`[CASHOUT] Registro creado en financial_ledger: ${ledgerRef.id}`);

            // Registrar en transaction_logs (sub-colección) para compatibilidad
            if (netWinnings > 0) {
                const transactionRef = userRef.collection('transactions').doc();
                transaction.set(transactionRef, {
                    type: 'poker_cashout',
                    amount: netWinnings,
                    reason: `Poker Room Cash-out - ${ledgerType}`,
                    sessionId: sessionId,
                    metadata: {
                        finalChips: finalChips,
                        buyInAmount: buyInAmount,
                        rakePaid: totalRake,
                        exitFee: exitFee
                    },
                    timestamp: timestamp
                });
            }

            // Registrar exit fee si aplica
            if (exitFee > 0) {
                const feeRef = userRef.collection('transactions').doc();
                transaction.set(feeRef, {
                    type: 'poker_exit_fee',
                    amount: -exitFee,
                    reason: 'Early Exit Fee',
                    sessionId: sessionId,
                    timestamp: timestamp
                });
            }
        });

        console.log(`✅ Ended poker session ${sessionId} for user ${uid}. Returned ${Math.max(0, finalChips - exitFee)} credits (Fee: ${exitFee}).`);
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

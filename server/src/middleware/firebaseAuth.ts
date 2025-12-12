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
        // Check for existing active session for this user in this room
        const existingSessionQuery = await db.collection('poker_sessions')
            .where('userId', '==', uid)
            .where('roomId', '==', roomId)
            .where('status', '==', 'active')
            .limit(1)
            .get();

        if (!existingSessionQuery.empty) {
            console.log(`User ${uid} already has an active session in room ${roomId}. Reusing.`);
            return existingSessionQuery.docs[0].id;
        }

        const sessionId = await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(uid);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error('User not found');
            }

            const currentBalance = userDoc.data()?.credit || 0;

            if (currentBalance < amount) {
                throw new Error('Insufficient balance');
            }

            // Deduct balance from main wallet
            transaction.update(userRef, {
                credit: currentBalance - amount,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Create Poker Session
            const sessionRef = db.collection('poker_sessions').doc();
            const newSessionId = sessionRef.id;

            transaction.set(sessionRef, {
                userId: uid,
                roomId: roomId,
                buyInAmount: amount,
                currentChips: amount,
                startTime: admin.firestore.FieldValue.serverTimestamp(),
                status: 'active',
                totalRakePaid: 0
            });

            // Record transaction log
            const transactionRef = userRef.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'poker_buyin',
                amount: -amount,
                reason: `Poker Room Buy-in: ${roomId}`,
                sessionId: newSessionId,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return newSessionId;
        });

        console.log(`Reserved poker session ${sessionId} for user ${uid} in room ${roomId}`);
        return sessionId;
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

            // Obtener buy-in original de la sesión
            const buyInAmount = Number(sessionData?.buyInAmount) || 0;
            
            // Calcular monto neto (fichas finales - exit fee)
            const netWinnings = Math.max(0, finalChips - exitFee);
            
            // Calcular ganancia/pérdida vs buy-in
            const netProfit = netWinnings - buyInAmount;
            
            // Determinar tipo de transacción
            const ledgerType = netWinnings > buyInAmount ? 'GAME_WIN' : 'GAME_LOSS';
            
            console.log(`[CASHOUT] Usuario: ${uid}, Sesión: ${sessionId}`);
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

            // Actualizar crédito del usuario (OBLIGATORIO usar increment para evitar race conditions)
            if (netWinnings > 0) {
                transaction.update(userRef, {
                    credit: admin.firestore.FieldValue.increment(netWinnings),
                    // LIMPIEZA DE ESTADO VISUAL - Elimina el indicador "+X en mesa"
                    currentTableId: admin.firestore.FieldValue.delete(),
                    moneyInPlay: admin.firestore.FieldValue.delete(),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[CASHOUT] Crédito actualizado: +${netWinnings} al saldo del usuario`);
            } else {
                // Aunque sea 0, limpiar estado visual
                transaction.update(userRef, {
                    currentTableId: admin.firestore.FieldValue.delete(),
                    moneyInPlay: admin.firestore.FieldValue.delete(),
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            // Escribir en financial_ledger (OBLIGATORIO - nunca debe estar vacío)
            const timestamp = admin.firestore.FieldValue.serverTimestamp();
            const ledgerRef = db.collection('financial_ledger').doc();
            transaction.set(ledgerRef, {
                type: ledgerType,
                userId: uid,
                tableId: sessionData?.roomId || null,
                amount: netWinnings,
                netAmount: netWinnings,
                netProfit: netProfit,
                grossAmount: finalChips, // Fichas antes del exit fee
                rakePaid: totalRake,
                exitFee: exitFee,
                buyInAmount: buyInAmount,
                timestamp: timestamp,
                description: `Cashout de sesión ${sessionId}. ${ledgerType === 'GAME_WIN' ? 'Ganancia' : 'Pérdida'} Neta: ${netProfit > 0 ? '+' : ''}${netProfit} (Recibido: ${netWinnings}, Rake: ${totalRake}${exitFee > 0 ? `, Exit Fee: ${exitFee}` : ''})`
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

            // Log transaction
            const transactionRef = userRef.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'poker_topup',
                amount: -amount,
                reason: 'Poker Room Top-Up',
                sessionId: sessionId,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        });

        console.log(`Added ${amount} chips to session ${sessionId} for user ${uid}`);
        return true;
    } catch (error) {
        console.error('Error adding chips to session:', error);
        return false;
    }
}

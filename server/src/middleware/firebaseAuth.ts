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
            const initialBalance = 1000;
            const now = admin.firestore.FieldValue.serverTimestamp();

            const userData = {
                uid: uid,
                email: decodedToken.email || '',
                displayName: decodedToken.name || 'Player',
                photoURL: decodedToken.picture || '',
                credit: initialBalance, // Changed from walletBalance to credit
                createdAt: now,
                lastLogin: now
            };

            await userRef.set(userData);

            // Create initial transaction
            await userRef.collection('transactions').add({
                type: 'deposit',
                amount: initialBalance,
                reason: 'Welcome Bonus',
                timestamp: now
            });

            console.log(`Created new user ${uid} with ${initialBalance} credits`);
        } else {
            // Update last login
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
            const sessionId = sessionRef.id;

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
                sessionId: sessionId,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return sessionId;
        });

        console.log(`Reserved poker session ${sessionId} for user ${uid} in room ${roomId}`);
        return sessionId;
    } catch (error) {
        console.error('Error reserving poker session:', error);
        return null;
    }
}

export async function endPokerSession(uid: string, sessionId: string, finalChips: number, totalRake: number): Promise<boolean> {
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

            if (sessionDoc.data()?.status !== 'active') {
                // Already closed, maybe duplicate call
                return;
            }

            // Update session status
            transaction.update(sessionRef, {
                currentChips: finalChips,
                totalRakePaid: totalRake, // This might be cumulative if updated periodically, but here we set final
                endTime: admin.firestore.FieldValue.serverTimestamp(),
                status: 'completed'
            });

            // Return chips to user wallet
            if (finalChips > 0) {
                const userDoc = await transaction.get(userRef);
                if (userDoc.exists) {
                    const currentBalance = userDoc.data()?.credit || 0;
                    transaction.update(userRef, {
                        credit: currentBalance + finalChips,
                        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                    });

                    // Record transaction log
                    const transactionRef = userRef.collection('transactions').doc();
                    transaction.set(transactionRef, {
                        type: 'poker_cashout',
                        amount: finalChips,
                        reason: 'Poker Room Cash-out',
                        sessionId: sessionId,
                        timestamp: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            }
        });

        console.log(`Ended poker session ${sessionId} for user ${uid}. Returned ${finalChips} credits.`);
        return true;
    } catch (error) {
        console.error('Error ending poker session:', error);
        return false;
    }
}

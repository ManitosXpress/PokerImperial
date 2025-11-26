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
                walletBalance: initialBalance,
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
        return userDoc.data()?.walletBalance || 0;
    } catch (error) {
        console.error('Error getting balance:', error);
        return 0;
    }
}

export async function deductCreditsForGame(uid: string, amount: number): Promise<boolean> {
    if (!admin.apps.length) return false;

    const db = admin.firestore();

    try {
        const result = await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(uid);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error('User not found');
            }

            const currentBalance = userDoc.data()?.walletBalance || 0;

            if (currentBalance < amount) {
                throw new Error('Insufficient balance');
            }

            // Deduct balance
            transaction.update(userRef, {
                walletBalance: currentBalance - amount,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Record transaction
            const transactionRef = userRef.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'payment',
                amount: -amount,
                reason: 'Game Entry Fee',
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return true;
        });

        return result;
    } catch (error) {
        console.error('Error deducting credits:', error);
        return false;
    }
}

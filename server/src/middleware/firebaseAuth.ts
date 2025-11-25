import * as admin from 'firebase-admin';
import * as path from 'path';
import * as fs from 'fs';

// Initialize Firebase Admin
// Check if serviceAccountKey.json exists
const serviceAccountPath = path.join(__dirname, '../../serviceAccountKey.json');

if (fs.existsSync(serviceAccountPath)) {
    try {
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccountPath)
        });
        console.log('Firebase Admin initialized successfully');
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
        return decodedToken.uid;
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

            transaction.update(userRef, {
                walletBalance: currentBalance - amount,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            return true;
        });

        return result;
    } catch (error) {
        console.error('Error deducting credits:', error);
        return false;
    }
}

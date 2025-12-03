import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const onUserCreate = functions.auth.user().onCreate(async (user) => {
    const { uid, email, displayName, photoURL } = user;

    const userRef = db.collection('users').doc(uid);

    try {
        await userRef.set({
            uid,
            email,
            displayName: displayName || '',
            photoURL: photoURL || '',
            role: 'player', // Enforce default role
            clubId: null,   // Enforce no club
            credit: 0,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            // We use merge: true to avoid overwriting if the client created the doc first
            // However, we WANT to enforce role/clubId, so we might want to be careful.
            // But since this runs async, client might have written something.
            // Let's ensure role and clubId are set correctly.
        }, { merge: true });

        console.log(`User ${uid} created with default role 'player'.`);

    } catch (error) {
        console.error(`Error creating user profile for ${uid}:`, error);
    }
});

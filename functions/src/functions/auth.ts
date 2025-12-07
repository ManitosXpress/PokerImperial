import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const onUserCreate = functions.auth.user().onCreate(async (user) => {
    const { uid, email, displayName, photoURL } = user;

    const userRef = db.collection('users').doc(uid);

    try {
        const doc = await userRef.get();

        if (doc.exists) {
            // Document exists (likely created by ownerCreateMember or sellerCreatePlayer)
            // We only fill in missing fields if necessary, but definitely DO NOT overwrite role/clubId
            // if they are already set.
            console.log(`User ${uid} already has a profile. Skipping default creation.`);
            return;
        }

        // Document doesn't exist, create with defaults (for self-registration)
        await userRef.set({
            uid,
            email,
            displayName: displayName || '',
            photoURL: photoURL || '',
            role: 'player', // Default role for self-signup
            clubId: null,   // Default no club
            credit: 0,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`User ${uid} created with default role 'player'.`);

    } catch (error) {
        console.error(`Error creating user profile for ${uid}:`, error);
    }
});

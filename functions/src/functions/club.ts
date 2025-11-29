import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * createClub
 * Creates a new club.
 */
export const createClub = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { name, description } = data;
    if (!name) {
        throw new functions.https.HttpsError('invalid-argument', 'Club name is required.');
    }

    const userId = context.auth.uid;
    const clubId = db.collection('clubs').doc().id;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const newClub = {
        id: clubId,
        name,
        description: description || '',
        ownerId: userId,
        members: [userId],
        memberCount: 1,
        walletBalance: 0,
        createdAt: timestamp,
    };

    await db.collection('clubs').doc(clubId).set(newClub);

    // Update user's clubId
    await db.collection('users').doc(userId).update({
        clubId: clubId
    });

    return { success: true, clubId };
};

/**
 * joinClub
 * Adds a user to a club.
 */
export const joinClub = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { clubId } = data;
    if (!clubId) {
        throw new functions.https.HttpsError('invalid-argument', 'Club ID is required.');
    }

    const userId = context.auth.uid;
    const clubRef = db.collection('clubs').doc(clubId);

    await db.runTransaction(async (transaction) => {
        const clubDoc = await transaction.get(clubRef);
        if (!clubDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Club not found.');
        }

        const clubData = clubDoc.data();
        if (clubData?.members.includes(userId)) {
            throw new functions.https.HttpsError('already-exists', 'User is already a member.');
        }

        transaction.update(clubRef, {
            members: admin.firestore.FieldValue.arrayUnion(userId),
            memberCount: admin.firestore.FieldValue.increment(1)
        });

        transaction.update(db.collection('users').doc(userId), {
            clubId: clubId
        });
    });

    return { success: true };
};

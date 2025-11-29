import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * getClubLeaderboard
 * Fetches the leaderboard for a specific club.
 * Returns a list of members sorted by their credit balance.
 */
export const getClubLeaderboard = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { clubId } = data;
    if (!clubId) {
        throw new functions.https.HttpsError('invalid-argument', 'Club ID is required.');
    }

    // Verify user is a member of the club
    const clubDoc = await db.collection('clubs').doc(clubId).get();
    if (!clubDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Club not found.');
    }

    const clubData = clubDoc.data();
    if (!clubData?.members.includes(context.auth.uid)) {
        throw new functions.https.HttpsError('permission-denied', 'You are not a member of this club.');
    }

    // Fetch members' data
    // Note: In a real large-scale app, you might want to maintain a separate leaderboard collection
    // or use a scheduled function to aggregate this data to avoid reading all user docs.
    // For now, we'll read user docs for members (limit to top 50 or similar if list is huge).

    const members = clubData.members;
    if (members.length === 0) return { leaderboard: [] };

    // Firestore 'in' query supports up to 10 items. For larger clubs, we need to batch or rethink.
    // For this MVP, we will assume we can fetch users by clubId index if we added it to users.
    // Since we added clubId to users in createClub/joinClub, we can query users where clubId == clubId.

    const usersSnapshot = await db.collection('users')
        .where('clubId', '==', clubId)
        .orderBy('credits', 'desc') // Requires an index
        .limit(50)
        .get();

    const leaderboard = usersSnapshot.docs.map(doc => {
        const userData = doc.data();
        return {
            uid: doc.id,
            displayName: userData.displayName || 'Unknown',
            photoURL: userData.photoURL || '',
            credits: userData.credits || 0, // In a real app, maybe show 'winnings' instead of total wallet
        };
    });

    return { leaderboard };
};

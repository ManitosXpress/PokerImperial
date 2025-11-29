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

    console.log(`📊 Fetching leaderboard for club: ${clubId} by user: ${context.auth.uid}`);

    // Verify user is a member of the club
    const clubDoc = await db.collection('clubs').doc(clubId).get();
    if (!clubDoc.exists) {
        console.log(`❌ Club not found: ${clubId}`);
        throw new functions.https.HttpsError('not-found', 'Club not found.');
    }

    const clubData = clubDoc.data();
    if (!clubData?.members || !clubData.members.includes(context.auth.uid)) {
        console.log(`❌ User ${context.auth.uid} is not a member of club ${clubId}`);
        throw new functions.https.HttpsError('permission-denied', 'You are not a member of this club.');
    }

    const members = clubData.members;
    console.log(`📊 Club has ${members.length} members`);

    if (members.length === 0) {
        console.log('⚠️ Club has no members');
        return { leaderboard: [] };
    }

    try {
        // Try to use the indexed query first
        console.log('📊 Attempting indexed query...');
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
                credits: userData.credits || 0,
            };
        });

        console.log(`✅ Successfully fetched ${leaderboard.length} leaderboard entries`);
        return { leaderboard };

    } catch (error: any) {
        console.log(`⚠️ Indexed query failed: ${error.message}`);

        // If index is missing and club is small (<=10 members), fetch individually
        if (error.message.includes('index') && members.length <= 10) {
            console.log(`📊 Falling back to individual member fetch for ${members.length} members`);

            const userDocs = await Promise.all(
                members.map((uid: string) => db.collection('users').doc(uid).get())
            );

            const leaderboard = userDocs
                .filter(doc => doc.exists)
                .map(doc => {
                    const userData = doc.data()!;
                    return {
                        uid: doc.id,
                        displayName: userData.displayName || 'Unknown',
                        photoURL: userData.photoURL || '',
                        credits: userData.credits || 0,
                    };
                })
                .sort((a, b) => b.credits - a.credits);

            console.log(`✅ Fallback successful: ${leaderboard.length} members`);
            return { leaderboard };
        }

        // Re-throw for other errors or large clubs
        console.error(`❌ Cannot fetch leaderboard: ${error.message}`);
        throw new functions.https.HttpsError(
            'failed-precondition',
            `Failed to fetch leaderboard. ${error.message.includes('index') ?
                'Please create the required Firestore index. Check the Firebase Console Functions logs for the index creation link.' :
                error.message}`
        );
    }
};

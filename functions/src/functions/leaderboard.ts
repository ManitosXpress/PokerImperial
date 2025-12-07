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

    let leaderboard: any[] = [];


    try {
        // Try to use the indexed query first
        console.log('📊 Attempting indexed query...');
        const usersSnapshot = await db.collection('users')
            .where('clubId', '==', clubId)
            .orderBy('credit', 'desc') // Correct field name is 'credit'
            .limit(50)
            .get();

        leaderboard = usersSnapshot.docs.map(doc => {
            const userData = doc.data();
            return {
                uid: doc.id,
                displayName: userData.displayName || 'Unknown',
                photoURL: userData.photoURL || '',
                credits: userData.credit || 0, // Use 'credit' from DB
                role: userData.role || 'player', // Include role
            };
        });

        console.log(`✅ Indexed query found ${leaderboard.length} entries`);

    } catch (error: any) {
        console.log(`⚠️ Indexed query failed: ${error.message}`);
        // We will fall through to the fallback check
    }

    // FALLBACK: If query returned no results (or failed) BUT we have members, fetch individually
    // This handles cases where:
    // 1. Firestore index is missing (error caught above)
    // 2. Users don't have 'clubId' field set (query returns empty)
    // 3. Data inconsistency
    if (leaderboard.length === 0 && members.length > 0) {
        console.log(`📊 Falling back to individual member fetch for ${members.length} members`);


        // Limit fallback to 50 members to prevent explosion
        const membersToFetch = members.slice(0, 50);

        const userDocs = await Promise.all(
            membersToFetch.map((uid: string) => db.collection('users').doc(uid).get())
        );

        leaderboard = userDocs
            .filter(doc => doc.exists)
            .map(doc => {
                const userData = doc.data()!;
                return {
                    uid: doc.id,
                    displayName: userData.displayName || 'Unknown',
                    photoURL: userData.photoURL || '',
                    credits: userData.credit || 0, // Use 'credit' from DB, map to 'credits' for frontend
                    role: userData.role || 'player', // Include role
                };
            })
            .sort((a, b) => b.credits - a.credits);

        console.log(`✅ Fallback successful: ${leaderboard.length} members`);
    }

    return { leaderboard };
};

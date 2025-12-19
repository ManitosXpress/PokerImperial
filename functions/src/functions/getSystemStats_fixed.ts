import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Lazy initialization de Firestore para evitar timeout en deploy
const getDb = () => {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    return admin.firestore();
};

const assertAdmin = (context: functions.https.CallableContext) => {
    // Basic check for auth
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required.');
};

/**
 * getSystemStats
 * Returns aggregated system statistics.
 * FIXED: Added null safety to prevent 500 errors when system_stats/economy doesn't exist
 */
export const getSystemStats = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    try {
        const db = getDb();
        // 1. Count Users
        const usersSnapshot = await db.collection('users').count().get();
        const totalUsers = usersSnapshot.data().count;

        // 2. Active Tables
        const tablesSnapshot = await db.collection('poker_sessions').where('status', '==', 'active').count().get();
        const activeTables = tablesSnapshot.data().count;

        // 3. Total Circulation (Robust Calculation)
        // We sum 'credit' (singular) as requested
        let totalCirculation = 0;

        const allUsers = await db.collection('users').select('credit').get();

        allUsers.forEach(doc => {
            const d = doc.data();
            totalCirculation += (Number(d.credit) || 0);
        });

        // 4. Get accumulated rake with null safety - READ FIRST
        const economyDoc = await db.collection('system_stats').doc('economy').get();
        const economyData = economyDoc.exists ? economyDoc.data() : null;
        const accumulatedRake = economyData?.accumulated_rake || 0;

        // 5. Update cache for reference - WRITE AFTER reading, preserve rake
        await db.collection('system_stats').doc('economy').set({
            totalCirculation: totalCirculation,
            accumulated_rake: accumulatedRake,
            lastCalculated: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        return {
            totalUsers,
            activeTables,
            totalCirculation,
            accumulatedRake
        };
    } catch (error) {
        console.error('Error getting stats:', error);
        throw new functions.https.HttpsError('internal', 'Failed to get stats.');
    }
};

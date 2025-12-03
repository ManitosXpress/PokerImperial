import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();
const auth = admin.auth();

// Helper to check if request is from an admin
const assertAdmin = (context: functions.https.CallableContext) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }
    // Check for custom claim 'role' == 'admin'
    if (context.auth.token.role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Admin privileges required.');
    }
};

/**
 * adminSetUserRole
 * Changes a user's role in Firestore and Custom Claims.
 * @param data { targetUid: string, newRole: string }
 */
export const adminSetUserRole = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    const { targetUid, newRole } = data;
    const validRoles = ['admin', 'club', 'seller', 'player'];

    if (!targetUid || !validRoles.includes(newRole)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid targetUid or newRole.');
    }

    try {
        // 1. Update Custom Claims (Source of Truth for Security Rules)
        await auth.setCustomUserClaims(targetUid, { role: newRole });

        // 2. Update Firestore Document (For UI/Querying)
        await db.collection('users').doc(targetUid).update({
            role: newRole,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });

        console.log(`Admin ${context.auth?.uid} changed role of ${targetUid} to ${newRole}`);
        return { success: true };
    } catch (error) {
        console.error('Error setting user role:', error);
        throw new functions.https.HttpsError('internal', 'Failed to set user role.');
    }
};

/**
 * adminMintCredits
 * Mints new credits to a user's wallet and logs to financial_ledger.
 * @param data { targetUid: string, amount: number }
 */
export const adminMintCredits = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    const { targetUid, amount } = data;
    if (!targetUid || typeof amount !== 'number' || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid targetUid or amount.');
    }

    const userRef = db.collection('users').doc(targetUid);
    const ledgerRef = db.collection('financial_ledger').doc();

    try {
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'User not found.');
            }

            const currentCredit = userDoc.data()?.credit || 0;
            const newCredit = currentCredit + amount;

            // 1. Update User Wallet
            transaction.update(userRef, { credit: newCredit });

            // 2. Log to Ledger
            transaction.set(ledgerRef, {
                type: 'ADMIN_MINT',
                amount: amount,
                currency: 'CREDIT',
                fromId: 'SYSTEM_MINT',
                toId: targetUid,
                performedBy: context.auth?.uid,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Admin minted ${amount} credits for user ${targetUid}`
            });
        });

        console.log(`Admin ${context.auth?.uid} minted ${amount} credits for ${targetUid}`);
        return { success: true };
    } catch (error) {
        console.error('Error minting credits:', error);
        throw new functions.https.HttpsError('internal', 'Failed to mint credits.');
    }
};

/**
 * getSystemStats
 * Returns aggregated system statistics.
 */
export const getSystemStats = async (data: any, context: functions.https.CallableContext) => {
    assertAdmin(context);

    try {
        // Note: For large datasets, these aggregations should be done via distributed counters
        // or scheduled functions. For now, we'll do simple queries.

        // 1. Count Users
        const usersSnapshot = await db.collection('users').count().get();
        const totalUsers = usersSnapshot.data().count;

        // 2. Active Tables (Sessions)
        const tablesSnapshot = await db.collection('poker_sessions').where('status', '==', 'active').count().get();
        const activeTables = tablesSnapshot.data().count;

        // 3. Total Circulation (This is expensive, ideally use a counter. We'll skip exact sum for now to avoid timeout on large DBs)
        // Or we can just sum the 'financial_ledger' MINTs - BURNS? 
        // Let's just return 0 for now or implement a basic sum if requested.
        // User requested "Total de Créditos en Circulación".
        // We will do a sum of all user credits. WARNING: Expensive.
        // Optimization: Only sum top 100 wallets? No, that's inaccurate.
        // Let's try to sum all. If it fails, we'll need a different approach.
        // Actually, let's just return a placeholder or a "calculated nightly" value if we had one.
        // For this MVP, let's assuming the user base is small enough (< 1000 users).

        let totalCirculation = 0;
        const allUsers = await db.collection('users').select('credit').get();
        allUsers.forEach(doc => {
            totalCirculation += (doc.data().credit || 0);
        });

        return {
            totalUsers,
            activeTables,
            totalCirculation
        };
    } catch (error) {
        console.error('Error getting stats:', error);
        throw new functions.https.HttpsError('internal', 'Failed to get stats.');
    }
};

/**
 * bootstrapAdmin
 * Temporary function to make the caller an admin.
 * Protected by a hardcoded secret.
 */
export const bootstrapAdmin = async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const { secret } = data;
    if (secret !== 'ANTIGRAVITY_GOD_MODE_2025') {
        throw new functions.https.HttpsError('permission-denied', 'Invalid secret.');
    }

    try {
        await auth.setCustomUserClaims(context.auth.uid, { role: 'admin' });
        await db.collection('users').doc(context.auth.uid).update({
            role: 'admin',
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
        return { success: true, message: 'You are now an Admin.' };
    } catch (error) {
        console.error('Error bootstrapping admin:', error);
        throw new functions.https.HttpsError('internal', 'Failed to bootstrap.');
    }
};

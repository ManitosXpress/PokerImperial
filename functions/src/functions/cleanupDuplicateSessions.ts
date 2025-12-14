import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

/**
 * Admin function to find and clean up duplicate poker sessions.
 * 
 * Finds all active sessions and groups by userId+roomId.
 * For duplicates, keeps the oldest (first created) and marks the rest as 'duplicate_cleaned'.
 * 
 * Usage:
 * - Call with { dryRun: true } to preview what would be cleaned (default)
 * - Call with { dryRun: false } to actually clean duplicates
 * 
 * @param data.dryRun - If true (default), only reports duplicates without cleaning
 * @returns Summary of duplicates found and (optionally) cleaned
 */
export const cleanupDuplicateSessions = functions.https.onCall(async (data, context) => {
    // 1. Verify authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const db = admin.firestore();

    // 2. Verify admin role
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    const userData = userDoc.data();

    if (userData?.role !== 'admin' && userData?.role !== 'owner') {
        throw new functions.https.HttpsError('permission-denied', 'Admin access required');
    }

    const dryRun = data?.dryRun ?? true; // Default to dry run for safety

    console.log(`[CLEANUP] Starting duplicate session cleanup. DryRun: ${dryRun}`);

    try {
        // 3. Find all active sessions
        const activeSessions = await db.collection('poker_sessions')
            .where('status', '==', 'active')
            .get();

        console.log(`[CLEANUP] Found ${activeSessions.size} total active sessions`);

        // 4. Group by `userId_roomId`
        const sessionGroups = new Map<string, Array<admin.firestore.QueryDocumentSnapshot>>();

        for (const doc of activeSessions.docs) {
            const sessionData = doc.data();
            const key = `${sessionData.userId}_${sessionData.roomId}`;
            const existing = sessionGroups.get(key) || [];
            existing.push(doc);
            sessionGroups.set(key, existing);
        }

        // 5. Find duplicates (groups with more than 1 session)
        const duplicates: Array<{
            sessionId: string,
            userId: string,
            roomId: string,
            buyInAmount: number,
            startTime: any
        }> = [];

        const toClean: admin.firestore.QueryDocumentSnapshot[] = [];

        for (const [key, sessions] of sessionGroups.entries()) {
            if (sessions.length > 1) {
                console.log(`[CLEANUP] Duplicate group ${key}: ${sessions.length} sessions`);

                // Sort by startTime (oldest first) - keep the oldest, clean the rest
                sessions.sort((a, b) =>
                    (a.data().startTime?.toMillis() || 0) - (b.data().startTime?.toMillis() || 0)
                );

                // Keep the first (oldest), mark the rest as duplicates
                for (let i = 1; i < sessions.length; i++) {
                    const session = sessions[i];
                    const sessionData = session.data();

                    duplicates.push({
                        sessionId: session.id,
                        userId: sessionData.userId,
                        roomId: sessionData.roomId,
                        buyInAmount: sessionData.buyInAmount || 0,
                        startTime: sessionData.startTime?.toDate?.()?.toISOString() || 'unknown'
                    });

                    toClean.push(session);
                }
            }
        }

        console.log(`[CLEANUP] Found ${duplicates.length} duplicate sessions to clean`);

        // 6. Clean if not dry run
        let cleanedCount = 0;

        if (!dryRun && toClean.length > 0) {
            const timestamp = admin.firestore.FieldValue.serverTimestamp();

            // Firestore batch has a limit of 500 operations
            const batchSize = 400;

            for (let i = 0; i < toClean.length; i += batchSize) {
                const batch = db.batch();
                const chunk = toClean.slice(i, i + batchSize);

                for (const session of chunk) {
                    batch.update(session.ref, {
                        status: 'duplicate_cleaned',
                        cleanedAt: timestamp,
                        cleanedBy: context.auth.uid,
                        originalStatus: 'active',
                        cleanupNote: 'Automated cleanup of duplicate session'
                    });
                }

                await batch.commit();
                cleanedCount += chunk.length;
                console.log(`[CLEANUP] Cleaned batch ${Math.floor(i / batchSize) + 1}: ${chunk.length} sessions`);
            }

            console.log(`[CLEANUP] ✅ Cleaned ${cleanedCount} duplicate sessions`);
        }

        // 7. Build summary by user
        const userSummary = new Map<string, number>();
        for (const dup of duplicates) {
            const count = userSummary.get(dup.userId) || 0;
            userSummary.set(dup.userId, count + 1);
        }

        const affectedUsers = Array.from(userSummary.entries()).map(([userId, count]) => ({
            userId,
            duplicatesCleaned: count
        }));

        return {
            success: true,
            dryRun: dryRun,
            totalActiveSessions: activeSessions.size,
            duplicatesFound: duplicates.length,
            duplicates: duplicates,
            affectedUsers: affectedUsers,
            cleaned: cleanedCount,
            message: dryRun
                ? `[DRY RUN] Found ${duplicates.length} duplicate sessions across ${affectedUsers.length} users. Run with dryRun=false to clean.`
                : `✅ Cleaned ${cleanedCount} duplicate sessions across ${affectedUsers.length} users.`
        };

    } catch (error: any) {
        console.error('[CLEANUP] ❌ Error during cleanup:', error);
        throw new functions.https.HttpsError('internal', `Cleanup failed: ${error.message || 'Unknown error'}`);
    }
});

/**
 * Utility function to check for a specific user's duplicate sessions.
 * Can be called by admin to diagnose a single user.
 */
export const checkUserSessions = functions.https.onCall(async (data, context) => {
    // Verify authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const db = admin.firestore();

    // Verify admin role
    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    const callerData = callerDoc.data();

    if (callerData?.role !== 'admin' && callerData?.role !== 'owner') {
        throw new functions.https.HttpsError('permission-denied', 'Admin access required');
    }

    const targetUserId = data?.userId;
    if (!targetUserId) {
        throw new functions.https.HttpsError('invalid-argument', 'userId is required');
    }

    // Find all sessions for this user
    const allSessions = await db.collection('poker_sessions')
        .where('userId', '==', targetUserId)
        .orderBy('startTime', 'desc')
        .limit(50)
        .get();

    const activeSessions = allSessions.docs.filter(doc => doc.data().status === 'active');

    // Group active sessions by room
    const byRoom = new Map<string, Array<any>>();
    for (const doc of activeSessions) {
        const sessionData = doc.data();
        const roomId = sessionData.roomId;
        const existing = byRoom.get(roomId) || [];
        existing.push({
            sessionId: doc.id,
            roomId,
            buyInAmount: sessionData.buyInAmount,
            currentChips: sessionData.currentChips,
            startTime: sessionData.startTime?.toDate?.()?.toISOString() || 'unknown',
            status: sessionData.status
        });
        byRoom.set(roomId, existing);
    }

    // Find duplicates
    const duplicateRooms: Array<{ roomId: string, sessionCount: number, sessions: any[] }> = [];
    for (const [roomId, sessions] of byRoom.entries()) {
        if (sessions.length > 1) {
            duplicateRooms.push({
                roomId,
                sessionCount: sessions.length,
                sessions
            });
        }
    }

    // Get user info
    const userDoc = await db.collection('users').doc(targetUserId).get();
    const userData = userDoc.data();

    return {
        success: true,
        userId: targetUserId,
        displayName: userData?.displayName || 'Unknown',
        currentTableId: userData?.currentTableId || null,
        moneyInPlay: userData?.moneyInPlay || 0,
        totalSessions: allSessions.size,
        activeSessions: activeSessions.length,
        duplicateRooms: duplicateRooms,
        hasDuplicates: duplicateRooms.length > 0,
        message: duplicateRooms.length > 0
            ? `⚠️ User has ${duplicateRooms.length} rooms with duplicate sessions`
            : '✅ No duplicate sessions found'
    };
});

import * as admin from "firebase-admin";

/**
 * REAL-TIME DAILY STATS UPDATER
 * 
 * Updates daily statistics atomically in real-time as games are played.
 * This ensures the dashboard shows live 24h metrics instead of waiting for midnight cron.
 * 
 * Document Structure: stats_daily/{YYYY-MM-DD}
 * Fields:
 * - totalVolume: Sum of all pots (betting volume)
 * - totalHands: Number of hands played (turnover/velocity)
 * - dailyGGR: Gross Gaming Revenue (total rake collected)
 * - lastUpdated: Server timestamp
 */

/**
 * Helper function to update daily stats atomically
 * 
 * Call this IMMEDIATELY after each hand settlement
 * 
 * @param potSize - Total pot size (chips wagered this hand)
 * @param rakeGenerated - Rake collected from this hand
 */
export async function updateDailyStats(
    potSize: number,
    rakeGenerated: number
): Promise<void> {
    try {
        const db = admin.firestore();

        // Get today's date in UTC-04 timezone (your preference)
        const now = new Date();
        const dateKey = now.toISOString().split('T')[0]; // YYYY-MM-DD

        // Reference to today's stats document
        const statsRef = db.collection('stats_daily').doc(dateKey);

        // Atomic increment (creates document if doesn't exist)
        await statsRef.set({
            dateKey: dateKey,
            date: admin.firestore.Timestamp.now(),
            totalVolume: admin.firestore.FieldValue.increment(potSize),
            totalHands: admin.firestore.FieldValue.increment(1),
            dailyGGR: admin.firestore.FieldValue.increment(rakeGenerated),
            totalRake: admin.firestore.FieldValue.increment(rakeGenerated), // Alias for consistency
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        console.log(`✅ Daily stats updated: +$${potSize} volume, +$${rakeGenerated} GGR, +1 hand`);
    } catch (error) {
        console.error('❌ Error updating daily stats:', error);
        // Don't throw - we don't want to fail the game settlement if stats update fails
    }
}

/**
 * Alternative: Update inside a transaction
 * 
 * Use this version if you want the daily stats update to be part of the same
 * transaction as the game settlement (all-or-nothing)
 * 
 * @param transaction - Firestore transaction object
 * @param potSize - Total pot size
 * @param rakeGenerated - Rake collected
 */
export function updateDailyStatsInTransaction(
    transaction: admin.firestore.Transaction,
    potSize: number,
    rakeGenerated: number
): void {
    const db = admin.firestore();

    const now = new Date();
    const dateKey = now.toISOString().split('T')[0];

    const statsRef = db.collection('stats_daily').doc(dateKey);

    // Use transaction.set with merge
    transaction.set(statsRef, {
        dateKey: dateKey,
        date: admin.firestore.Timestamp.now(),
        totalVolume: admin.firestore.FieldValue.increment(potSize),
        totalHands: admin.firestore.FieldValue.increment(1),
        dailyGGR: admin.firestore.FieldValue.increment(rakeGenerated),
        totalRake: admin.firestore.FieldValue.increment(rakeGenerated),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
}

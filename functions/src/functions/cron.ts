import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * dailyEconomyCron
 * Runs every day at midnight (00:00) to aggregate economic stats for the previous day.
 * 
 * Aggregates:
 * - Total Rake (RAKE_COLLECTED)
 * - Total Mint (ADMIN_MINT)
 * - Total Burn (ADMIN_BURN)
 * - Total Volume (Chips put into play - GAME_WIN/GAME_LOSS buyInAmount)
 * 
 * Writes to: stats_daily/{YYYY-MM-DD}
 */
export const dailyEconomyCron = functions.pubsub.schedule('0 0 * * *').timeZone('America/New_York').onRun(async (context) => {
    const db = admin.firestore();

    // Calculate date range for "Yesterday"
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);

    // Format YYYY-MM-DD for document ID
    const year = yesterday.getFullYear();
    const month = String(yesterday.getMonth() + 1).padStart(2, '0');
    const day = String(yesterday.getDate()).padStart(2, '0');
    const dateId = `${year}-${month}-${day}`;

    // Start and End of yesterday
    const startOfDay = new Date(year, yesterday.getMonth(), yesterday.getDate(), 0, 0, 0);
    const endOfDay = new Date(year, yesterday.getMonth(), yesterday.getDate(), 23, 59, 59, 999);

    console.log(`📊 Starting Daily Economy Aggregation for ${dateId}...`);

    try {
        // Query financial_ledger for yesterday's transactions
        const ledgerSnapshot = await db.collection('financial_ledger')
            .where('timestamp', '>=', startOfDay)
            .where('timestamp', '<=', endOfDay)
            .get();

        let totalRake = 0;
        let totalMint = 0;
        let totalBurn = 0;
        let totalVolume = 0;

        ledgerSnapshot.forEach(doc => {
            const data = doc.data();
            const type = data.type;
            const amount = Number(data.amount) || 0;
            const buyIn = Number(data.buyInAmount) || 0;

            if (type === 'RAKE_COLLECTED') {
                totalRake += amount;
            } else if (type === 'ADMIN_MINT') {
                totalMint += amount;
            } else if (type === 'ADMIN_BURN') {
                totalBurn += amount; // Burn is usually stored as positive amount in ledger for this type, or check implementation
            } else if (type === 'GAME_WIN' || type === 'GAME_LOSS') {
                // Volume = Total Chips put into play (Buy-ins)
                // We sum buyInAmount from all game results
                // Note: This might double count if we are not careful, but usually GAME_WIN/LOSS is per session end.
                // A better volume metric might be sum of all bets, but buy-in volume is a good proxy for "Chips cycled".
                totalVolume += buyIn;
            }
        });

        // Write to stats_daily
        await db.collection('stats_daily').doc(dateId).set({
            date: dateId,
            timestamp: admin.firestore.Timestamp.fromDate(startOfDay),
            totalRake,
            totalMint,
            totalBurn,
            totalVolume,
            calculatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true }); // Merge to preserve handsPlayed if it was updated in real-time

        console.log(`✅ Daily Stats for ${dateId} saved: Rake=${totalRake}, Mint=${totalMint}, Burn=${totalBurn}, Vol=${totalVolume}`);
        return null;

    } catch (error) {
        console.error(`❌ Error in dailyEconomyCron for ${dateId}:`, error);
        return null;
    }
});

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * DAILY ECONOMY STATISTICS AGGREGATOR
 * 
 * Runs daily at midnight UTC-04 to aggregate financial metrics from the previous day.
 * This prevents expensive real-time queries on the financial_ledger collection.
 * 
 * Stores aggregated data in: stats_daily/{YYYY-MM-DD}
 * 
 * Metrics calculated:
 * - totalRake: Total house rake collected
 * - totalMint: Total credits injected (deposits, bonuses)
 * - totalBurn: Total credits removed (withdrawals)
 * - totalVolume: Total betting volume (sum of all bets)
 * - handsPlayed: Number of poker hands played
 * - activeUsers: Number of unique users who played
 */
export const dailyEconomyCron = functions.pubsub
    .schedule('0 4 * * *') // 4 AM UTC = Midnight UTC-04
    .timeZone('America/Caracas') // UTC-04 timezone
    .onRun(async (context) => {
        const db = admin.firestore();

        // Calculate yesterday's date in UTC-04
        const now = new Date();
        const yesterday = new Date(now);
        yesterday.setDate(yesterday.getDate() - 1);
        yesterday.setHours(0, 0, 0, 0);

        const dayStart = admin.firestore.Timestamp.fromDate(yesterday);
        const dayEnd = admin.firestore.Timestamp.fromDate(
            new Date(yesterday.getTime() + 24 * 60 * 60 * 1000)
        );

        const dateKey = yesterday.toISOString().split('T')[0]; // YYYY-MM-DD

        console.log(`📊 Starting daily economy aggregation for ${dateKey}`);

        try {
            // Query financial_ledger for yesterday's transactions
            const ledgerSnapshot = await db.collection('financial_ledger')
                .where('timestamp', '>=', dayStart)
                .where('timestamp', '<', dayEnd)
                .get();

            console.log(`📝 Found ${ledgerSnapshot.size} transactions for ${dateKey}`);

            // Initialize metrics
            let totalRake = 0;
            let totalMint = 0;
            let totalBurn = 0;
            let totalVolume = 0;
            let handsPlayed = 0;
            const activeUserIds = new Set<string>();

            // Process each transaction
            for (const doc of ledgerSnapshot.docs) {
                const data = doc.data();
                const type = data.type;
                const amount = Math.abs(Number(data.amount) || 0);
                const userId = data.userId;

                if (userId) {
                    activeUserIds.add(userId);
                }

                switch (type) {
                    case 'RAKE':
                        totalRake += amount;
                        break;

                    case 'MINT':
                    case 'DEPOSIT':
                    case 'BONUS':
                    case 'REFUND':
                        totalMint += amount;
                        break;

                    case 'BURN':
                    case 'WITHDRAWAL':
                        totalBurn += amount;
                        break;

                    case 'BET':
                    case 'ANTE':
                    case 'BLIND':
                        totalVolume += amount;
                        break;

                    case 'HAND_COMPLETE':
                        handsPlayed++;
                        break;
                }
            }

            // Calculate derived metrics
            const netFlow = totalMint - totalBurn;
            const activeUsers = activeUserIds.size;

            // Store aggregated stats
            const statsDoc = {
                date: dayStart,
                dateKey: dateKey,
                totalRake: totalRake,
                totalMint: totalMint,
                totalBurn: totalBurn,
                totalVolume: totalVolume,
                handsPlayed: handsPlayed,
                activeUsers: activeUsers,
                netFlow: netFlow,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            };

            await db.collection('stats_daily').doc(dateKey).set(statsDoc);

            console.log(`✅ Daily stats saved for ${dateKey}:`, {
                totalRake,
                totalMint,
                totalBurn,
                totalVolume,
                handsPlayed,
                activeUsers,
                netFlow
            });

            return {
                success: true,
                dateKey,
                stats: statsDoc
            };

        } catch (error: any) {
            console.error(`❌ Error aggregating daily stats for ${dateKey}:`, error);
            throw error;
        }
    });

/**
 * MANUAL TRIGGER FOR DAILY STATS
 * 
 * Allows manual execution of daily stats aggregation for a specific date.
 * Useful for backfilling historical data or fixing missed cron runs.
 * 
 * Usage:
 * POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/triggerDailyStats
 * Body: { "date": "2025-12-13" }  // Optional, defaults to yesterday
 */
export const triggerDailyStats = functions.https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed. Use POST.' });
        return;
    }

    const db = admin.firestore();
    const requestedDate = req.body?.date;

    // Parse date
    let targetDate: Date;
    if (requestedDate) {
        targetDate = new Date(requestedDate);
        targetDate.setHours(0, 0, 0, 0);
    } else {
        // Default to yesterday
        targetDate = new Date();
        targetDate.setDate(targetDate.getDate() - 1);
        targetDate.setHours(0, 0, 0, 0);
    }

    const dayStart = admin.firestore.Timestamp.fromDate(targetDate);
    const dayEnd = admin.firestore.Timestamp.fromDate(
        new Date(targetDate.getTime() + 24 * 60 * 60 * 1000)
    );

    const dateKey = targetDate.toISOString().split('T')[0];

    try {
        console.log(`📊 Manual daily stats aggregation for ${dateKey}`);

        const ledgerSnapshot = await db.collection('financial_ledger')
            .where('timestamp', '>=', dayStart)
            .where('timestamp', '<', dayEnd)
            .get();

        let totalRake = 0;
        let totalMint = 0;
        let totalBurn = 0;
        let totalVolume = 0;
        let handsPlayed = 0;
        const activeUserIds = new Set<string>();

        for (const doc of ledgerSnapshot.docs) {
            const data = doc.data();
            const type = data.type;
            const amount = Math.abs(Number(data.amount) || 0);
            const userId = data.userId;

            if (userId) {
                activeUserIds.add(userId);
            }

            switch (type) {
                case 'RAKE':
                    totalRake += amount;
                    break;
                case 'MINT':
                case 'DEPOSIT':
                case 'BONUS':
                case 'REFUND':
                    totalMint += amount;
                    break;
                case 'BURN':
                case 'WITHDRAWAL':
                    totalBurn += amount;
                    break;
                case 'BET':
                case 'ANTE':
                case 'BLIND':
                    totalVolume += amount;
                    break;
                case 'HAND_COMPLETE':
                    handsPlayed++;
                    break;
            }
        }

        const statsDoc = {
            date: dayStart,
            dateKey: dateKey,
            totalRake: totalRake,
            totalMint: totalMint,
            totalBurn: totalBurn,
            totalVolume: totalVolume,
            handsPlayed: handsPlayed,
            activeUsers: activeUserIds.size,
            netFlow: totalMint - totalBurn,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection('stats_daily').doc(dateKey).set(statsDoc);

        res.status(200).json({
            success: true,
            dateKey,
            stats: statsDoc,
            transactionsProcessed: ledgerSnapshot.size
        });

    } catch (error: any) {
        console.error(`❌ Error in manual stats aggregation:`, error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

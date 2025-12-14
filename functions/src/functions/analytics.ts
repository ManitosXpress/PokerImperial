import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * GET TOP HOLDERS (WHALES)
 * 
 * Returns top 10 users with highest credit balance.
 * Optimized with Firestore index on credit DESC.
 * 
 * Usage: Call this function to get the richest users in the ecosystem.
 */
export const getTopHolders = functions.https.onCall(async (data, context) => {
    // Require authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    // Optional: Require admin role
    // const userDoc = await admin.firestore().collection('users').doc(context.auth.uid).get();
    // if (userDoc.data()?.role !== 'admin') {
    //     throw new functions.https.HttpsError('permission-denied', 'Admin access required.');
    // }

    try {
        const db = admin.firestore();
        const limit = data?.limit || 10;

        const snapshot = await db.collection('users')
            .orderBy('credit', 'desc')
            .limit(limit)
            .get();

        const whales = snapshot.docs.map(doc => ({
            uid: doc.id,
            displayName: doc.data().displayName || 'Unknown',
            email: doc.data().email || '',
            photoURL: doc.data().photoURL || '',
            credit: Number(doc.data().credit) || 0,
            rank: 0 // Will be set below
        }));

        // Assign ranks
        whales.forEach((whale, index) => {
            whale.rank = index + 1;
        });

        return {
            success: true,
            whales: whales,
            total: whales.length
        };

    } catch (error: any) {
        console.error('Error getting top holders:', error);
        throw new functions.https.HttpsError('internal', `Failed to get top holders: ${error.message}`);
    }
});

/**
 * GET TOP WINNERS 24H (SHARKS)
 * 
 * Returns top 10 users with highest net profit in the last 24 hours.
 * Calculated from financial_ledger entries.
 * 
 * This is critical for detecting:
 * - Bots or automated players
 * - Collusion between players
 * - Unusual winning patterns
 */
export const getTopWinners24h = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    try {
        const db = admin.firestore();
        const limit = data?.limit || 10;

        // Get timestamp from 24 hours ago
        const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 24 * 60 * 60 * 1000)
        );

        // Query financial_ledger for last 24h
        const snapshot = await db.collection('financial_ledger')
            .where('timestamp', '>=', twentyFourHoursAgo)
            .get();

        // Calculate net profit per user
        const userProfits = new Map<string, {
            userId: string;
            netProfit: number;
            wins: number;
            losses: number;
            handsPlayed: number;
        }>();

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const userId = data.userId;
            const type = data.type;
            const amount = Number(data.amount) || 0;

            if (!userId) continue;

            if (!userProfits.has(userId)) {
                userProfits.set(userId, {
                    userId,
                    netProfit: 0,
                    wins: 0,
                    losses: 0,
                    handsPlayed: 0
                });
            }

            const userStats = userProfits.get(userId)!;

            // Track net profit
            if (type === 'GAME_WIN') {
                userStats.netProfit += amount;
                userStats.wins++;
            } else if (type === 'GAME_LOSS') {
                userStats.netProfit -= Math.abs(amount);
                userStats.losses++;
            } else if (type === 'HAND_COMPLETE') {
                userStats.handsPlayed++;
            }
        }

        // Convert to array and sort by net profit
        const sortedUsers = Array.from(userProfits.values())
            .sort((a, b) => b.netProfit - a.netProfit)
            .slice(0, limit);

        // Fetch user details
        const sharks = await Promise.all(
            sortedUsers.map(async (stats, index) => {
                const userDoc = await db.collection('users').doc(stats.userId).get();
                const userData = userDoc.data();

                return {
                    uid: stats.userId,
                    displayName: userData?.displayName || 'Unknown',
                    email: userData?.email || '',
                    photoURL: userData?.photoURL || '',
                    netProfit: stats.netProfit,
                    wins: stats.wins,
                    losses: stats.losses,
                    handsPlayed: stats.handsPlayed,
                    winRate: stats.wins + stats.losses > 0
                        ? (stats.wins / (stats.wins + stats.losses) * 100).toFixed(1)
                        : '0.0',
                    rank: index + 1
                };
            })
        );

        return {
            success: true,
            sharks: sharks,
            total: sharks.length,
            period: '24h'
        };

    } catch (error: any) {
        console.error('Error getting top winners 24h:', error);
        throw new functions.https.HttpsError('internal', `Failed to get top winners: ${error.message}`);
    }
});

/**
 * GET 24H METRICS
 * 
 * Returns real-time metrics for the current 24-hour period:
 * - Betting volume (total chips wagered)
 * - Hands played
 * - GGR (Gross Gaming Revenue = total rake)
 * - Active users
 */
export const get24hMetrics = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    try {
        const db = admin.firestore();

        const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 24 * 60 * 60 * 1000)
        );

        const snapshot = await db.collection('financial_ledger')
            .where('timestamp', '>=', twentyFourHoursAgo)
            .get();

        let bettingVolume = 0;
        let handsPlayed = 0;
        let ggr = 0; // Gross Gaming Revenue (rake)
        const activeUserIds = new Set<string>();

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const type = data.type;
            const amount = Math.abs(Number(data.amount) || 0);
            const userId = data.userId;

            if (userId) {
                activeUserIds.add(userId);
            }

            if (type === 'BET' || type === 'ANTE' || type === 'BLIND') {
                bettingVolume += amount;
            } else if (type === 'RAKE') {
                ggr += amount;
            } else if (type === 'HAND_COMPLETE') {
                handsPlayed++;
            }
        }

        return {
            success: true,
            metrics: {
                bettingVolume: bettingVolume,
                handsPlayed: handsPlayed,
                ggr: ggr,
                activeUsers: activeUserIds.size,
                moneyVelocity: handsPlayed // Using hands as proxy for velocity
            },
            period: '24h',
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

    } catch (error: any) {
        console.error('Error getting 24h metrics:', error);
        throw new functions.https.HttpsError('internal', `Failed to get 24h metrics: ${error.message}`);
    }
});

/**
 * GET WEEKLY TRENDS
 * 
 * Returns 7 days of aggregated data for charts:
 * - Daily liquidity (total user credits)
 * - Daily rake
 * - Daily mint vs burn
 * 
 * Uses the stats_daily collection for fast queries.
 */
export const getWeeklyTrends = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    try {
        const db = admin.firestore();
        const days = data?.days || 7;

        // Get last N days from stats_daily
        const snapshot = await db.collection('stats_daily')
            .orderBy('dateKey', 'desc')
            .limit(days)
            .get();

        const trends = snapshot.docs
            .map(doc => ({
                date: doc.id,
                totalRake: doc.data().totalRake || 0,
                totalMint: doc.data().totalMint || 0,
                totalBurn: doc.data().totalBurn || 0,
                totalVolume: doc.data().totalVolume || 0,
                handsPlayed: doc.data().handsPlayed || 0,
                activeUsers: doc.data().activeUsers || 0,
                netFlow: doc.data().netFlow || 0
            }))
            .reverse(); // Oldest to newest for chart display

        // Calculate total liquidity for each day
        // Note: This is a simplified calculation. For more accuracy,
        // you might want to store daily snapshots of total user credits
        const trendsWithLiquidity = await Promise.all(
            trends.map(async (day) => {
                // For now, get current total liquidity
                // In production, you'd want to snapshot this daily
                const usersSnapshot = await db.collection('users').get();
                let totalLiquidity = 0;
                usersSnapshot.docs.forEach(doc => {
                    totalLiquidity += Number(doc.data().credit) || 0;
                });

                return {
                    ...day,
                    totalLiquidity: totalLiquidity
                };
            })
        );

        return {
            success: true,
            trends: trendsWithLiquidity,
            days: trendsWithLiquidity.length
        };

    } catch (error: any) {
        console.error('Error getting weekly trends:', error);
        throw new functions.https.HttpsError('internal', `Failed to get weekly trends: ${error.message}`);
    }
});

/**
 * GET CURRENT LIQUIDITY
 * 
 * Returns total liquidity (sum of all user credits) in real-time.
 * This is used for the main dashboard card.
 */
export const getCurrentLiquidity = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    try {
        const db = admin.firestore();

        const snapshot = await db.collection('users').get();

        let totalLiquidity = 0;
        let userCount = 0;

        snapshot.docs.forEach(doc => {
            const credit = Number(doc.data().credit) || 0;
            totalLiquidity += credit;
            userCount++;
        });

        return {
            success: true,
            totalLiquidity: totalLiquidity,
            userCount: userCount,
            averageBalance: userCount > 0 ? totalLiquidity / userCount : 0,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

    } catch (error: any) {
        console.error('Error getting current liquidity:', error);
        throw new functions.https.HttpsError('internal', `Failed to get liquidity: ${error.message}`);
    }
});

/**
 * GET TOTAL RAKE
 * 
 * Returns total rake collected in the system's lifetime.
 */
export const getTotalRake = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    try {
        const db = admin.firestore();

        const snapshot = await db.collection('financial_ledger')
            .where('type', '==', 'RAKE')
            .get();

        let totalRake = 0;

        snapshot.docs.forEach(doc => {
            const amount = Math.abs(Number(doc.data().amount) || 0);
            totalRake += amount;
        });

        return {
            success: true,
            totalRake: totalRake,
            transactionCount: snapshot.size,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

    } catch (error: any) {
        console.error('Error getting total rake:', error);
        throw new functions.https.HttpsError('internal', `Failed to get rake: ${error.message}`);
    }
});

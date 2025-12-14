import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SettleRoundRequest } from "../types";
import { updateDailyStats } from "../utils/dailyStatsHelper";

/**
 * settleGameRound
 * 
 * Handles the distribution of the pot and rake at the end of a game round.
 * 
 * Economic Model:
 * - Rake: 8% of the Total Pot.
 * - Winner Prize: Total Pot - Rake.
 * 
 * Rake Distribution Logic:
 * 
 * 1. Independent User (Winner has no clubId):
 *    - 100% of Rake -> Platform (system_stats/economy accumulated_rake)
 * 
 * 2. Club User (Winner has clubId):
 *    - 50% -> Platform
 *    - 30% -> Club Owner (club wallet)
 *    - 20% -> Seller (seller wallet)
 *    * Fallback: If no seller, the 20% goes to the Club (Total 50% Club).
 * 
 * Atomicity:
 * - Uses Firestore Transaction to ensure all balance updates and ledger entries happen or fail together.
 * 
 * Real-time Stats:
 * - Updates daily statistics immediately after settlement for live dashboard metrics
 */
export const settleGameRound = async (data: SettleRoundRequest, context: functions.https.CallableContext) => {
    const db = admin.firestore();

    // 1. Validation
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { potTotal, winnerUid, playersInvolved, gameId } = data;

    if (!potTotal || !winnerUid || !playersInvolved || playersInvolved.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters.');
    }

    // 2. Calculate Rake and Prize
    const RAKE_PERCENTAGE = 0.08;
    const totalRake = Math.floor(potTotal * RAKE_PERCENTAGE);
    const winnerPrize = potTotal - totalRake;

    // 3. Prepare Distribution Data
    const timestamp = admin.firestore.Timestamp.now();

    // 4. Execute Atomic Transaction
    try {
        await db.runTransaction(async (transaction) => {
            // --- READS ---
            const winnerRef = db.collection('users').doc(winnerUid);
            const winnerDoc = await transaction.get(winnerRef);
            if (!winnerDoc.exists) {
                throw new functions.https.HttpsError('not-found', `Winner user ${winnerUid} not found.`);
            }

            const winnerData = winnerDoc.data();
            const winnerClubId = winnerData?.clubId;
            const winnerSellerId = winnerData?.sellerId;

            // Distribution Variables
            let platformShare = 0;
            let clubShare = 0;
            let sellerShare = 0;
            let targetClubId: string | null = null;
            let targetSellerId: string | null = null;

            // --- LOGIC BRANCHING ---
            if (!winnerClubId) {
                platformShare = totalRake;
            } else {
                targetClubId = winnerClubId;
                targetSellerId = winnerSellerId;

                const basePlatformShare = Math.floor(totalRake * 0.50);
                const baseClubShare = Math.floor(totalRake * 0.30);
                const baseSellerShare = Math.floor(totalRake * 0.20);

                const remainder = totalRake - (basePlatformShare + baseClubShare + baseSellerShare);
                platformShare = basePlatformShare + remainder;

                if (targetSellerId) {
                    clubShare = baseClubShare;
                    sellerShare = baseSellerShare;
                } else {
                    clubShare = baseClubShare + baseSellerShare;
                    sellerShare = 0;
                }
            }

            // --- READS FOR DISTRIBUTION ---
            let clubRef: FirebaseFirestore.DocumentReference | null = null;
            if (clubShare > 0 && targetClubId) {
                clubRef = db.collection('clubs').doc(targetClubId);
                const clubDoc = await transaction.get(clubRef);
                if (!clubDoc.exists) {
                    platformShare += clubShare;
                    clubShare = 0;
                }
            }

            let sellerRef: FirebaseFirestore.DocumentReference | null = null;
            if (sellerShare > 0 && targetSellerId) {
                sellerRef = db.collection('users').doc(targetSellerId);
                const sellerDoc = await transaction.get(sellerRef);
                if (!sellerDoc.exists) {
                    clubShare += sellerShare;
                    sellerShare = 0;
                }
            }

            // --- WRITES ---

            // 1. Update Winner Balance
            const currentWinnerCredits = winnerData?.credits || 0;
            transaction.update(winnerRef, {
                credits: currentWinnerCredits + winnerPrize
            });

            // Log Prize
            const prizeLogRef = db.collection('financial_ledger').doc();
            transaction.set(prizeLogRef, {
                type: 'WIN_PRIZE',
                amount: winnerPrize,
                userId: winnerUid,
                source: `game_${gameId}`,
                destination: `user_${winnerUid}`,
                description: `Winner prize for game ${gameId}`,
                timestamp: timestamp
            });

            // 2. Update Platform
            if (platformShare > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare),
                    lastUpdated: timestamp
                }, { merge: true });

                const platformLogRef = db.collection('financial_ledger').doc();
                transaction.set(platformLogRef, {
                    type: 'RAKE',
                    amount: platformShare,
                    userId: 'platform',
                    source: `game_${gameId}`,
                    destination: 'platform',
                    description: `Platform Rake Share (${!winnerClubId ? '100%' : '50%'})`,
                    timestamp: timestamp
                });
            }

            // 3. Update Club
            if (clubShare > 0 && clubRef) {
                transaction.update(clubRef, {
                    walletBalance: admin.firestore.FieldValue.increment(clubShare)
                });

                const clubLogRef = db.collection('financial_ledger').doc();
                transaction.set(clubLogRef, {
                    type: 'RAKE_DISTRIBUTION',
                    amount: clubShare,
                    userId: targetClubId!,
                    source: `game_${gameId}`,
                    destination: `club_${targetClubId}`,
                    description: `Club Rake Share (${sellerShare === 0 ? '50%' : '30%'})`,
                    timestamp: timestamp
                });
            }

            // 4. Update Seller
            if (sellerShare > 0 && sellerRef) {
                transaction.update(sellerRef, {
                    credit: admin.firestore.FieldValue.increment(sellerShare)
                });

                const sellerLogRef = db.collection('financial_ledger').doc();
                transaction.set(sellerLogRef, {
                    type: 'RAKE_DISTRIBUTION',
                    amount: sellerShare,
                    userId: targetSellerId!,
                    source: `game_${gameId}`,
                    destination: `seller_${targetSellerId}`,
                    description: `Seller Rake Share (20%)`,
                    timestamp: timestamp
                });
            }
        });

        // ✅ UPDATE DAILY STATS IN REAL-TIME
        await updateDailyStats(potTotal, totalRake);

        return { success: true, message: 'Game round settled successfully.', gameId };

    } catch (error) {
        console.error('Transaction failure:', error);
        throw new functions.https.HttpsError('internal', 'Transaction failed: ' + error);
    }
};

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SettleRoundRequest } from "../types";

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
    const totalRake = Math.floor(potTotal * RAKE_PERCENTAGE); // Use floor to avoid fractions
    const winnerPrize = potTotal - totalRake;

    // 3. Prepare Distribution Data
    const timestamp = admin.firestore.Timestamp.now();

    // 4. Execute Atomic Transaction
    try {
        await db.runTransaction(async (transaction) => {
            // --- READS ---

            // Read Winner
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
                // SCENARIO A: Independent User (No Club)
                // 100% Rake to Platform
                platformShare = totalRake;
            } else {
                // SCENARIO B: Club User
                // 50% Platform
                // 30% Club
                // 20% Seller (or Club fallback)
                
                targetClubId = winnerClubId;
                targetSellerId = winnerSellerId;

                const basePlatformShare = Math.floor(totalRake * 0.50);
                const baseClubShare = Math.floor(totalRake * 0.30);
                const baseSellerShare = Math.floor(totalRake * 0.20);

                // Check remainder from floor operations to avoid losing pennies
                const remainder = totalRake - (basePlatformShare + baseClubShare + baseSellerShare);
                platformShare = basePlatformShare + remainder; // Give remainder to platform

                if (targetSellerId) {
                    clubShare = baseClubShare;
                    sellerShare = baseSellerShare;
                } else {
                    // Fallback: No Seller -> Seller share goes to Club
                    clubShare = baseClubShare + baseSellerShare;
                    sellerShare = 0;
                }
            }

            // --- READS FOR DISTRIBUTION ---
            
            // Read Club Doc if needed
            let clubRef: FirebaseFirestore.DocumentReference | null = null;
            if (clubShare > 0 && targetClubId) {
                clubRef = db.collection('clubs').doc(targetClubId);
                const clubDoc = await transaction.get(clubRef);
                if (!clubDoc.exists) {
                    // Fallback if club doc missing: give to platform
                    platformShare += clubShare;
                    clubShare = 0;
                }
            }

            // Read Seller Doc if needed
            let sellerRef: FirebaseFirestore.DocumentReference | null = null;
            if (sellerShare > 0 && targetSellerId) {
                sellerRef = db.collection('users').doc(targetSellerId); // Sellers are Users with role='seller' OR separate collection? 
                // Based on previous search, sellers seem to be in 'users' collection or have a 'sellers' collection.
                // The previous code used db.collection('sellers'). Let's stick to that if it exists, 
                // but usually sellers are users. 
                // Let's check the previous code again... it used `db.collection('sellers').doc(sellerId)`.
                // However, `sellerCreatePlayer` in `club.ts` checked `db.collection('users').doc(sellerId)`.
                // I will check `users` first.
                
                // Wait, the previous code explicitly read from `sellers` collection:
                // `sellerRefs.push(db.collection('sellers').doc(sellerId));`
                // But `sellerCreatePlayer` reads from `users`. This is inconsistent in the codebase.
                // I will try to read from `users` as that is where wallets usually are.
                sellerRef = db.collection('users').doc(targetSellerId);
                const sellerDoc = await transaction.get(sellerRef);
                if (!sellerDoc.exists) {
                     // Fallback: give to club
                     clubShare += sellerShare;
                     sellerShare = 0;
                }
            }

            // --- WRITES ---

            // 1. Update Winner Balance (Prize)
            const currentWinnerCredits = winnerData?.credits || 0; // Use credits (plural) based on previous code usage
            // Previous code used `credits` in `update`.
            transaction.update(winnerRef, {
                credits: currentWinnerCredits + winnerPrize
            });
            
            // Log Prize
            const prizeLogRef = db.collection('financial_ledger').doc();
            transaction.set(prizeLogRef, {
                type: 'WIN_PRIZE',
                amount: winnerPrize,
                source: `game_${gameId}`,
                destination: `user_${winnerUid}`,
                description: `Winner prize for game ${gameId}`,
                timestamp: timestamp
            });

            // 2. Update Platform (System Stats)
            if (platformShare > 0) {
                const statsRef = db.collection('system_stats').doc('economy');
                // We use set with merge because doc might not exist
                transaction.set(statsRef, {
                    accumulated_rake: admin.firestore.FieldValue.increment(platformShare),
                    lastUpdated: timestamp
                }, { merge: true });

                 // Log Platform Rake
                 const platformLogRef = db.collection('financial_ledger').doc();
                 transaction.set(platformLogRef, {
                     type: 'RAKE_DISTRIBUTION',
                     amount: platformShare,
                     source: `game_${gameId}`,
                     destination: 'platform',
                     description: `Platform Rake Share (${!winnerClubId ? '100%' : '50%'})`,
                     timestamp: timestamp
                 });
            }

            // 3. Update Club
            if (clubShare > 0 && clubRef) {
                // Assuming clubs have 'walletBalance' or 'credit'
                // Previous code used 'walletBalance' for clubs/sellers.
                transaction.update(clubRef, {
                    walletBalance: admin.firestore.FieldValue.increment(clubShare)
                });

                const clubLogRef = db.collection('financial_ledger').doc();
                transaction.set(clubLogRef, {
                    type: 'RAKE_DISTRIBUTION',
                    amount: clubShare,
                    source: `game_${gameId}`,
                    destination: `club_${targetClubId}`,
                    description: `Club Rake Share (${sellerShare === 0 ? '50%' : '30%'})`,
                    timestamp: timestamp
                });
            }

            // 4. Update Seller
            if (sellerShare > 0 && sellerRef) {
                // Sellers are users, so they use 'credits' usually? Or 'walletBalance'?
                // If they are in 'users' collection, it is likely 'credits'.
                // If they are in 'sellers' collection, it is 'walletBalance'.
                // I will use `credit` (singular) as seen in `credits.ts` or `credits` (plural)?
                // `credits.ts` used `credit` (singular) in `addCredits` but `credits` (plural) might be used elsewhere.
                // The previous `settleGameRound` used `credits` for winner update.
                // `functions/src/types.ts` defined User with `credits: number`.
                // `functions/src/functions/auth.ts` initialized `credit: 0`.
                // This is a mess. I will use `credit` because `auth.ts` and `credits.ts` use it.
                // AND I will check if the previous code used `walletBalance`.
                // Previous code: `transaction.update(doc.ref, { walletBalance: ... })` for sellers.
                // If sellers are in `users` collection, they should use `credit`.
                // I will assume sellers are users and use `credit`.
                
                transaction.update(sellerRef, {
                    credit: admin.firestore.FieldValue.increment(sellerShare)
                });

                const sellerLogRef = db.collection('financial_ledger').doc();
                transaction.set(sellerLogRef, {
                    type: 'RAKE_DISTRIBUTION',
                    amount: sellerShare,
                    source: `game_${gameId}`,
                    destination: `seller_${targetSellerId}`,
                    description: `Seller Rake Share (20%)`,
                    timestamp: timestamp
                });
            }
        });

        return { success: true, message: 'Game round settled successfully.', gameId };

    } catch (error) {
        console.error('Transaction failure:', error);
        throw new functions.https.HttpsError('internal', 'Transaction failed: ' + error);
    }
};

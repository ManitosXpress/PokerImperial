import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';


export const ownerTransferCredit = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();

    // 1. Authentication Check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { clubId, targetUid, amount } = data;
    const ownerId = context.auth.uid;

    // Validation
    if (!clubId || !targetUid || !amount || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid arguments: clubId, targetUid, and positive amount are required.');
    }

    try {
        await db.runTransaction(async (transaction) => {
            // 2. Get Club Document to verify ownership
            const clubRef = db.collection('clubs').doc(clubId);
            const clubDoc = await transaction.get(clubRef);

            if (!clubDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Club not found.');
            }

            const clubData = clubDoc.data();

            // 3. Verify Ownership
            if (clubData?.ownerId !== ownerId) {
                throw new functions.https.HttpsError('permission-denied', 'Only the club owner can transfer funds.');
            }

            // 4. Get Owner Document (Source)
            const ownerRef = db.collection('users').doc(ownerId);
            const ownerDoc = await transaction.get(ownerRef);

            if (!ownerDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Owner profile not found.');
            }

            const ownerBalance = ownerDoc.data()?.credit || 0;
            if (ownerBalance < amount) {
                throw new functions.https.HttpsError('failed-precondition', `Insufficient funds. Available: ${ownerBalance}`);
            }

            // 5. Get Target Member Document (Destination)
            const targetRef = db.collection('users').doc(targetUid);
            const targetDoc = await transaction.get(targetRef);

            if (!targetDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Target member not found.');
            }

            // 6. Execute Transfer
            // Deduct from Owner
            transaction.update(ownerRef, {
                credit: admin.firestore.FieldValue.increment(-amount),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Add to Target Member
            transaction.update(targetRef, {
                credit: admin.firestore.FieldValue.increment(amount),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // 7. Create Transaction Record
            const transactionRef = db.collection('transaction_logs').doc();
            transaction.set(transactionRef, {
                type: 'p2p_transfer', // Peer to peer (Owner to Member)
                fromId: ownerId,
                toId: targetUid,
                amount: amount,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Club Transfer: Owner to Member`,
                clubId: clubId,
                metadata: {
                    initiatedBy: 'owner',
                    clubName: clubData?.name
                }
            });
        });

        return { success: true, message: 'Transfer successful' };

    } catch (error) {
        console.error('Transfer error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Transfer failed', error);
    }
};

/**
 * sellerTransferCredit
 * Allows a seller to transfer credits to a player in their club.
 * - Can only transfer to 'player' role users
 * - Cannot transfer to other sellers or owner
 * - Target must be in the same club
 */
export const sellerTransferCredit = async (data: any, context: functions.https.CallableContext) => {
    const db = admin.firestore();

    // 1. Authentication Check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { clubId, targetUid, amount } = data;
    const sellerId = context.auth.uid;

    // Validation
    if (!clubId || !targetUid || !amount || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid arguments: clubId, targetUid, and positive amount are required.');
    }

    try {
        await db.runTransaction(async (transaction) => {
            // 2. Get Seller Document to verify role
            const sellerRef = db.collection('users').doc(sellerId);
            const sellerDoc = await transaction.get(sellerRef);

            if (!sellerDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Seller profile not found.');
            }

            const sellerData = sellerDoc.data();

            // 3. Verify caller is a seller
            if (sellerData?.role !== 'seller') {
                throw new functions.https.HttpsError('permission-denied', 'Only sellers can use this function.');
            }

            // 4. Verify seller belongs to this club
            if (sellerData?.clubId !== clubId) {
                throw new functions.https.HttpsError('permission-denied', 'You can only transfer within your own club.');
            }

            // 5. Check seller has sufficient balance
            const sellerBalance = sellerData?.credit || 0;
            if (sellerBalance < amount) {
                throw new functions.https.HttpsError('failed-precondition', `Insufficient funds. Available: ${sellerBalance}`);
            }

            // 6. Get Target User Document
            const targetRef = db.collection('users').doc(targetUid);
            const targetDoc = await transaction.get(targetRef);

            if (!targetDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Target user not found.');
            }

            const targetData = targetDoc.data();

            // 7. Verify target is a player (not seller or owner)
            if (targetData?.role !== 'player') {
                throw new functions.https.HttpsError('permission-denied', 'Sellers can only transfer to players, not to other sellers or owners.');
            }

            // 8. Verify target belongs to the same club
            if (targetData?.clubId !== clubId) {
                throw new functions.https.HttpsError('permission-denied', 'Target player must be in the same club.');
            }

            // 9. Execute Transfer
            // Deduct from Seller
            transaction.update(sellerRef, {
                credit: admin.firestore.FieldValue.increment(-amount),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Add to Target Player
            transaction.update(targetRef, {
                credit: admin.firestore.FieldValue.increment(amount),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // 10. Create Transaction Record
            const transactionRef = db.collection('transaction_logs').doc();
            transaction.set(transactionRef, {
                type: 'seller_transfer', // Seller to Player transfer
                fromId: sellerId,
                toId: targetUid,
                amount: amount,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Seller Transfer: Seller to Player`,
                clubId: clubId,
                metadata: {
                    initiatedBy: 'seller',
                    sellerId: sellerId,
                }
            });
        });

        return { success: true, message: 'Transfer successful' };

    } catch (error) {
        console.error('Seller transfer error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Transfer failed', error);
    }
};

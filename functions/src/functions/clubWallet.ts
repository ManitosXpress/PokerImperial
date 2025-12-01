import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const transferClubToMember = async (data: any, context: functions.https.CallableContext) => {
    // 1. Authentication Check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { clubId, memberId, amount } = data;
    const callerId = context.auth.uid;

    // Validation
    if (!clubId || !memberId || !amount || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid arguments: clubId, memberId, and positive amount are required.');
    }

    try {
        await db.runTransaction(async (transaction) => {
            // 2. Get Club Document
            const clubRef = db.collection('clubs').doc(clubId);
            const clubDoc = await transaction.get(clubRef);

            if (!clubDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Club not found.');
            }

            const clubData = clubDoc.data();

            // 3. Verify Ownership
            if (clubData?.ownerId !== callerId) {
                throw new functions.https.HttpsError('permission-denied', 'Only the club owner can transfer funds.');
            }

            // 4. Verify Balance
            const currentBalance = clubData?.walletBalance || 0;
            if (currentBalance < amount) {
                throw new functions.https.HttpsError('failed-precondition', 'Insufficient club funds.');
            }

            // 5. Get Member Document
            const memberRef = db.collection('users').doc(memberId);
            const memberDoc = await transaction.get(memberRef);

            if (!memberDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Member not found.');
            }

            // 6. Execute Transfer
            // Deduct from Club
            transaction.update(clubRef, {
                walletBalance: admin.firestore.FieldValue.increment(-amount)
            });

            // Add to Member
            transaction.update(memberRef, {
                credit: admin.firestore.FieldValue.increment(amount) // Correct field name is 'credit'
            });

            // Optional: Create Transaction Record
            const transactionRef = db.collection('transactions').doc();
            transaction.set(transactionRef, {
                type: 'CLUB_TRANSFER',
                fromId: clubId,
                toId: memberId,
                amount: amount,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: `Transfer from Club ${clubData?.name} to member`
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

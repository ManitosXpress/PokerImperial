import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const externalDeposit = functions.https.onRequest(async (req, res) => {
    // Initialize Admin if needed (though index.ts should handle it, safe to check)
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    // 1. Security Check (Bearer Token)
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        res.status(401).send({ error: 'Unauthorized. Missing Bearer Token.' });
        return;
    }

    const token = authHeader.split('Bearer ')[1];
    if (token !== 'ANTIGRAVITY_N8N_SECRET_2025') {
        res.status(403).send({ error: 'Forbidden. Invalid Token.' });
        return;
    }

    // 2. Validate Input
    if (req.method !== 'POST') {
        res.status(405).send({ error: 'Method Not Allowed. Use POST.' });
        return;
    }

    const { userId, amount, source, details } = req.body;

    if (!userId || typeof amount !== 'number' || amount <= 0) {
        res.status(400).send({ error: 'Invalid input. userId and positive amount are required.' });
        return;
    }

    // 3. Transactional Update
    const userRef = db.collection('users').doc(userId);
    const ledgerRef = db.collection('financial_ledger').doc();

    try {
        const newBalance = await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new Error('User not found');
            }

            const currentCredit = userDoc.data()?.credit || 0;
            const newCredit = currentCredit + amount;

            // Update User Balance
            transaction.update(userRef, {
                credit: newCredit,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Log Transaction
            transaction.set(ledgerRef, {
                type: 'DEPOSIT_BOT',
                amount: amount,
                currency: 'CREDIT',
                fromId: source || 'EXTERNAL_BOT',
                toId: userId,
                performedBy: 'n8n_bot',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                details: details || 'External Deposit',
                metadata: req.body // Store full payload for audit
            });

            return newCredit;
        });

        // 4. Success Response
        res.status(200).send({
            success: true,
            message: 'Deposit successful',
            newBalance: newBalance,
            transactionId: ledgerRef.id
        });

    } catch (error: any) {
        console.error('Error in externalDeposit:', error);
        if (error.message === 'User not found') {
            res.status(404).send({ error: 'User not found' });
        } else {
            res.status(500).send({ error: 'Internal Server Error' });
        }
    }
});

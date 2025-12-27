import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { FeedEventType, SystemFeedItem } from "../types";

// Helper to add to feed
const addToSystemFeed = async (item: SystemFeedItem) => {
    try {
        const db = admin.firestore();
        await db.collection('system_feed').add({
            ...item,
            timestamp: admin.firestore.FieldValue.serverTimestamp() // Ensure server timestamp
        });
    } catch (error) {
        console.error('[FEED] Error adding to feed:', error);
    }
};

/**
 * Trigger: New User Created
 * Source: users/{uid} (onCreate)
 */
export const onUserCreatedFeed = functions.firestore
    .document('users/{uid}')
    .onCreate(async (snapshot, context) => {
        const userData = snapshot.data();
        const name = userData.displayName || 'New User';

        await addToSystemFeed({
            type: FeedEventType.NEW_USER,
            message: `Nuevo usuario registrado: '${name}'`,
            severity: 'low',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            metadata: { uid: context.params.uid }
        });
    });

/**
 * Trigger: Transaction Log Created (Deposits & Withdrawals)
 * Source: transaction_logs/{id} (onCreate)
 */
export const onTransactionLogCreated = functions.firestore
    .document('transaction_logs/{id}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        const type = data.type; // 'credit', 'debit', 'admin_debit'
        const amount = Number(data.amount) || 0;
        const userId = data.userId;
        const reason = data.reason || '';

        // Ignore small amounts or internal transfers if needed
        if (amount <= 0) return;

        // 1. DEPOSITS (Credit)
        // Filter out game winnings or internal transfers if possible. 
        // Usually 'credit' with reason 'Poker Buy-In' is internal, but 'credit' from 'admin' or 'payment' is deposit.
        // Let's look at the reason or metadata.
        // In credits.ts: 
        // - addCredits: type='credit', reason=custom
        // - processCashOut: type='credit', reason='Poker Cashout...' -> We might want to ignore cashouts as "Deposits" to the wallet, 
        //   but maybe show them as "Cashout from Table"? 
        //   The user asked for "Finanzas (In): Depósitos". Cashout from table is internal.
        //   Real deposits come from addCredits.

        if (type === 'credit') {
            if (reason.includes('Poker Cashout')) {
                // This is a player leaving a table. 
                // Maybe we don't show this as a "Deposit" to the system, but as a Game Event?
                // The user prompt says: "Finanzas (In): Depósitos, Rake generado".
                // "Finanzas (Out): Retiros".
                // Let's skip Table Cashouts for "Deposit" feed to avoid noise, or maybe show them as Game events?
                // For now, let's assume "Deposit" means external money coming in.
                // We can filter by checking if it's NOT a cashout.
                return;
            }

            // Assume it's a deposit (Admin add or future payment gateway)
            // Fetch user name
            const db = admin.firestore();
            const userDoc = await db.collection('users').doc(userId).get();
            const userName = userDoc.data()?.displayName || 'User';

            await addToSystemFeed({
                type: FeedEventType.DEPOSIT,
                message: `${userName} depositó ${amount} créditos`,
                amount: amount,
                severity: 'medium',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata: { uid: userId, reason }
            });
        }

        // 2. WITHDRAWALS (Debit)
        // In credits.ts:
        // - deductCredits: type='debit'
        // - withdrawCredits: type='debit', reason='Withdrawal...'
        // - joinTable: type='debit', reason='Poker Buy-In...' -> Internal.
        else if (type === 'debit' || type === 'admin_debit') {
            if (reason.includes('Poker Buy-In')) {
                return; // Internal game buy-in
            }

            // Fetch user name
            const db = admin.firestore();
            const userDoc = await db.collection('users').doc(userId).get();
            const userName = userDoc.data()?.displayName || 'User';

            await addToSystemFeed({
                type: FeedEventType.WITHDRAWAL,
                message: `Retiro: $${amount} por '${userName}'`,
                amount: amount,
                severity: 'high', // Withdrawals are important
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                metadata: { uid: userId, reason }
            });
        }
    });

/**
 * Trigger: Ledger Entry Created (Big Wins)
 * Source: financial_ledger/{id} (onCreate)
 */
export const onLedgerEntryCreated = functions.firestore
    .document('financial_ledger/{id}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();

        // We are looking for RAKE_COLLECTED which implies a hand finished.
        if (data.type === 'RAKE_COLLECTED') {
            const potTotal = Number(data.potTotal) || 0;
            const winnerUid = data.winnerUid;
            const tableId = data.tableId;

            // Threshold for "Big Win"
            if (potTotal > 500) {
                const db = admin.firestore();
                const userDoc = await db.collection('users').doc(winnerUid).get();
                const userName = userDoc.data()?.displayName || 'Player';

                // Get table name if possible, or just ID
                // const tableDoc = await db.collection('poker_tables').doc(tableId).get();
                // const tableName = tableDoc.data()?.name || tableId;

                await addToSystemFeed({
                    type: FeedEventType.GAME_BIG_WIN,
                    message: `Player '${userName}' ganó un bote de ${potTotal}`,
                    amount: potTotal,
                    severity: 'medium', // Good news
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    metadata: { uid: winnerUid, tableId, handId: data.handId }
                });
            }
        }
    });

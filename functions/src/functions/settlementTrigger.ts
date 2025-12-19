import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { settleGameRoundCore } from "./gameEconomy";
import { SettleRoundRequest } from "../types";

// Global initialization to ensure app exists
if (!admin.apps.length) {
    admin.initializeApp();
}

export const onSettlementTriggered = functions.firestore
    .document('_trigger_settlement/{docId}')
    .onCreate(async (snap, context) => {
        const db = admin.firestore(); // Use admin directly since we initialized it globally

        const data = snap.data();
        const docId = context.params.docId;

        console.log(`[TRIGGER] Settlement triggered for ${docId}`);

        // DEBUG: Confirm execution
        try {
            await db.collection('_debug_settlement_errors').add({
                docId,
                status: 'STARTED',
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        } catch (e) { console.error('Debug write failed', e); }

        if (!data) {
            console.error('[TRIGGER] No data in settlement trigger');
            return;
        }

        const request: SettleRoundRequest = {
            potTotal: data.potTotal,
            winnerUid: data.winnerUid,
            playersInvolved: [], // Not strictly used in core logic but part of interface
            gameId: data.gameId,
            tableId: data.tableId,
            finalPlayerStacks: data.finalPlayerStacks,
            authPayload: data.authPayload,
            signature: data.signature
        };

        try {
            await settleGameRoundCore(request, db);
            console.log(`[TRIGGER] Settlement successful for ${docId}`);

            // Cleanup trigger document
            await snap.ref.delete();
        } catch (error: any) {
            console.error(`[TRIGGER] Settlement failed for ${docId}:`, error);

            // Write error to Firestore for debugging
            try {
                await admin.firestore().collection('_debug_settlement_errors').add({
                    docId,
                    error: error.message || JSON.stringify(error),
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
            } catch (e) {
                console.error('Failed to write debug error:', e);
            }
        }
    });

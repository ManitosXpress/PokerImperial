import * as functions from "firebase-functions";
import { settleGameRoundCore } from "./gameEconomy";
import { SettleRoundRequest } from "../types";

export const onSettlementTriggered = functions.firestore
    .document('_trigger_settlement/{docId}')
    .onCreate(async (snap, context) => {
        const data = snap.data();
        const docId = context.params.docId;

        console.log(`[TRIGGER] Settlement triggered for ${docId}`);

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
            await settleGameRoundCore(request);
            console.log(`[TRIGGER] Settlement successful for ${docId}`);

            // Cleanup trigger document
            await snap.ref.delete();
        } catch (error) {
            console.error(`[TRIGGER] Settlement failed for ${docId}:`, error);
            // Don't delete so we can inspect/retry? Or maybe delete to avoid loops?
            // For now, keep it to debug.
        }
    });

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { addCredits, deductCredits, withdrawCredits } from "./functions/credits";
import { settleGameRound } from "./functions/gameEconomy";

// Initialize Firebase Admin SDK (lazy initialization)
if (!admin.apps.length) {
    admin.initializeApp();
}

// Export Cloud Functions
export const addCreditsFunction = functions.https.onCall(addCredits);
export const deductCreditsFunction = functions.https.onCall(deductCredits);
export const withdrawCreditsFunction = functions.https.onCall(withdrawCredits);
export const settleGameRoundFunction = functions.https.onCall(settleGameRound);

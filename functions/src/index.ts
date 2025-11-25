import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { addCredits, deductCredits } from "./functions/credits";

// Initialize Firebase Admin SDK (lazy initialization)
if (!admin.apps.length) {
    admin.initializeApp();
}

// Export Cloud Functions
export const addCreditsFunction = functions.https.onCall(addCredits);
export const deductCreditsFunction = functions.https.onCall(deductCredits);

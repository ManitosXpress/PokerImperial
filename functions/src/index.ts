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

// Club Functions
import { createClub, joinClub } from './functions/club';
export const createClubFunction = functions.https.onCall(createClub);
export const joinClubFunction = functions.https.onCall(joinClub);

// Tournament Functions
import { createTournament } from './functions/tournament';
export const createTournamentFunction = functions.https.onCall(createTournament);

// Leaderboard Functions
import { getClubLeaderboard } from './functions/leaderboard';
export const getClubLeaderboardFunction = functions.https.onCall(getClubLeaderboard);

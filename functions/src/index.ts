import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { addCredits, deductCredits, withdrawCredits, adminWithdrawCredits } from "./functions/credits";
import { settleGameRound } from "./functions/gameEconomy";

// Initialize Firebase Admin SDK (lazy initialization)
if (!admin.apps.length) {
    admin.initializeApp();
}

// Export Cloud Functions
export const addCreditsFunction = functions.https.onCall(addCredits);
export const deductCreditsFunction = functions.https.onCall(deductCredits);
export const withdrawCreditsFunction = functions.https.onCall(withdrawCredits);
export const adminWithdrawCreditsFunction = functions.https.onCall(adminWithdrawCredits);
export const settleGameRoundFunction = functions.https.onCall(settleGameRound);

// Club Functions
import { createClub, joinClub, ownerCreateMember, sellerCreatePlayer } from './functions/club';
export const createClubFunction = functions.https.onCall(createClub);
export const joinClubFunction = functions.https.onCall(joinClub);
export const ownerCreateMemberFunction = functions.https.onCall(ownerCreateMember);
export const sellerCreatePlayerFunction = functions.https.onCall(sellerCreatePlayer);

// Tournament Functions
import { createTournament } from './functions/tournament';
export const createTournamentFunction = functions.https.onCall(createTournament);

// Leaderboard Functions
import { getClubLeaderboard } from './functions/leaderboard';
export const getClubLeaderboardFunction = functions.https.onCall(getClubLeaderboard);

// Club Wallet Functions
import { ownerTransferCredit, sellerTransferCredit } from './functions/clubWallet';
export const ownerTransferCreditFunction = functions.https.onCall(ownerTransferCredit);
export const sellerTransferCreditFunction = functions.https.onCall(sellerTransferCredit);

// Invitation Functions
import { createClubInvite, completeInvitationRegistration } from './functions/invitations';
export const createClubInviteFunction = functions.https.onCall(createClubInvite);
export const completeInvitationRegistrationFunction = functions.https.onCall(completeInvitationRegistration);

// Auth Triggers
import { onUserCreate } from './functions/auth';
export const onUserCreateFunction = onUserCreate;

// Admin Functions
import { adminSetUserRole, adminMintCredits, getSystemStats, bootstrapAdmin, repairStuckSessions, getUserTransactionHistory, clearAllFirestoreData, adminDeleteUser, cleanWelcomeBonusUsers } from './functions/admin';
export const adminSetUserRoleFunction = functions.https.onCall(adminSetUserRole);
export const adminMintCreditsFunction = functions.https.onCall(adminMintCredits);
export const getSystemStatsFunction = functions.https.onCall(getSystemStats);
export const bootstrapAdminFunction = functions.https.onCall(bootstrapAdmin);
export const getUserTransactionHistoryFunction = functions.https.onCall(getUserTransactionHistory);
export const adminDeleteUserFunction = functions.https.onCall(adminDeleteUser);
export { repairStuckSessions, clearAllFirestoreData, cleanWelcomeBonusUsers }; // HTTP Functions para reparación y limpieza

// External Integrations
export * from './functions/external';

// Table Functions
import { createPublicTable, createClubTableFunction as _createClubTableFunction, startGameFunction as _startGameFunction, closeTableAndCashOut } from './functions/table';
export const createPublicTableFunction = createPublicTable;
export const createClubTableFunctionExport = _createClubTableFunction; // Keep for backward compatibility
export const createClubTableFunction = _createClubTableFunction;
export const startGameFunction = _startGameFunction;
export const closeTableAndCashOutFunction = functions.https.onCall(closeTableAndCashOut);

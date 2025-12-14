import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { addCredits, deductCredits, withdrawCredits, adminWithdrawCredits } from "./functions/credits";
import { settleGameRound } from "./functions/gameEconomy";
import { createClub, joinClub, leaveClub, ownerCreateMember, sellerCreatePlayer } from './functions/club';
import { createTournament } from './functions/tournament';
import { getClubLeaderboard } from './functions/leaderboard';
import { ownerTransferCredit, sellerTransferCredit } from './functions/clubWallet';
import { createClubInvite, completeInvitationRegistration } from './functions/invitations';
import { onUserCreate } from './functions/auth';
import { adminSetUserRole, adminMintCredits, getSystemStats, bootstrapAdmin, repairStuckSessions, getUserTransactionHistory, clearAllFirestoreData, adminDeleteUser, cleanWelcomeBonusUsers, adminCreateUser, cleanStuckMoneyInPlay } from './functions/admin';
import { createPublicTable, createClubTableFunction as _createClubTableFunction, startGameFunction as _startGameFunction, closeTableAndCashOut, universalTableSettlement } from './functions/table';

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
export const createClubFunction = functions.https.onCall(createClub);
export const joinClubFunction = functions.https.onCall(joinClub);
export const leaveClubFunction = functions.https.onCall(leaveClub);
export const ownerCreateMemberFunction = functions.https.onCall(ownerCreateMember);
export const sellerCreatePlayerFunction = functions.https.onCall(sellerCreatePlayer);

// Tournament Functions
export const createTournamentFunction = functions.https.onCall(createTournament);

// Leaderboard Functions
export const getClubLeaderboardFunction = functions.https.onCall(getClubLeaderboard);

// Club Wallet Functions
export const ownerTransferCreditFunction = functions.https.onCall(ownerTransferCredit);
export const sellerTransferCreditFunction = functions.https.onCall(sellerTransferCredit);

// Invitation Functions
export const createClubInviteFunction = functions.https.onCall(createClubInvite);
export const completeInvitationRegistrationFunction = functions.https.onCall(completeInvitationRegistration);

// Auth Triggers
export const onUserCreateFunction = onUserCreate;

// Admin Functions
export const adminSetUserRoleFunction = functions.https.onCall(adminSetUserRole);
export const adminMintCreditsFunction = functions.https.onCall(adminMintCredits);
export const getSystemStatsFunction = functions.https.onCall(getSystemStats);
export const bootstrapAdminFunction = functions.https.onCall(bootstrapAdmin);
export const getUserTransactionHistoryFunction = functions.https.onCall(getUserTransactionHistory);
export const adminDeleteUserFunction = functions.https.onCall(adminDeleteUser);
export const adminCreateUserFunction = functions.https.onCall(adminCreateUser);
export { repairStuckSessions, clearAllFirestoreData, cleanWelcomeBonusUsers, cleanStuckMoneyInPlay }; // HTTP Functions para reparación y limpieza

// External Integrations
export * from './functions/external';

// Table Functions
export const createPublicTableFunction = createPublicTable;
export const createClubTableFunctionExport = _createClubTableFunction; // Keep for backward compatibility
export const createClubTableFunction = _createClubTableFunction;
export const startGameFunction = _startGameFunction;
export const closeTableAndCashOutFunction = functions.https.onCall(closeTableAndCashOut);
export const universalTableSettlementFunction = functions.https.onCall(universalTableSettlement);

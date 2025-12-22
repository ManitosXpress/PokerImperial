import * as functions from "firebase-functions";
import * as admin from 'firebase-admin';
import { addCredits, deductCredits, withdrawCredits, adminWithdrawCredits } from "./functions/credits";
import { settleGameRound, joinTable, processCashOut, universalTableSettlement } from "./functions/gameEconomy";
import { createClub, joinClub, leaveClub, ownerCreateMember, sellerCreatePlayer } from './functions/club';
import { createTournament, registerForTournament, unregisterFromTournament, startTournament } from './functions/tournament';
import { adminPauseTournament, adminResumeTournament, adminForceBlindLevel, adminBroadcastMessage } from './functions/tournamentAdmin';
import { sendTournamentMessage } from './functions/chat';
import { onTournamentFinish } from './functions/tournamentTriggers';
import { getClubLeaderboard } from './functions/leaderboard';
import { ownerTransferCredit, sellerTransferCredit } from './functions/clubWallet';
import { createClubInvite, completeInvitationRegistration } from './functions/invitations';
import { onUserCreate } from './functions/auth';
import { adminSetUserRole, adminMintCredits, getSystemStats, bootstrapAdmin, repairStuckSessions, getUserTransactionHistory, clearAllFirestoreData, adminDeleteUser, cleanWelcomeBonusUsers, adminCreateUser, cleanStuckMoneyInPlay, cleanupCorruptedSessions } from './functions/admin';
import { createPublicTable, createClubTableFunction as _createClubTableFunction, startGameFunction as _startGameFunction, getInGameBalance } from './functions/table';
import { dailyEconomyCron } from './functions/cron';
import { dailyEconomyCron as newDailyEconomyCron, triggerDailyStats } from './functions/scheduled_functions';
import { getTopHolders, getTopWinners24h, get24hMetrics, getWeeklyTrends, getCurrentLiquidity, getTotalRake } from './functions/analytics';
import { cleanupDuplicateSessions, checkUserSessions } from './functions/cleanupDuplicateSessions';
import { sanitizeMoneyInPlay } from './functions/sanitize_money_in_play';
import { onCashoutTriggered } from './functions/cashoutTrigger';

// Initialize Firebase Admin SDK (lazy initialization)
// Removed global init to prevent deployment timeouts. 
// Each function must ensure admin is initialized.
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
export const registerForTournamentFunction = functions.https.onCall(registerForTournament);
export const unregisterFromTournamentFunction = functions.https.onCall(unregisterFromTournament);
export const startTournamentFunction = functions.https.onCall(startTournament);
export const sendTournamentMessageFunction = functions.https.onCall(sendTournamentMessage);
export const onTournamentFinishFunction = onTournamentFinish;

// Tournament Admin (God Mode) Functions
export const adminPauseTournamentFunction = functions.https.onCall(adminPauseTournament);
export const adminResumeTournamentFunction = functions.https.onCall(adminResumeTournament);
export const adminForceBlindLevelFunction = functions.https.onCall(adminForceBlindLevel);
export const adminBroadcastMessageFunction = functions.https.onCall(adminBroadcastMessage);

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
export { repairStuckSessions, clearAllFirestoreData, cleanWelcomeBonusUsers, cleanStuckMoneyInPlay, cleanupCorruptedSessions }; // HTTP Functions para reparación y limpieza

// Session Cleanup Functions (Admin)
export { cleanupDuplicateSessions, checkUserSessions };

// Sanitation Scripts (Admin)
export const sanitizeMoneyInPlayFunction = sanitizeMoneyInPlay;

// External Integrations
export * from './functions/external';

// Table Functions
export const createPublicTableFunction = createPublicTable;
export const createClubTableFunctionExport = _createClubTableFunction; // Keep for backward compatibility
export const createClubTableFunction = _createClubTableFunction;
export const startGameFunction = _startGameFunction;

export const universalTableSettlementFunction = functions.https.onCall(universalTableSettlement);
export const joinTableFunction = functions.https.onCall(joinTable);
export const processCashOutFunction = functions.https.onCall(processCashOut);
export const getInGameBalanceFunction = functions.https.onCall(getInGameBalance);
export const dailyEconomyCronFunction = dailyEconomyCron;

// New Economic Intelligence Functions
export { newDailyEconomyCron, triggerDailyStats }; // Scheduled stats aggregation
export const getTopHoldersFunction = getTopHolders;
export const getTopWinners24hFunction = getTopWinners24h;
export const get24hMetricsFunction = get24hMetrics;
export const getWeeklyTrendsFunction = getWeeklyTrends;
export const getCurrentLiquidityFunction = getCurrentLiquidity;
export const getTotalRakeFunction = getTotalRake;

// Backfill / Repair Script (Callable version to avoid timeout)
export { recalcDailyStatsCallable } from './functions/backfillStats';

// Cashout Trigger (Server-Initiated Cashouts)
export const onCashoutTriggeredFunction = onCashoutTriggered;

// Settlement Trigger (Server-Initiated Settlement)
import { onSettlementTriggered } from './functions/settlementTrigger';
export const onSettlementTriggeredV4 = onSettlementTriggered;

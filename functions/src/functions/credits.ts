import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/v1/https";
import { generateTransactionHash } from "../utils/hash";

/**
 * Interface for addCredits request
 */
interface AddCreditsRequest {
    amount: number;
    reason: string;
}

/**
 * Interface for deductCredits request
 */
interface DeductCreditsRequest {
    amount: number;
    reason: string;
    metadata?: {
        gameId?: string;
        tableId?: string;
        [key: string]: any;
    };
}

/**
 * Interface for adminWithdrawCredits request
 */
interface AdminWithdrawCreditsRequest {
    targetUid: string;
    amount: number;
    reason: string;
}

/**
 * Interface for transaction response
 */
interface TransactionResponse {
    success: boolean;
    newBalance: number;
    transactionId: string;
    message?: string;
}

/**
 * ⚠️ DEPRECATED - DO NOT USE
 * 
 * This function has been deprecated for security reasons.
 * 
 * Migration Guide:
 * - For automated systems (n8n, webhooks): Use `externalDeposit` with Bearer Token auth
 * - For admin dashboard: Use `adminMintCredits` with admin role validation
 * 
 * @deprecated Since 2026-01-30. Will be removed in future versions.
 */
export async function addCredits(
    data: AddCreditsRequest,
    context: CallableContext
): Promise<TransactionResponse> {
    console.warn('[DEPRECATED] addCredits called - redirecting to secure alternatives');

    throw new functions.https.HttpsError(
        'failed-precondition',
        'DEPRECATED: This function is no longer supported for security reasons. ' +
        'Use externalDeposit (for automated systems with Bearer Token) or ' +
        'adminMintCredits (for admin dashboard with admin role).'
    );
}

/**
 * ADMIN MINT CREDITS
 * Use addCredits logic but allows targeting any user.
 * (Note: Function implementation wasn't shown in previous read but assumed to exist as addCredits handles context.auth.uid. 
 *  I am keeping addCredits as is (self-add? seems weird for production but ok for logic).
 *  Wait, `addCredits` uses `context.auth.uid`. That means users can give themselves credits? 
 *  That sounds like a security flaw unless it's a dev function or restricted by security rules. 
 *  But the user asked for Admin Minting in the UI, referencing `adminMintCreditsFunction`.
 *  I will create `adminWithdrawCredits` below.)
 */

/**
 * ADMIN WITHDRAW CREDITS (Burn/Cashout)
 * 
 * Allows an admin to deduct credits from any user's wallet.
 * Reduces Total Liquidity.
 */
export async function adminWithdrawCredits(
    data: AdminWithdrawCreditsRequest,
    context: CallableContext
): Promise<TransactionResponse> {
    // 1. Validate Admin Auth
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    // 🔐 SECURITY: Enforce admin-only access
    const isAdmin = context.auth.token.admin === true;
    if (!isAdmin) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'Admin privileges required to withdraw credits from users'
        );
    }

    const { targetUid, amount, reason } = data;

    if (!targetUid) {
        throw new functions.https.HttpsError('invalid-argument', 'Target UID required');
    }
    if (!amount || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid amount: must be greater than 0');
    }

    try {
        const db = admin.firestore();
        const result = await db.runTransaction(async (transaction) => {
            const userRef = db.collection("users").doc(targetUid);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User not found");
            }

            const currentBalance = userDoc.data()?.credit || 0;

            if (currentBalance < amount) {
                throw new Error(`Insufficient user balance: ${currentBalance}`);
            }

            const newBalance = currentBalance - amount;
            const timestamp = Date.now();

            const hash = generateTransactionHash(
                targetUid,
                amount,
                "admin_debit",
                timestamp,
                currentBalance,
                newBalance
            );

            transaction.update(userRef, {
                credit: newBalance,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            const logRef = db.collection("transaction_logs").doc();
            transaction.set(logRef, {
                userId: targetUid,
                adminId: context.auth!.uid,
                amount,
                type: "admin_debit", // distinct from normal debit
                reason: reason || "Admin Withdrawal / Burn",
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                beforeBalance: currentBalance,
                afterBalance: newBalance,
                hash,
                metadata: {
                    action: "burn_liquidity"
                }
            });

            // CRÍTICO: Registrar en financial_ledger para agregación diaria
            const ledgerRef = db.collection("financial_ledger").doc();
            transaction.set(ledgerRef, {
                type: "ADMIN_BURN",
                userId: targetUid,
                adminId: context.auth!.uid,
                amount: amount, // Positive amount, type indicates direction
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                description: reason || "Admin Withdrawal / Burn"
            });

            // 4. Update Total Circulation Counter (Decrement)
            const statsRef = db.collection('system_stats').doc('economy');
            transaction.set(statsRef, {
                totalCirculation: admin.firestore.FieldValue.increment(-amount)
            }, { merge: true });

            return {
                success: true,
                newBalance,
                transactionId: logRef.id
            };
        });

        // --- N8N Webhook Trigger (WITHDRAWAL) ---
        try {
            const webhookUrl = 'https://versatec.app.n8n.cloud/webhook/70426eb0-aa5d-4f48-92f1-7d71fa8b6d3e';
            const queryParams = new URLSearchParams({
                event: 'admin_burn',
                type: 'WITHDRAWAL', // Explicit type for n8n filter
                targetUid: targetUid,
                amount: amount.toString(),
                adminUid: context.auth?.uid || 'system',
                timestamp: new Date().toISOString()
            }).toString();

            // Using GET as per user screenshot configuration
            await fetch(`${webhookUrl}?${queryParams}`);
            console.log('N8N Webhook triggered successfully (Withdrawal)');
        } catch (error) {
            console.error('N8N Webhook failed (Withdrawal):', error);
        }

        return result;
    } catch (error) {
        console.error("Error in adminWithdrawCredits:", error);
        throw new Error(`Failed to withdraw: ${(error as Error).message}`);
    }
}

/**
 * DEDUCT CREDITS - Server-Authoritative Function
 *
 * This function deducts credits from a user's wallet using atomic transactions.
 * It verifies sufficient balance before deducting to prevent negative balances.
 * IMPORTANT: Only this function can decrease user balance - clients cannot.
 *
 * Future blockchain integration: This function can create a withdrawal request
 * that triggers a blockchain transaction to send tokens to the user's wallet.
 *
 * @param data - Request data containing amount, reason, and optional metadata
 * @param context - Firebase auth context
 * @returns Transaction response with new balance
 */
export async function deductCredits(
    data: DeductCreditsRequest,
    context: CallableContext
): Promise<TransactionResponse> {
    // Validate authentication
    if (!context.auth) {
        throw new Error("Authentication required");
    }

    const userId = context.auth.uid;
    const { amount, reason, metadata } = data;

    // Validate input
    if (!amount || amount <= 0) {
        throw new Error("Invalid amount: must be greater than 0");
    }

    if (!reason || reason.trim().length === 0) {
        throw new Error("Reason is required");
    }

    try {
        const db = admin.firestore();
        // Use Firestore transaction for atomicity (prevents race conditions)
        const result = await db.runTransaction(async (transaction) => {
            const userRef = db.collection("users").doc(userId);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User not found");
            }

            const currentBalance = userDoc.data()?.credit || 0;

            // Check sufficient balance
            if (currentBalance < amount) {
                throw new Error(
                    `Insufficient balance. Current: ${currentBalance}, Required: ${amount}`
                );
            }

            const newBalance = currentBalance - amount;
            const timestamp = Date.now();

            // Generate hash for audit trail
            const hash = generateTransactionHash(
                userId,
                amount,
                "debit",
                timestamp,
                currentBalance,
                newBalance
            );

            // Update user balance
            transaction.update(userRef, {
                credit: newBalance,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Create transaction log entry (immutable audit trail)
            const logRef = db.collection("transaction_logs").doc();
            transaction.set(logRef, {
                userId,
                amount,
                type: "debit",
                reason,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                beforeBalance: currentBalance,
                afterBalance: newBalance,
                hash,
                metadata: metadata || {},
            });

            return {
                success: true,
                newBalance,
                transactionId: logRef.id,
            };
        });

        return result;
    } catch (error) {
        console.error("Error deducting credits:", error);
        throw new Error(`Failed to deduct credits: ${(error as Error).message}`);
    }
}

/**
 * Interface for withdrawCredits request
 */
interface WithdrawCreditsRequest {
    amount: number;
    walletAddress: string;
    reason?: string;
}

/**
 * ⚠️ DEPRECATED - DO NOT USE
 * 
 * This function has been deprecated for security reasons.
 * 
 * Migration Guide:
 * - Use `adminWithdrawCredits` with proper admin role validation
 * 
 * @deprecated Since 2026-01-30. Will be removed in future versions.
 */
export async function withdrawCredits(
    data: WithdrawCreditsRequest,
    context: CallableContext
): Promise<TransactionResponse> {
    console.warn('[DEPRECATED] withdrawCredits called - redirecting to adminWithdrawCredits');

    throw new functions.https.HttpsError(
        'failed-precondition',
        'DEPRECATED: This function is no longer supported for security reasons. ' +
        'Use adminWithdrawCredits with proper admin role validation instead.'
    );
}

import * as admin from "firebase-admin";
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
 * Interface for transaction response
 */
interface TransactionResponse {
    success: boolean;
    newBalance: number;
    transactionId: string;
    message?: string;
}

/**
 * ADD CREDITS - Server-Authoritative Function
 *
 * This function adds credits to a user's wallet using atomic transactions.
  * IMPORTANT: Only this function can increase user balance - clients cannot.
 *
 * Future blockchain integration: This function can be triggered by a
 * blockchain deposit listener when tokens are deposited to the game contract.
 *
 * @param data - Request data containing amount and reason
 * @param context - Firebase auth context
 * @returns Transaction response with new balance
 */
export async function addCredits(
    data: AddCreditsRequest,
    context: CallableContext
): Promise<TransactionResponse> {
    // Validate authentication
    if (!context.auth) {
        throw new Error("Authentication required");
    }

    const userId = context.auth.uid;
    const { amount, reason } = data;

    // Validate input
    if (!amount || amount <= 0) {
        throw new Error("Invalid amount: must be greater than 0");
    }

    if (!reason || reason.trim().length === 0) {
        throw new Error("Reason is required");
    }

    try {
        const db = admin.firestore();
        // Use Firestore transaction for atomicity
        const result = await db.runTransaction(async (transaction) => {
            const userRef = db.collection("users").doc(userId);
            const userDoc = await transaction.get(userRef);

            // Create user if doesn't exist (first time registration)
            if (!userDoc.exists) {
                const userData = {
                    uid: userId,
                    email: context.auth!.token.email || "",
                    displayName: context.auth!.token.name ||
                        context.auth!.token.email?.split("@")[0] || "Player",
                    photoURL: context.auth!.token.picture || "",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    credit: 0,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
                };
                transaction.set(userRef, userData);
            }

            // Get current balance
            const currentBalance = userDoc.exists ?
                (userDoc.data()?.credit || 0) : 0;
            const newBalance = currentBalance + amount;
            const timestamp = Date.now();

            // Generate hash for audit trail
            const hash = generateTransactionHash(
                userId,
                amount,
                "credit",
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
                type: "credit",
                reason,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                beforeBalance: currentBalance,
                afterBalance: newBalance,
                hash,
                metadata: {
                    authMethod: context.auth!.token.firebase?.sign_in_provider || "unknown",
                },
            });

            return {
                success: true,
                newBalance,
                transactionId: logRef.id,
            };
        });

        return result;
    } catch (error) {
        console.error("Error adding credits:", error);
        throw new Error(`Failed to add credits: ${(error as Error).message}`);
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

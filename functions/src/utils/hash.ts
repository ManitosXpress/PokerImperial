import crypto from "crypto";

/**
 * Generates a SHA-256 hash of transaction data for audit trail
 * This ensures immutability and allows future blockchain verification
 */
export function generateTransactionHash(
    userId: string,
    amount: number,
    type: "credit" | "debit",
    timestamp: number,
    beforeBalance: number,
    afterBalance: number
): string {
    const data = `${userId}|${amount}|${type}|${timestamp}|${beforeBalance}|${afterBalance}`;
    return crypto.createHash("sha256").update(data).digest("hex");
}

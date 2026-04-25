// In a real application, these package IDs would come from a configuration service,
// environment variables, or be discovered dynamically. For this example, they are hardcoded.
// You can find a package's ID by running `dpm damlc inspect-dar --json .daml/dist/<package-name>-<version>.dar`
// and looking for the `main_package_id` field.
const SOURCE_PACKAGE_ID = "d14e08374fc7197d6a0de468c9681c1345134220b225965a34e81561f5f543de"; // Example hash
const TARGET_PACKAGE_ID = "a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5a2a5"; // Example hash

/**
 * Represents the payload for a Daml JSON API v1 `exercise` command.
 */
interface ExerciseCommand {
  templateId: string;
  contractId: string;
  choice: string;
  argument: object;
}

/**
 * Custom error class for handling failures from the Daml Ledger API.
 */
export class LedgerApiError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
    public readonly errors?: string[]
  ) {
    super(message);
    this.name = "LedgerApiError";
  }
}

/**
 * A generic helper to send a command to a Daml Ledger's JSON API.
 * It handles request formation, authorization, and error parsing.
 * @param ledgerUrl The base URL of the JSON API (e.g., http://localhost:7575).
 * @param endpoint The API endpoint path (e.g., "/v1/exercise").
 * @param authToken The JWT used for authorization.
 * @param payload The command payload to be sent.
 * @returns The JSON response from the ledger API.
 */
const sendCommand = async <T extends object>(
  ledgerUrl: string,
  endpoint: string,
  authToken: string,
  payload: T
): Promise<any> => {
  const response = await fetch(`${ledgerUrl}${endpoint}`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${authToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    // Attempt to parse the error response for more detailed diagnostics
    let errorBody: { errors?: string[] } = {};
    try {
      errorBody = await response.json();
    } catch (e) {
      // The response body was not valid JSON
      console.error("Failed to parse error response from ledger API:", e);
    }
    const errorMessage = errorBody.errors?.[0] || `Ledger API request failed with status ${response.status}`;
    throw new LedgerApiError(errorMessage, response.status, errorBody.errors);
  }

  return response.json();
};

/**
 * Initiates the bridge process by locking an asset on the source domain.
 * This function exercises the `Lock` choice on an IOU contract.
 *
 * @param sourceLedgerUrl The URL of the source domain's JSON API.
 * @param authToken The user's JWT for the source domain.
 * @param assetCid The contract ID of the `Source.Asset:Iou` to be locked.
 * @param targetDomainId A string identifier for the target Canton domain.
 * @param targetRecipient The Party ID of the recipient on the target domain.
 * @returns The result of the exercise command from the ledger.
 */
export const lockAsset = async (
  sourceLedgerUrl: string,
  authToken: string,
  assetCid: string,
  targetDomainId: string,
  targetRecipient: string
): Promise<any> => {
  const command: ExerciseCommand = {
    templateId: `${SOURCE_PACKAGE_ID}:Source.Asset:Iou`,
    contractId: assetCid,
    choice: "Lock",
    argument: {
      targetDomainId,
      targetRecipient,
    },
  };

  try {
    const result = await sendCommand(sourceLedgerUrl, "/v1/exercise", authToken, command);
    console.log("Bridge lock transaction submitted successfully:", result?.result?.transactionId);
    return result;
  } catch (error) {
    console.error("Failed to lock asset for bridging:", error);
    // Re-throw the error so the UI layer can handle it (e.g., show a toast notification)
    throw error;
  }
};

/**
 * Redeems a wrapped asset on the target domain to unlock the original asset.
 * This function exercises the `RequestRedemption` choice on a `Target.Wrapped:Iou` contract.
 *
 * @param targetLedgerUrl The URL of the target domain's JSON API.
 * @param authToken The user's JWT for the target domain.
 * @param wrappedAssetCid The contract ID of the wrapped IOU to be redeemed.
 * @returns The result of the exercise command from the ledger.
 */
export const redeemAsset = async (
  targetLedgerUrl: string,
  authToken: string,
  wrappedAssetCid: string
): Promise<any> => {
  const command: ExerciseCommand = {
    templateId: `${TARGET_PACKAGE_ID}:Target.Wrapped:Iou`,
    contractId: wrappedAssetCid,
    choice: "RequestRedemption",
    argument: {}, // Assuming the choice takes no arguments
  };

  try {
    const result = await sendCommand(targetLedgerUrl, "/v1/exercise", authToken, command);
    console.log("Bridge redemption transaction submitted successfully:", result?.result?.transactionId);
    return result;
  } catch (error) {
    console.error("Failed to redeem wrapped asset:", error);
    // Re-throw for UI handling
    throw error;
  }
};
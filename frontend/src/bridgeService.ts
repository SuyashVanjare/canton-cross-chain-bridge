// Copyright (c) 2024 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

import { CreateCommand, ExerciseCommand } from '@c7/ledger';

// --- Configuration --------------------------------------------------------------------
// In a real application, these would be managed more dynamically,
// potentially fetched from a discovery service or environment variables.

const SOURCE_LEDGER_URL = process.env.REACT_APP_SOURCE_LEDGER_URL || 'http://localhost:7575';
const DEST_LEDGER_URL = process.env.REACT_APP_DEST_LEDGER_URL || 'http://localhost:8585';

// --- Types ----------------------------------------------------------------------------
// These types would ideally be generated from the Daml models using `dpm codegen-js`.
// For this example, we define them manually to match the Daml templates.

export interface Asset {
  id: string;
  symbol: string;
  quantity: string;
}

export interface LockRequestArgs {
  userParty: string;
  notaryParty: string;
  destinationParty: string;
  assetId: string;
  amount: string;
  sourceDomainId: string;
  destinationDomainId: string;
  token: string;
}

export interface RedeemRequestArgs {
  wrappedAssetCid: string;
  userParty: string;
  token: string;
}

// --- Private Helper Functions ----------------------------------------------------------

/**
 * A generic wrapper for making authenticated requests to a Daml Ledger JSON API.
 * @param ledgerUrl The base URL of the JSON API.
 * @param endpoint The API endpoint to hit (e.g., 'create', 'exercise').
 * @param token The JWT token for authentication.
 * @param command The command payload.
 * @returns The JSON response from the ledger.
 * @throws An error if the network request fails or the ledger returns a non-200 status.
 */
async function submitLedgerCommand<T>(
  ledgerUrl: string,
  endpoint: 'create' | 'exercise',
  token: string,
  command: CreateCommand | ExerciseCommand
): Promise<T> {
  const response = await fetch(`${ledgerUrl}/v1/${endpoint}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(command),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`Ledger command failed with status ${response.status}:`, errorBody);
    throw new Error(`Ledger command failed: ${response.statusText} - ${errorBody}`);
  }

  return response.json() as Promise<T>;
}

// --- Public Service Functions ---------------------------------------------------------

/**
 * Initiates the asset locking process on the source domain.
 * This creates a `LockRequest` contract which the notary will observe.
 *
 * @param args The arguments required to create the lock request.
 * @returns The result of the create command from the ledger.
 */
export const lockAsset = async (args: LockRequestArgs) => {
  const {
    userParty,
    notaryParty,
    destinationParty,
    assetId,
    amount,
    sourceDomainId,
    destinationDomainId,
    token
  } = args;

  const createCommand: CreateCommand = {
    templateId: 'BridgeNotary:LockRequest',
    payload: {
      owner: userParty,
      notary: notaryParty,
      destinationParty: destinationParty,
      assetId: assetId,
      amount: amount,
      sourceDomainId: sourceDomainId,
      destinationDomainId: destinationDomainId,
    },
  };

  console.log("Submitting LockRequest to source domain:", SOURCE_LEDGER_URL);
  console.log("Payload:", JSON.stringify(createCommand.payload, null, 2));

  return submitLedgerCommand(SOURCE_LEDGER_URL, 'create', token, createCommand);
};

/**
 * Initiates the asset redemption process on the destination domain.
 * This exercises the `RequestBurn` choice on a `WrappedAsset` contract,
 * creating a `BurnRequest` that the notary will observe to unlock the
 * original asset on the source domain.
 *
 * @param args The arguments required for the redemption request.
 * @returns The result of the exercise command from the ledger.
 */
export const redeemAsset = async (args: RedeemRequestArgs) => {
  const { wrappedAssetCid, userParty, token } = args;

  const exerciseCommand: ExerciseCommand = {
    templateId: 'BurnRedemption:WrappedAsset',
    contractId: wrappedAssetCid,
    choice: 'RequestBurn',
    argument: {},
    meta: {
      actAs: [userParty],
    },
  };

  console.log("Submitting RequestBurn to destination domain:", DEST_LEDGER_URL);
  console.log("Command:", JSON.stringify(exerciseCommand, null, 2));

  return submitLedgerCommand(DEST_LEDGER_URL, 'exercise', token, exerciseCommand);
};
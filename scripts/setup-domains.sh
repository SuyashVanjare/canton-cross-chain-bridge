#!/usr/bin/env bash

# This script automates the setup of a local two-domain Canton network
# for testing the canton-cross-chain-bridge project.
#
# It performs the following steps:
# 1. Builds the Daml project to produce a DAR file.
# 2. Creates a temporary directory (.canton-local) for Canton configuration and data.
# 3. Generates a Canton configuration file for two participants and two domains.
# 4. Generates a Canton bootstrap script to initialize the network, upload the DAR,
#    and allocate necessary parties.
# 5. Starts Canton in the background.
# 6. Waits for the network to be ready and prints connection details.
# 7. Tails the Canton log file. Press Ctrl+C to shut down and clean up.

set -euo pipefail

# --- Configuration ---
# These should match the 'name' and 'version' in your daml.yaml
PROJECT_NAME="canton-cross-chain-bridge"
PROJECT_VERSION="0.1.0"

# Directory for all Canton-related files and state
CANTON_DIR=".canton-local"

# File paths
CANTON_LOG="${CANTON_DIR}/canton.log"
CANTON_CONF="${CANTON_DIR}/bridge.conf"
CANTON_BOOTSTRAP="${CANTON_DIR}/bootstrap.canton"

# Network Ports
SOURCE_PARTICIPANT_ADMIN_PORT=5012
SOURCE_PARTICIPANT_LEDGER_PORT=6866
TARGET_PARTICIPANT_ADMIN_PORT=5022
TARGET_PARTICIPANT_LEDGER_PORT=6867

# --- Cleanup Logic ---
CANTON_PID=""
function cleanup {
  if [ -n "$CANTON_PID" ]; then
    echo ""
    echo "Shutting down Canton network (PID: ${CANTON_PID})..."
    kill "$CANTON_PID" || true
    # Wait for the process to terminate gracefully
    wait "$CANTON_PID" 2>/dev/null || true
  fi
  echo "Cleanup complete."
}
trap cleanup EXIT INT TERM

# --- Main Script ---

echo "▶️  Building Daml project..."
dpm build

DAR_PATH=$(find .daml/dist -name "${PROJECT_NAME}-${PROJECT_VERSION}.dar")
if [ ! -f "$DAR_PATH" ]; then
    echo "❌ Error: DAR file not found for ${PROJECT_NAME}-${PROJECT_VERSION}"
    echo "Please check your daml.yaml configuration."
    exit 1
fi
# Canton requires an absolute path for DAR uploads in the bootstrap script.
DAR_PATH_ABS=$(realpath "$DAR_PATH")
echo "✅ Found DAR at: ${DAR_PATH_ABS}"


echo "▶️  Configuring local Canton environment in '${CANTON_DIR}'..."
rm -rf "${CANTON_DIR}"
mkdir -p "${CANTON_DIR}"


echo "    - Generating Canton configuration file: ${CANTON_CONF}"
cat > "${CANTON_CONF}" <<EOF
// Canton configuration for a two-domain bridge setup
canton {
  participants {
    source-participant {
      storage.type = memory
      admin-api.port = ${SOURCE_PARTICIPANT_ADMIN_PORT}
      ledger-api.port = ${SOURCE_PARTICIPANT_LEDGER_PORT}
    }
    target-participant {
      storage.type = memory
      admin-api.port = ${TARGET_PARTICIPANT_ADMIN_PORT}
      ledger-api.port = ${TARGET_PARTICIPANT_LEDGER_PORT}
    }
  }

  domains {
    source-domain {
      storage.type = memory
      public-api.port = 5013
      admin-api.port = 5014
      mediator.admin-api.port = 5015
      sequencer {
        admin-api.port = 5016
        public-api.port = 5017
      }
    }
    target-domain {
      storage.type = memory
      public-api.port = 5023
      admin-api.port = 5024
      mediator.admin-api.port = 5025
      sequencer {
        admin-api.port = 5026
        public-api.port = 5027
      }
    }
  }
}
EOF


echo "    - Generating Canton bootstrap script: ${CANTON_BOOTSTRAP}"
cat > "${CANTON_BOOTSTRAP}" <<EOF
// Canton bootstrap script for initializing the bridge network

// Start all nodes defined in the config
println("Starting all Canton nodes...")
source_participant.start()
target_participant.start()
source_domain.start()
target_domain.start()

// Wait for them to be active
println("Waiting for nodes to become active...")
source_participant.health.wait_for_active()
target_participant.health.wait_for_active()
source_domain.health.wait_for_running()
target_domain.health.wait_for_running()
println("All nodes are active.")

// Connect participants to their respective domains
println("Connecting participants to domains...")
source_participant.domains.connect_local(source_domain)
target_participant.domains.connect_local(target_domain)
source_participant.domains.enable(source_domain.id)
target_participant.domains.enable(target_domain.id)
println("Domain connections enabled.")

// Upload the DAR to both participants
println("Uploading DAR to participants...")
source_participant.dars.upload("${DAR_PATH_ABS}", vetAllPackages = true)
target_participant.dars.upload("${DAR_PATH_ABS}", vetAllPackages = true)
println("DARs uploaded successfully.")

// Allocate parties required for the bridge workflow
println("Allocating parties...")
val alice = source_participant.parties.allocate(partyId="Alice", displayName="Alice")
val notary = target_participant.parties.allocate(partyId="Notary", displayName="Notary")
val bob = target_participant.parties.allocate(partyId="Bob", displayName="Bob")
println("Parties allocated.")

// Print out final connection details for other scripts and applications
println("============================================================")
println(" ✅ Canton Bridge Environment is Ready")
println("============================================================")
println(s"Source Participant (source-domain):")
println(s"  - Ledger API Port:  ${SOURCE_PARTICIPANT_LEDGER_PORT}")
println(s"  - Allocated Party:  \${alice.party} (Alice)")
println(s"Target Participant (target-domain):")
println(s"  - Ledger API Port:  ${TARGET_PARTICIPANT_LEDGER_PORT}")
println(s"  - Allocated Parties: \${notary.party} (Notary)")
println(s"                       \${bob.party} (Bob)")
println("------------------------------------------------------------")
println(" Log file available at: ${CANTON_LOG}")
println(" Press Ctrl+C to shut down the network.")
println("============================================================")
EOF


echo "▶️  Starting Canton network in the background..."
# Start Canton, redirecting all output to the log file.
# The '&' runs it in the background.
canton -c "${CANTON_CONF}" --bootstrap "${CANTON_BOOTSTRAP}" > "${CANTON_LOG}" 2>&1 &
CANTON_PID=$!
echo "✅ Canton process started with PID: ${CANTON_PID}"

echo "▶️  Waiting for network setup to complete... (this may take a minute)"
# Wait for the success message from our bootstrap script to appear in the log.
# This is a robust way to know the network is fully initialized.
# Timeout after 2 minutes to prevent hanging indefinitely.
if timeout 120s tail -f "${CANTON_LOG}" | grep -qe "Press Ctrl+C to shut down the network."; then
    # Clear the line from tail/grep and show final status
    echo ""
    echo "✅ Network is up and running."
    echo ""
else
    echo "❌ Canton startup timed out after 120 seconds."
    echo "    Please check the log file for errors: ${CANTON_LOG}"
    exit 1
fi

# Keep this script running to hold the Canton process.
# When the user hits Ctrl+C, the trap will execute the cleanup function.
echo "Tailing Canton log. Press Ctrl+C to stop."
echo "------------------------------------------"
tail -f "${CANTON_LOG}" &
wait "$CANTON_PID"
#!/bin/bash

set -euo pipefail

# --- Configuration ---
CANTON_VERSION="3.4.0"
PROJECT_NAME="canton-cross-chain-bridge"
PROJECT_VERSION="0.1.0"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
DAR_PATH="$PROJECT_ROOT/.daml/dist/${PROJECT_NAME}-${PROJECT_VERSION}.dar"
CONFIG_DIR="$SCRIPT_DIR/.generated-config"
CONFIG_FILE="$CONFIG_DIR/bridge-dev.conf"
SCRIPT_FILE="$CONFIG_DIR/bridge-dev.canton"
PORT_DIR="$CONFIG_DIR/.ports"
CANTON_PID_FILE="$CONFIG_DIR/canton.pid"

# Participant Ports
P1_ADMIN_PORT=5012
P1_LEDGER_API_PORT=6866
P1_JSON_API_PORT=7575
P2_ADMIN_PORT=5022
P2_LEDGER_API_PORT=6876
P2_JSON_API_PORT=7576
P3_ADMIN_PORT=5032
P3_LEDGER_API_PORT=6886
P3_JSON_API_PORT=7577

# --- Helper Functions ---
function cleanup {
  echo "--- Shutting down Canton ---"
  if [ -f "$CANTON_PID_FILE" ]; then
    kill "$(cat "$CANTON_PID_FILE")" || true
    rm -f "$CANTON_PID_FILE"
  else
    # Fallback if pid file wasn't created
    pkill -f "bridge-dev.conf" || true
  fi
  # Clean up generated files
  rm -rf "$CONFIG_DIR"
  echo "--- Cleanup complete ---"
}

trap cleanup EXIT

# --- Main Script ---

echo "--- Starting Canton Bridge Setup ---"

# 1. Check prerequisites
if ! command -v dpm &> /dev/null
then
    echo "DPM (dpm) command not found."
    echo "Please install the Daml SDK version ${CANTON_VERSION} or later."
    exit 1
fi
if [ ! -f "$DAR_PATH" ]; then
    echo "DAR file not found at: $DAR_PATH"
    echo "Please build the project first by running 'dpm build' in the project root."
    exit 1
fi

# 2. Prepare directories and kill any old processes
echo "--- Preparing environment ---"
cleanup # Run cleanup first to stop any lingering processes
mkdir -p "$CONFIG_DIR"
mkdir -p "$PORT_DIR"


# 3. Generate Canton configuration file
echo "--- Generating Canton config file at $CONFIG_FILE ---"
cat > "$CONFIG_FILE" << EOF
// Canton configuration for a two-domain bridge setup
canton {
  participants {
    participant_source {
      admin-api.port = ${P1_ADMIN_PORT}
      ledger-api {
        port = ${P1_LEDGER_API_PORT}
        json-api.port = ${P1_JSON_API_PORT}
        json-api.port-file = "${PORT_DIR}/participant_source.port"
      }
      storage.type = memory
    }
    participant_target {
      admin-api.port = ${P2_ADMIN_PORT}
      ledger-api {
        port = ${P2_LEDGER_API_PORT}
        json-api.port = ${P2_JSON_API_PORT}
        json-api.port-file = "${PORT_DIR}/participant_target.port"
      }
      storage.type = memory
    }
    participant_notary {
      admin-api.port = ${P3_ADMIN_PORT}
      ledger-api {
        port = ${P3_LEDGER_API_PORT}
        json-api.port = ${P3_JSON_API_PORT}
        json-api.port-file = "${PORT_DIR}/participant_notary.port"
      }
      storage.type = memory
    }
  }

  domains {
    source_domain {
      storage.type = memory
      public-api.port = 5014
      admin-api.port = 5013
      sequencer.type = in-process
      mediator.type = in-process
    }
    target_domain {
      storage.type = memory
      public-api.port = 5024
      admin-api.port = 5023
      sequencer.type = in-process
      mediator.type = in-process
    }
    notary_domain {
      storage.type = memory
      public-api.port = 5034
      admin-api.port = 5033
      sequencer.type = in-process
      mediator.type = in-process
    }
  }
}
EOF

# 4. Generate Canton setup script
echo "--- Generating Canton setup script at $SCRIPT_FILE ---"
cat > "$SCRIPT_FILE" << EOF
// Wait for all nodes to start
println("Waiting for Canton nodes to start...")
Seq(participant_source, participant_target, participant_notary, source_domain, target_domain, notary_domain).foreach(_.health.wait_for_running())
println("All nodes are running.")

// Define domain IDs and connect participants
println("Connecting participants to domains...")
val sourceId = DomainId.tryFromString("source-domain::ffffffff")
val targetId = DomainId.tryFromString("target-domain::ffffffff")
val notaryId = DomainId.tryFromString("notary-domain::ffffffff")

source_domain.domains.set_id(sourceId)
target_domain.domains.set_id(targetId)
notary_domain.domains.set_id(notaryId)

source_domain.participants.connect(participant_source, ParticipantPermission.Submission)
target_domain.participants.connect(participant_target, ParticipantPermission.Submission)

// The notary needs to see both source and target domains
source_domain.participants.connect(participant_notary, ParticipantPermission.Observation)
target_domain.participants.connect(participant_notary, ParticipantPermission.Submission)
notary_domain.participants.connect(participant_notary, ParticipantPermission.Submission)

println("Enabling domains for participants...")
participant_source.domains.enable(sourceId)
participant_target.domains.enable(targetId)
participant_notary.domains.enable(sourceId)
participant_notary.domains.enable(targetId)
participant_notary.domains.enable(notaryId)

// Upload the bridge DAR to all participants
println("Uploading DAR to participants...")
val dar = καλύτερα.files.path_from_string("${DAR_PATH}")
participant_source.dars.upload(dar)
participant_target.dars.upload(dar)
participant_notary.dars.upload(dar)

// Allocate parties for the demo
println("Allocating parties...")
val alice = participant_source.parties.enable("Alice")
val bob = participant_target.parties.enable("Bob")
val bridgeOperator = participant_notary.parties.enable("BridgeOperator")
val sourceBank = participant_source.parties.enable("SourceBank")
val targetBank = participant_target.parties.enable("TargetBank")

// --- Setup Complete ---
println("\n" + "="*50)
println("CANTON BRIDGE ENVIRONMENT IS READY")
println("="*50 + "\n")

println("Participants:")
println(s"  - Source Participant Ledger API:  localhost:${P1_LEDGER_API_PORT}")
println(s"  - Source Participant JSON API:    http://localhost:${P1_JSON_API_PORT}")
println(s"  - Target Participant Ledger API:  localhost:${P2_LEDGER_API_PORT}")
println(s"  - Target Participant JSON API:    http://localhost:${P2_JSON_API_PORT}")
println(s"  - Notary Participant Ledger API:  localhost:${P3_LEDGER_API_PORT}")
println(s"  - Notary Participant JSON API:    http://localhost:${P3_JSON_API_PORT}")
println("\nParties:")
println(s"  - Alice:        \${alice.toLf} (hosted on Source Participant)")
println(s"  - Bob:          \${bob.toLf} (hosted on Target Participant)")
println(s"  - BridgeOperator: \${bridgeOperator.toLf} (hosted on Notary Participant)")
println(s"  - SourceBank:     \${sourceBank.toLf} (hosted on Source Participant)")
println(s"  - TargetBank:     \${targetBank.toLf} (hosted on Target Participant)")
println("\n" + "="*50)
println("Press Ctrl+C to shut down.")
EOF

# 5. Start Canton in the background
echo "--- Starting Canton process ---"
# The --bootstrap-script option will automatically run the script when Canton is ready.
# This is more reliable than using sleep and a separate `canton --script` command.
dpm canton -- \
  -c "$CONFIG_FILE" \
  --bootstrap-script "$SCRIPT_FILE" \
  --bootstrap-script-config.timeout=60s \
  &

CANTON_PID=$!
echo "$CANTON_PID" > "$CANTON_PID_FILE"
echo "--- Canton process started with PID $CANTON_PID ---"
echo "--- Waiting for bootstrap to complete (see Canton logs) ---"

# 6. Wait for the Canton process to exit
wait "$CANTON_PID"
exit_code=$?
echo "--- Canton process exited with code $exit_code ---"
exit $exit_code
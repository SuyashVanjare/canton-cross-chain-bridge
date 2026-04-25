import React from 'react';
import { DamlLedger } from '@c7/react';
import { BridgeWidget } from './BridgeWidget';
import './App.css';

// --- Configuration ---
// In a real application, these values would be managed by a robust configuration system
// and authentication flow (e.g., OAuth2). For this example, we use environment variables,
// which is a common practice for development and internal tools.
const SOURCE_JSON_API_URL = process.env.REACT_APP_SOURCE_JSON_API_URL || 'http://localhost:7575';
const TARGET_JSON_API_URL = process.env.REACT_APP_TARGET_JSON_API_URL || 'http://localhost:7576';

// These must be set in a `.env.local` file in the `frontend` directory for local development.
// e.g., REACT_APP_SOURCE_PARTY_ID=Alice::1220...
const SOURCE_PARTY_ID = process.env.REACT_APP_SOURCE_PARTY_ID;
const SOURCE_AUTH_TOKEN = process.env.REACT_APP_SOURCE_AUTH_TOKEN;

const TARGET_PARTY_ID = process.env.REACT_APP_TARGET_PARTY_ID;
const TARGET_AUTH_TOKEN = process.env.REACT_APP_TARGET_AUTH_TOKEN;
// --- End Configuration ---


/**
 * A simple validation component to ensure the required environment variables are set.
 * This provides helpful feedback to developers during setup.
 */
const ConfigGuard: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const missingVars = [
    !SOURCE_PARTY_ID && 'REACT_APP_SOURCE_PARTY_ID',
    !SOURCE_AUTH_TOKEN && 'REACT_APP_SOURCE_AUTH_TOKEN',
    !TARGET_PARTY_ID && 'REACT_APP_TARGET_PARTY_ID',
    !TARGET_AUTH_TOKEN && 'REACT_APP_TARGET_AUTH_TOKEN',
  ].filter(Boolean);

  if (missingVars.length > 0) {
    return (
      <div className="config-error-container">
        <div className="config-error-card">
          <h2>Configuration Error</h2>
          <p>The following required environment variables are not set:</p>
          <ul>
            {missingVars.map(v => <li key={v}><code>{v}</code></li>)}
          </ul>
          <p>
            Please create a <code>.env.local</code> file in the <code>frontend</code> directory and define them.
            You can generate party-specific JWTs using the Canton console or other tooling.
          </p>
          <p>Example <code>.env.local</code>:</p>
          <pre>
            REACT_APP_SOURCE_PARTY_ID=Alice::1220...<br />
            REACT_APP_SOURCE_AUTH_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...<br />
            REACT_APP_TARGET_PARTY_ID=Alice::1220...<br />
            REACT_APP_TARGET_AUTH_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
          </pre>
        </div>
      </div>
    );
  }

  return <>{children}</>;
};


/**
 * The main application component for the Canton Cross-Domain Bridge.
 *
 * This component sets up the primary dashboard layout, which is split into two sections:
 * one for the source domain and one for the target domain.
 *
 * A key architectural choice here is the use of two separate `DamlLedger` context providers.
 * Each provider is configured for a specific Canton domain (participant node). This allows
 * components within each section (like `BridgeWidget`) to use `@c7/react` hooks
 * (`useParty`, `useLedger`, `useStreamQueries`) that are automatically scoped to the correct
 * domain.
 *
 * Cross-domain actions are handled by passing the connection details of the "other" domain
 * as props to the `BridgeWidget`, which then uses a service layer (`bridgeService.ts`) to
 * make direct JSON API calls when needed (e.g., notifying the target domain of a lock on the source).
 */
const App: React.FC = () => {
  return (
    <ConfigGuard>
      <div className="app-container">
        <header className="app-header">
          <h1>Canton Cross-Domain Asset Bridge</h1>
          <p>An interface for locking assets on a source domain and minting wrapped representations on a target domain.</p>
        </header>

        <main className="bridge-dashboard">
          {/* Source Domain View */}
          <DamlLedger
            party={SOURCE_PARTY_ID!}
            token={SOURCE_AUTH_TOKEN!}
            httpBaseUrl={SOURCE_JSON_API_URL}
          >
            <div className="domain-container">
              <div className="domain-header">
                <h2>Source Domain</h2>
                <span className="domain-url">{SOURCE_JSON_API_URL}</span>
              </div>
              <BridgeWidget
                domainType="source"
                counterpartyConfig={{
                  partyId: TARGET_PARTY_ID!,
                  token: TARGET_AUTH_TOKEN!,
                  httpBaseUrl: TARGET_JSON_API_URL,
                }}
              />
            </div>
          </DamlLedger>

          {/* Target Domain View */}
          <DamlLedger
            party={TARGET_PARTY_ID!}
            token={TARGET_AUTH_TOKEN!}
            httpBaseUrl={TARGET_JSON_API_URL}
          >
            <div className="domain-container">
              <div className="domain-header">
                <h2>Target Domain</h2>
                <span className="domain-url">{TARGET_JSON_API_URL}</span>
              </div>
              <BridgeWidget
                domainType="target"
                counterpartyConfig={{
                  partyId: SOURCE_PARTY_ID!,
                  token: SOURCE_AUTH_TOKEN!,
                  httpBaseUrl: SOURCE_JSON_API_URL,
                }}
              />
            </div>
          </DamlLedger>
        </main>

        <footer className="app-footer">
          <p>Powered by <a href="https://www.digitalasset.com/canton" target="_blank" rel="noopener noreferrer">Canton</a> and <a href="https://www.daml.com" target="_blank" rel="noopener noreferrer">Daml</a></p>
        </footer>
      </div>
    </ConfigGuard>
  );
};

export default App;
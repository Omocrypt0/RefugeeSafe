# 🛡️ RefugeeSafe

**A social recovery wallet for displaced persons, built on the [Stacks](https://www.stacks.co/) blockchain in [Clarity](https://docs.stacks.co/clarity/overview).**

RefugeeSafe gives displaced individuals a secure, self-custodied STX wallet that can be recovered without seed phrases — using a network of trusted aid workers, advocates, or family members as co-signers. No bank. No middleman. No lost-forever funds.

---

## 🌍 Why RefugeeSafe?

Displaced persons — refugees, asylum seekers, and internally displaced people — often lose access to identity documents, phones, and financial accounts during crises. Traditional wallets rely on seed phrases that are easy to lose or destroy. RefugeeSafe replaces that single point of failure with **human trust networks**: the same aid workers, NGO advocates, and community contacts already present in displacement contexts.

---

## ✨ Features

- **Self-custodied STX wallet** — only the owner can send funds under normal conditions
- **Social recovery** — trusted contacts can collectively restore access to a new address
- **Configurable threshold** — owner sets how many contacts must agree (e.g. 2-of-5)
- **24-hour lock period** — standard recovery has a built-in delay to prevent rushed or coerced takeovers
- **Emergency fast-track** — unanimous approval bypasses the lock period for genuine crises
- **Contact labels** — each trusted contact carries a human-readable role (e.g. `"UNHCR Field Worker"`)
- **Recovery cancellation** — the owner can cancel any recovery attempt they didn't authorise
- **Transfer freeze** — funds cannot be moved while a recovery is in progress

---

## 🏗️ Architecture

```
RefugeeSafe.clar
│
├── State
│   ├── wallet-owner          → the displaced person's principal
│   ├── recovery-threshold    → votes needed to complete recovery
│   ├── trusted-contacts      → map of approved aid workers / advocates
│   ├── contact-label         → human-readable role per contact
│   ├── recovery-active       → bool flag for ongoing recovery
│   ├── recovery-candidate    → proposed new owner address
│   ├── recovery-initiated-at → block height when recovery started
│   └── recovery-votes        → current vote count
│
├── Owner Functions
│   ├── initialize            → set owner and threshold at deploy time
│   ├── add-trusted-contact   → add an aid worker with a role label
│   ├── remove-trusted-contact
│   ├── set-threshold         → update the approval quorum
│   ├── deposit               → send STX into the wallet
│   ├── send-stx              → send STX out (blocked during recovery)
│   └── cancel-recovery       → abort an active recovery attempt
│
├── Social Recovery Functions
│   ├── initiate-recovery     → trusted contact proposes a new owner
│   ├── approve-recovery      → other contacts cast their vote
│   ├── execute-recovery      → finalise after lock period + threshold met
│   └── execute-emergency-recovery → unanimous fast-track (no lock period)
│
└── Read-Only Functions
    ├── get-owner / get-threshold / get-trusted-count / get-balance
    ├── is-trusted / get-contact-label
    ├── is-recovery-active / get-recovery-candidate / get-recovery-votes
    └── has-voted
```

---

## 🔄 Recovery Flows

### Standard Recovery (~24 hours)

```
1. Trusted contact calls  → initiate-recovery(<new-address>)
                             (their vote is cast automatically)

2. Other trusted contacts → approve-recovery()
                             (until threshold is reached)

3. After 144 blocks (~24h) → execute-recovery()
                             (anyone can call once conditions are met)

4. Ownership transfers to the new address.
```

### Emergency Recovery (instant, unanimous)

```
1. Trusted contact calls  → initiate-recovery(<new-address>)

2. ALL remaining trusted contacts → approve-recovery()

3. Immediately              → execute-emergency-recovery()
                             (no lock period required)
```

### Cancellation

If the real owner still has access and a bad-faith recovery is initiated:

```
Owner calls → cancel-recovery()
```
This resets all votes and clears the recovery state instantly.

---

## 🚀 Deployment

### Prerequisites

- [Clarinet](https://docs.hiro.so/clarinet/getting-started) installed
- A Stacks wallet (e.g. [Leather](https://leather.io/)) for mainnet/testnet

### Local Development

```bash
# Create a new Clarinet project
clarinet new refugee-safe
cd refugee-safe

# Copy the contract
cp RefugeeSafe.clar contracts/

# Run tests
clarinet check        # syntax & type check
clarinet console      # interactive REPL
```

### Initialize the Contract

After deploying, call `initialize` once to set the wallet owner and recovery threshold:

```clarity
(contract-call? .refugee-safe initialize 'SP1ABC...OWNER u2)
```

> ⚠️ `initialize` can only be called by the deployer (`CONTRACT-OWNER`). Call it in the same transaction block as deployment, or immediately after.

### Add Trusted Contacts

```clarity
(contract-call? .refugee-safe add-trusted-contact 'SP2DEF...AIDWORKER "UNHCR Field Officer")
(contract-call? .refugee-safe add-trusted-contact 'SP3GHI...ADVOCATE  "IRC Case Manager")
(contract-call? .refugee-safe add-trusted-contact 'SP4JKL...FAMILY    "Sister - Nairobi")
```

### Set Threshold

```clarity
;; Require 2-of-3 contacts to approve recovery
(contract-call? .refugee-safe set-threshold u2)
```

---

## 📋 Function Reference

### Owner-Only

| Function | Parameters | Description |
|---|---|---|
| `initialize` | `owner principal`, `threshold uint` | Set wallet owner and recovery quorum |
| `add-trusted-contact` | `contact principal`, `label string-ascii` | Register an aid worker / advocate |
| `remove-trusted-contact` | `contact principal` | Remove a trusted contact |
| `set-threshold` | `new-threshold uint` | Update the recovery quorum |
| `deposit` | `amount uint` | Deposit STX into the wallet |
| `send-stx` | `recipient principal`, `amount uint` | Send STX (blocked during recovery) |
| `cancel-recovery` | — | Abort an active recovery |

### Trusted Contacts

| Function | Parameters | Description |
|---|---|---|
| `initiate-recovery` | `new-owner principal` | Start recovery, cast first vote |
| `approve-recovery` | — | Cast an approval vote |
| `execute-recovery` | — | Finalise after lock period + threshold met |
| `execute-emergency-recovery` | — | Instant recovery if all contacts voted |

### Read-Only

| Function | Returns | Description |
|---|---|---|
| `get-owner` | `principal` | Current wallet owner |
| `get-threshold` | `uint` | Recovery vote threshold |
| `get-trusted-count` | `uint` | Number of trusted contacts |
| `get-balance` | `uint` | Contract STX balance |
| `is-trusted` | `bool` | Check if a principal is a trusted contact |
| `get-contact-label` | `optional string` | Get a contact's role label |
| `is-recovery-active` | `bool` | Whether recovery is in progress |
| `get-recovery-candidate` | `principal` | Proposed new owner address |
| `get-recovery-votes` | `uint` | Current vote count |
| `has-voted` | `bool` | Whether a contact has voted this round |

---

## 🚨 Error Codes

| Code | Constant | Meaning |
|---|---|---|
| `u100` | `ERR-NOT-OWNER` | Caller is not the wallet owner |
| `u101` | `ERR-NOT-TRUSTED` | Caller is not a trusted contact |
| `u102` | `ERR-ALREADY-TRUSTED` | Contact is already registered |
| `u103` | `ERR-NOT-FOUND` | Contact not found |
| `u104` | `ERR-ALREADY-VOTED` | This contact already voted this round |
| `u105` | `ERR-RECOVERY-ACTIVE` | A recovery is already in progress |
| `u106` | `ERR-NO-RECOVERY-ACTIVE` | No recovery is currently active |
| `u107` | `ERR-THRESHOLD-NOT-MET` | Not enough votes yet |
| `u108` | `ERR-UNAUTHORIZED` | Lock period has not passed |
| `u109` | `ERR-INVALID-THRESHOLD` | Threshold must be > 0 and ≤ trusted count |
| `u110` | `ERR-MAX-TRUSTED` | Maximum of 10 trusted contacts reached |
| `u111` | `ERR-INSUFFICIENT-FUNDS` | Wallet balance too low |
| `u112` | `ERR-SELF-TRUST` | Owner cannot add themselves as a contact |

---

## 🔒 Security Considerations

- **Threshold carefully**: A threshold of 1 means a single contact can recover the wallet. For high-value wallets, use at least 2-of-3 or 3-of-5.
- **Vet your contacts**: Add only people you genuinely trust. A malicious contact can initiate recovery, though they still need others to reach the threshold.
- **Lock period is a safeguard**: The 24-hour window gives the owner time to notice and cancel an unauthorised attempt.
- **Transfers are frozen during recovery**: Funds cannot be moved while a recovery is active, preventing a race-condition drain.
- **No admin backdoor**: The contract deployer has no special ongoing powers after `initialize` is called.

---

## 🤝 Contributing

Contributions, audits, and translations welcome. If you work in a humanitarian context and want to adapt this contract for a specific deployment, please open an issue.
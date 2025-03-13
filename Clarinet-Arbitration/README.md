# Dispute Resolution Smart Contract

A Clarity smart contract for handling dispute resolution on the Stacks blockchain.

## Overview

This smart contract provides a decentralized dispute resolution system where parties can create disputes, submit evidence, and have a designated arbiter resolve the conflict. The contract handles the escrow of funds and distributes them according to the arbiter's decision.

## Features

- **Dispute Creation**: Users can create disputes by specifying the respondent, arbiter, disputed amount, and relevant timeframes.
- **Evidence Submission**: Both parties can submit evidence during the evidence period.
- **Arbitration**: A designated arbiter reviews evidence and resolves the dispute.
- **Automatic Resolution**: If the arbiter fails to respond within the deadline, the contract automatically splits the funds.
- **Configurable Timeframes**: Evidence and resolution periods can be customized for each dispute.
- **Arbitration Fees**: Arbiters are compensated for their services through predefined fees.
- **Dispute Cancellation**: Disputes can be cancelled if not yet accepted by the respondent.

## Contract Structure

### Error Constants

```
ERR_NOT_AUTHORIZED       - Caller is not authorized for the operation
ERR_INVALID_DISPUTE      - Invalid dispute parameters
ERR_DISPUTE_NOT_FOUND    - Referenced dispute doesn't exist
ERR_ALREADY_RESOLVED     - Dispute has already been resolved
ERR_INSUFFICIENT_FUNDS   - Insufficient funds for the operation
ERR_INVALID_STATUS       - Operation not allowed in current status
ERR_NO_RESOLUTION        - No resolution has been provided
ERR_TIMEOUT_NOT_REACHED  - Timeout period has not elapsed
ERR_INVALID_ARBITER      - Invalid arbiter assignment
```

### Status Constants

```
STATUS_PENDING        - Dispute created but not yet accepted
STATUS_EVIDENCE_PERIOD - Evidence collection period
STATUS_DELIBERATION    - Arbiter is reviewing evidence
STATUS_RESOLVED        - Dispute has been resolved
STATUS_CANCELLED       - Dispute has been cancelled
```

### Resolution Types

```
RESOLUTION_CLAIMANT_WINS   - Claimant wins the dispute
RESOLUTION_RESPONDENT_WINS - Respondent wins the dispute
RESOLUTION_SPLIT           - Disputed amount is split between parties
```

## Public Functions

### Administration
- `initialize(new-owner, fee)` - Initialize contract with owner and arbitration fee

### Dispute Lifecycle
- `create-dispute(respondent, arbiter, amount, evidence-period, resolution-period, description)` - Create a new dispute
- `accept-dispute(dispute-id)` - Respondent accepts a dispute
- `submit-evidence(dispute-id, evidence-hash)` - Submit evidence to a dispute
- `close-evidence-period(dispute-id)` - Close the evidence period and start deliberation
- `resolve-dispute(dispute-id, resolution-type)` - Arbiter resolves a dispute
- `cancel-dispute(dispute-id)` - Claimant cancels a dispute (only if not accepted)
- `force-timeout-resolution(dispute-id)` - Force resolution if arbiter doesn't respond in time

### Read-Only Functions
- `get-dispute(dispute-id)` - Get dispute details
- `get-evidence(dispute-id, party)` - Get evidence submitted by a party
- `get-arbitration-fee()` - Get current arbitration fee
- `get-owner()` - Get contract owner
- `get-dispute-count()` - Get total number of disputes

## Usage Examples

### Creating a Dispute

```clarity
(contract-call? .dispute-resolution create-dispute 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM 
  'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG 
  u1000 
  u144 
  u144 
  "Product not delivered as described"
)
```

### Accepting a Dispute

```clarity
(contract-call? .dispute-resolution accept-dispute u1)
```

### Submitting Evidence

```clarity
(contract-call? .dispute-resolution submit-evidence 
  u1 
  "QmT5NvUtoM5nWFfrQdVrFtvGfKFmG7AHE8P34isapyhCxX"
)
```

### Resolving a Dispute

```clarity
(contract-call? .dispute-resolution resolve-dispute
  u1
  u1 ;; RESOLUTION_CLAIMANT_WINS
)
```

## Fee Structure

- The contract charges an arbitration fee that is paid by both the claimant and respondent.
- If the arbiter resolves the dispute within the deadline, they receive both arbitration fees.
- If the arbiter fails to respond in time, the arbitration fees are refunded to the parties.

## Security Considerations

- The contract includes strict authorization checks to ensure only authorized parties can perform specific actions.
- Timeouts are implemented to prevent disputes from being stuck indefinitely.
- The contract handles proper escrow of funds during the dispute lifecycle.
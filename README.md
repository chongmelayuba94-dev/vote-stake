# VoteStake - Weighted Voting System

A decentralized voting platform built on Stacks blockchain where voting power is determined by token staking amounts.

## Overview

VoteStake implements a weighted decision-making system where participants can:
- Stake tokens to gain voting power
- Create and participate in governance proposals
- Vote with weight proportional to their stake
- Manage staking positions and rewards

## System Architecture

The VoteStake system consists of two main smart contracts:

### 1. Staking Contract (`staking.clar`)
- Handles token staking and unstaking
- Tracks staking positions and durations
- Calculates voting power based on stake amounts
- Manages staking rewards and penalties

### 2. Voting Contract (`voting.clar`)
- Creates and manages governance proposals
- Processes weighted votes based on stake
- Handles proposal execution and results
- Maintains voting history and statistics

## Key Features

### Weighted Voting
- Voting power directly correlates to staked token amounts
- Minimum stake requirements for proposal creation
- Time-weighted bonuses for longer staking periods

### Governance Proposals
- Any token holder can create proposals (with minimum stake)
- Proposals have defined voting periods
- Automatic execution for passed proposals
- Transparent voting results and history

### Staking Mechanism
- Flexible staking periods with different reward rates
- Early unstaking penalties to prevent vote manipulation
- Compound staking rewards for long-term participants
- Real-time voting power calculations

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js and npm for testing
- Stacks wallet for interaction

### Development Setup

```bash
# Clone the repository
git clone <repository-url>
cd vote-stake

# Install dependencies
npm install

# Check contract syntax
clarinet check

# Run tests
npm test
```

### Contract Deployment

The contracts can be deployed to:
- Devnet (for local development)
- Testnet (for testing)
- Mainnet (for production)

## Usage Examples

### Staking Tokens
```clarity
;; Stake 1000 tokens for 180 days
(contract-call? .staking stake-tokens u1000 u180)
```

### Creating a Proposal
```clarity
;; Create a governance proposal
(contract-call? .voting create-proposal 
  "Increase staking rewards" 
  "Proposal to increase base staking rate from 5% to 7%" 
  u1000)  ;; 1000 blocks voting period
```

### Voting on Proposals
```clarity
;; Vote yes on proposal #1
(contract-call? .voting cast-vote u1 true)
```

## Security Considerations

- All functions include proper authorization checks
- Staking positions are immutable during active votes
- Proposals require quorum and majority to pass
- Emergency pause functionality for critical issues

## Testing

The project includes comprehensive tests covering:
- Staking and unstaking scenarios
- Voting mechanism edge cases
- Proposal lifecycle management
- Security and access control

## Contributing

Please read our contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License.

# Authority follow-up — 2026-11-11

FACT — read-only public RPC checks at Ethereum block **26,391,659** (`0x192b46b`) show that the current manager `0x426c22504fd710fbaeacd0c15e7aad80210a1e12` still records `0x41652120ae1d605afff4beacd3a1cc0e22c7ff64` as owner of networks 1 and 2. Fee locks and ownership-transfer locks are true. CawProfile.networkManager() confirms the binding used for these reads.

For each network, simulated sponsor addition and gas override calls from that owner return successfully. The same inputs from an unrelated address revert `Not the owner`. A mint-fee change by the owner reverts `Fees locked`. These eth_call requests do not require the private key and change no chain state. They establish accepted authorization paths, not that anyone currently possesses the key. No transaction was signed or broadcast.

## Successful renunciations

All six linked PathwayExpander renunciation transactions returned status 1. Their receipt block hashes match the corresponding provider-returned block headers, and each target reports owner zero at its recorded read block. See the six explorer-named JSON records for transaction input, logs, chain ID, target and owner call.

| Generation | Ethereum target | Base target | Arbitrum target |
|---|---|---|---|
| current | 0xcdbdd8533e8e287f378687aa70208ffcff997d39 | 0xd14c3038141c849612825760d9832515323462b5 | 0xdad5bac641abe10a11188a1aed7fad282188a76a |
| discarded | 0x29225d1177d0ecb3c0309417197d493b827a75b0 | 0x29225d1177d0ecb3c0309417197d493b827a75b0 | 0xc41aff35c236f24404283ee909a2d0641e44fa42 |

The two linked old-manager fee/ownership-lock transactions also returned status 1. Old manager `0x09ee733eb6ba19debc0e576aa18333a9a5a6d546` reports both locks true for IDs 1 and 2, but both IDs retain the deployer owner. Its network 2 authentication fee is still 250000000000000 raw units; network 1's is zero. Thus the two successful receipts do not establish that every old-network fee is zero. `owner()` reverts on this manager; use the network-specific getter, not that revert as evidence of renunciation.

## Fees and correction

The earlier review incorrectly labeled the authentication fee CAW by using CAW's decimals. That inference was wrong. The pinned upstream CawProfile pays authentication fees from msg.value and accounts in native ETH. Its payFee records one fee for the recipient and another equal fee for BuyAndBurn. At this block the current Babylon getter returns **250000000000000 wei = 0.00025 ETH**, with the deployer as fee recipient; the two portions total **0.0005 ETH**, before any additional transport costs. Current accruedFees(deployer) returns **1500000000000000 wei = 0.0015 ETH**. See fee-reads.json. The old manager has the same nonzero auth getter for network 2. This is not a CAW-token fee.

Pinned source: https://github.com/GilgameshCaw/Caw/blob/97cd13f3a1423f702d411472fdd2b2a2e7bfbd59/solidity/contracts/CawProfile.sol (payFee, withdrawFees, withdrawFeesFor). Source interpretation is distinguished from a full deployed-bytecode/source match, which remains outside this review.

## Key deletion and limits

INFERENCE — public chain data cannot establish that every private-key copy or recovery source was destroyed. The operator's deletion report must remain labeled as a report. It does not remove recorded permissions. Assertions that residual calls are permanently impossible or accrued fees can never be released depend on that report.

This review does not allege deception or theft, prove someone retains the key, certify user-fund safety, enumerate every permission/dependency, prove all funds were returned, or establish manifesto compliance. Receipt/header agreement is provider-backed observation, not independent consensus authentication. Arbitrum's PublicNode endpoint failed; arb1.arbitrum.io/rpc returned the recorded successes. Secondary Ethereum-provider owner checks failed with HTTP 403 and are recorded as failures. Source and historical receipts remain scoped evidence.

## Reproduction

Use the recorded chain-specific RPCs and block numbers. Reissue each receipt hash, transaction hash and owner() call in the explorer-named JSON files. For permissions.json, replay each request as eth_call at its top-level block. old-network-reads.json and fee-reads.json include complete JSON-RPC requests. Do not broadcast the simulated calls. Compare successful controls with rejected controls. The script review-rpc.py reproduces the main capture into a fresh local directory; requires Python 3, pycryptodome and authenticated gh for public source capture. No private material is included.

# Network authority: fixed-block review

This documentation correction concerns the current deployment, not the abandoned earlier generation. It does not change contracts, assert malicious intent, or certify the entire deployment.

## Observed Ethereum state

Block **26,391,366** (`0x192b346`), via `https://ethereum.publicnode.com`. Current app/website CawProfile: `0xa3700808e1c62E989fbf5CE15312d79d1475bDb4`. Its `networkManager()` returned `0x426c22504fd710fbaeacd0c15e7aad80210a1e12`.

For networks 1 and 2, `getNetworkOwner(uint32)` returned `0x41652120ae1d605afff4beacd3a1cc0e22c7ff64`; `networkFeesLocked` and `networkOwnershipLocked` both returned true. Uruk's mint/deposit/withdraw/auth fees were zero. Babylon's first three were zero; authFee was 250000000000000 raw units. Correction (2026-11-11): the earlier inference from CAW decimals was wrong. Authentication uses native ETH; 250000000000000 wei is **0.00025 ETH**. A locked nonzero fee is not a zero fee.

## Read-only permission controls

The attached JSON records calldata, sender, block and complete responses. These were `eth_call` simulations, never signed or broadcast transactions. Supplying a sender in eth_call does not prove possession of that sender's key.

For both network IDs:
- `addAuthorizedSponsor(id, 0x0000000000000000000000000000000000000001)` from the recorded owner succeeded; the same call from address 0x...02 reverted `Not the owner`.
- `setGasOverride(id, 0x00000000, 1)` from the owner succeeded; the unrelated sender reverted `Not the owner`. This tests authorization for that selector, not a measured cost increase on a real cross-chain message.
- `setMintFee(id, 0)` from the owner reverted `Fees locked`.

Thus the fee lock works in the tested case while other owner-only calls remain accepted. The test does not show a capacity to steal assets. It does not enumerate every permission in all contracts.

The published Ethereum renunciation transaction `0x6533d7ef043ccc1a6489cc591ce29017047195c6976f32aed579d31d1bff482a` succeeded; its target `0xcdbdd8533e8e287f378687aa70208ffcff997d39` has owner zero. The published Base transaction `0x6b3c8fbe69ad63f28485428f4e8c1202082f10cbacfec68d82f70d50d83d6417` also succeeded; target `0xd14c3038141c849612825760d9832515323462b5` read owner zero. These are distinct from the retained network owner. At the initial check Arbitrum access failed. The follow-up below confirms both published Arbitrum renunciations.

## Reproduction and limits

Use an Ethereum archive-capable RPC and the block above. Replay each `method` and `params` in `network-authority-reads.json` as JSON-RPC requests. Compare both accepted and rejected controls. Do not submit transactions. Provider responses are not consensus-authenticated state proofs; second-provider corroboration was unavailable. A complete bytecode/source match and full authority/dependency audit remain outside this check. Later state must be checked at a newly identified block rather than silently substituted.

The source-level distinction is also explicit in [the pinned upstream manager](https://github.com/GilgameshCaw/Caw/blob/97cd13f3a1423f702d411472fdd2b2a2e7bfbd59/solidity/contracts/CawNetworkManager.sol#L670): ownership lock freezes transfer while gas overrides remain callable. This source reference alone is not deployed-bytecode verification.

## Follow-up

See [the 2026-11-11 fixed-block recheck](authority-followup-20261111/REVIEW.md) for both deployment generations, successful Arbitrum checks and remaining permissions. Earlier receipts retain their original block.

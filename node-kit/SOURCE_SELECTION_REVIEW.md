# Operator-selected source and remaining dependencies

Review date: 2026-11-12. Source baseline: [`9f150dc67a95cc34b8f6a499cbb83000b5e9f79e`](https://github.com/QL1-Infinite42-Guppy-Histoire/eth-caw/tree/9f150dc67a95cc34b8f6a499cbb83000b5e9f79e).

## Reproduced source-selection gap

FACT — `install-node.sh` previously cloned the current default branch of GilgameshCaw/Caw without an operator-selected commit. For an existing checkout it ran `git pull --ff-only || true`, continuing after a failed update. It then installed dependencies and started services. This did not establish which reviewed source would run on a later installation.

INFERENCE — continued installation depended on a mutable repository selection. This conflicts with the goal that another builder can reproduce and continue the work without depending on a particular maintainer's next branch update. It does not establish that any maintainer has acted maliciously or that a running node can be remotely stopped by a GitHub change.

## Manifesto and R2 relationship

The [manifesto](https://github.com/cawdevelopment/manifesto/blob/main/README.md) requires community review and acceptance on public GitHub and says no individual should be able to cripple the system in a meaningful way. The [reproduced R2 reading](https://github.com/Xubu-Trad/caw-lab/blob/canon/layers/R2-020_hex_transposition/MESSAGE.md) requires shared review, agreed release and implementation that does not make its deployers indispensable. Its recovery is not proof of author identity.

An exact source commit is an engineering measure supporting reproducibility of that review, not an explicit command in either source and not proof of compliance by itself. This patch does not declare a release accepted or decide an unresolved protocol rule.

## Bounded change

- Require `CAW_SOURCE_COMMIT`, a complete lowercase 40-character Git commit, before installing packages or changing system configuration.
- Allow `CAW_SOURCE_REPO` to select a preserved mirror instead of requiring the original account.
- Fetch the selected object, verify it, and use detached HEAD. No fallback to a branch or stale checkout.
- Refuse local changes/untracked files and non-checkout directories; never delete or reset operator configuration.
- Require `client/package.json` in the selected source.

Download and review the installer first. Set the selected commit in its environment or in an explicitly reviewed startup script. The app's existing copied script and old command stop without that selection. This is an intentional compatibility change. A user interface for selecting an approved release can follow only when that release has actually been reviewed. No particular commit is endorsed here.

## Validation

Run `python3 node-kit/test-source-selection.py`. Ten offline checks cover missing/malformed/branch-name selections, a selected older commit after branch advancement, clean repeat, dirty checkout preservation, absent object/mirror, a non-checkout directory and full-script early rejection. No packages, services, wallets, RPCs or real deployments are used. The first local fixture attempt was blocked by inherited Git commit signing; the final test disables signing only in its temporary repository.

These checks do not certify Ubuntu installation, package compatibility, node synchronization, deployment wiring or user-fund safety.

## Explicitly unresolved dependencies

| Surface | Observed baseline behavior | Remaining work |
|---|---|---|
| Installer delivery | Website/app copy executes mutable hosted script | Pin and verify the installer itself before elevated execution |
| Deployment configuration | Two generated address files fetched from hosted node kit | Bind configuration bytes, chain IDs and creation evidence to the selected release |
| Packages/runtime | NodeSource script, cloudflared latest download, npm install, system packages | Reproducible dependency selection and artifact provenance |
| Public endpoint | Cloudflare quick tunnel | Document/test independent HTTPS ingress and failover |
| Discovery | Hosted static list and Cloudflare worker | Independently replaceable discovery; manual node entry already exists in app |
| Chain access | PublicNode and Base RPC defaults | Operator-selected alternatives and independent recovery evidence |
| Existing node state | Local PostgreSQL/Redis and generated configuration | Rebuild/recovery exercise without the original operator's database or credentials |

The app at `d10a92af8628f5d93fc8f88374852d89da8440ed` exposes a manual node URL. Therefore the hosted registry is a default-discovery dependency, not proof that the operator controls all protocol access. Its auto-selection checks reachability; this review does not establish authenticated chain/deployment identity for a discovered endpoint.

Separate retained-contract-authority evidence is already tracked in [PR #1](https://github.com/QL1-Infinite42-Guppy-Histoire/eth-caw/pull/1); this patch does not duplicate or resolve it. Contract renunciation, reported key deletion, source verification, deployment and community acceptance are separate claims.

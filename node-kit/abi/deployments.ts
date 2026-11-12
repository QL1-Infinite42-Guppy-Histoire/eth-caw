/**
 * Deployment manifest for CAW Protocol contracts.
 *
 * MANAGED BY: solidity/scripts/deploy.js (after every successful deploy run).
 * READ BY: cli/src/steps/* (resolves the operator's chosen network to the
 *          right per-chain addresses, then writes addresses.ts).
 *
 * STRUCTURE:
 *   deployments[env][chainKey][contractName] = address
 *
 *   * env       — 'testnet' | 'mainnet' | 'dev'
 *   * chainKey  — 'L1' | 'L2' | 'L2b' | future 'L2c'...
 *
 * One Network = one storage chain. The CLI looks up the operator's networkId
 * on the L1 CawNetworkManager (getStorageChainEid), maps the eid back to a
 * chainKey, and pulls THIS Network's CawActions / CawProfileLedger / etc. from
 * the matching block. addresses.ts ends up with singular constants — the
 * call-sites in the rest of the codebase don't have to be multi-chain aware.
 *
 * Per-chain contracts (one entry per L2):
 *   - CawActions       (storage chain — receives action submissions)
 *   - CawProfileLedger     (per-chain balance/auth bookkeeping)
 *   - CawActionsArchive (storage chain doubles as archive — see deploy.js)
 *   - CawChallengeRelay (storage chain's relay for fraud proofs)
 *
 * L1-only contracts:
 *   - CawProfile, CawNetworkManager, CawProfileMinter, CawProfileQuoter,
 *     CawProfileMarketplace, CawProfileURI, MintableCaw, CawProfileLedger_L1,
 *     CawActions_L1
 *     (L1 hosts a co-deployed CawProfileLedger + CawActions in bypassLZ mode so
 *     a Network can pick L1 as their storage chain. L1 doesn't get its own
 *     archive/relay — see L2_CHAIN_KEYS comment in deploy.js.)
 *
 * After deploy: deploy.js rewrites just the env block it ran against.
 * Other env blocks are left untouched.
 */

export type Env = 'testnet' | 'mainnet' | 'dev'
export type ChainKey = 'L1' | 'L2' | 'L2b' | string

export interface ChainContracts {
  // L1-only contracts (only present on chainKey === 'L1'):
  MintableCaw?: `0x${string}`
  CawProfile?: `0x${string}`
  CawProfileLedger?: `0x${string}`     // On L1 this is the bypassLZ co-deployed mirror
  CawNetworkManager?: `0x${string}`
  CawProfileMinter?: `0x${string}`
  CawProfileQuoter?: `0x${string}`
  CawProfileLens?: `0x${string}`
  CawProfileMarketplace?: `0x${string}`
  CawProfileURI?: `0x${string}`
  CawFontDataA?: `0x${string}`
  CawFontDataB?: `0x${string}`
  CawBuyAndBurn?: `0x${string}`
  MockSwapRouter?: `0x${string}`
  SmartEOA?: `0x${string}`

  // Per-chain contracts (present on every L2; CawActions also on L1):
  CawActions?: `0x${string}`
  CawActionsERC1271?: `0x${string}`
  CawActionsArchive?: `0x${string}`
  CawChallengeRelay?: `0x${string}`
}

export type Deployments = Record<Env, Partial<Record<ChainKey, ChainContracts>>>

export const deployments: Deployments = {
  testnet: {
    L1: {
      MintableCaw: '0x56817dc696448135203C0556f702c6a953260411',
      CawProfile: '0xbbaA66afb60557e7f1D1517A0494F21C31c51EDE',
      CawProfileLedger: '0x4A857aa2EA9ae27a01eD44147b772619100184a8',
      CawNetworkManager: '0x1BC2529C62AFeB8dA64afAb1b6b02f3F8C41115e',
      CawProfileMinter: '0xb15e5A1edC2d1f016217AC7EA663fBdFd81650b6',
      CawProfileQuoter: '0x853c292a125dF04707b20F73a0AB8A00596b5f4B',
      CawProfileMarketplace: '0x59aE34F861859420Df418453D2b617368397372F',
      SmartEOA: '0xE7FD024840Ba862089af8e3F4d6F41668Ed42A6e',
      CawProfileURI: '0x2eDe2C0023678d2Cd0938A63Df3432FaAE5D30Fd',
      CawFontDataA: '0x41D3289C47b7081C5563057e2B06cF1D10256078',
      CawFontDataB: '0x9a9834870f6F8952DAbEb11D9E0D38216FA929Fe',
      CawBuyAndBurn: '0x5d571B2554dE6dBedf6E65c549989Ed53D3fB953',
      CawActions: '0xf4C5D4FB0394C2C8ea4523C6C46c02ece9534dA5',
      CawActionsERC1271: '0xcf3e81833Fb76E4c916AcBCaE1e6781753E70Ea5',
    },
    L2: {
      CawProfileLedger: '0xf65331bdBb388193CC8DA593e0cBAAAE60a3F320',
      CawActions: '0x801d3df0C675058AC363af0b8DDb5B52147D90d4',
      CawActionsERC1271: '0xf6cc99C45AFe9612cd572493d017e4eCDee252b7',
      CawActionsArchive: '0x0078b233b7cC53B2ad28684DC3d840A2e8B65Fad',
      CawChallengeRelay: '0x52fFB55a1b6774bDD1a3DB6a7A83d1dB50a73bC6',
    },
    L2b: {
      CawProfileLedger: '0xf65331bdBb388193CC8DA593e0cBAAAE60a3F320',
      CawActions: '0x801d3df0C675058AC363af0b8DDb5B52147D90d4',
      CawActionsERC1271: '0xf6cc99C45AFe9612cd572493d017e4eCDee252b7',
      CawActionsArchive: '0x0078b233b7cC53B2ad28684DC3d840A2e8B65Fad',
      CawChallengeRelay: '0x52fFB55a1b6774bDD1a3DB6a7A83d1dB50a73bC6',
    },
  },
  mainnet: {
    L1: {
      MintableCaw: '0xf3b9569F82B18aEf890De263B84189bd33EBe452',
      CawProfile: '0xa3700808e1c62E989fbf5CE15312d79d1475bDb4',
      CawProfileLedger: '0x3f6E2cc5a2E7CB6984f94c826717B71FB001dD3C',
      CawNetworkManager: '0x426C22504fd710fbAEAcd0c15e7aad80210a1E12',
      CawProfileMinter: '0xf219DA7aF9249322D4E982dc49FcE6251bCE0d22',
      CawProfileQuoter: '0x4baBf4136707d6f4C096ea447Ec3285Cc2AF7235',
      CawProfileMarketplace: '0xD76B5Aa960da00B1df69eD96a4F3D6D311Ef4bd9',
      SmartEOA: '0xC91a8eA79DCee6742AA125C11f3e6d37979BC992',
      CawProfileURI: '0xCF7e846D31193427458282eB4E3D3D348B79F1DF',
      CawFontDataA: '0xF105C02f1Cf8Ea2C607558314b9BD35B5F187B04',
      CawFontDataB: '0x8969ceD02E7B38b20256bC6341174d1ea04F4AEe',
      CawBuyAndBurn: '0xb6F3a337F318AFE16C6e952915796559e180ECAc',
      CawActions: '0x4Df413760cd196D28818478278f7A0E8b6Ee6e39',
      CawActionsERC1271: '0x9c0331CDC003453730B19f52a507373EF0a9e513',
    },
    L2: {
      CawProfileLedger: '0x206c99Ee5CFF8b5D761926ff224D867E1fBC7aaa',
      CawActions: '0xf4dFCf0EF472E8aaD3783479051f61EC574C6A8E',
      CawActionsERC1271: '0x1aF9fc193d23528C9F8C17030Bf3A61C5473d52c',
      CawActionsArchive: '0x9ac02C514A016c7E6A92cf69a44a4d793b6b9cfE',
      CawChallengeRelay: '0x747B7Bc621f3705e4Cd84eF0f94F2C1fF335F611',
    },
    L2b: {
      CawProfileLedger: '0xd14C3038141C849612825760D9832515323462B5',
      CawActions: '0x31e8F103F717C48c5FA6c9b9134a2AD1aEe8b1aE',
      CawActionsERC1271: '0xf4dFCf0EF472E8aaD3783479051f61EC574C6A8E',
      CawActionsArchive: '0x1aF9fc193d23528C9F8C17030Bf3A61C5473d52c',
      CawChallengeRelay: '0x9ac02C514A016c7E6A92cf69a44a4d793b6b9cfE',
    },
  },
  dev: {},
}

/**
 * Look up the deployments block for one (env, chain) pair. Throws if the
 * env or chain is unknown — better to fail loudly during install than to
 * silently end up with undefined addresses on a different chain.
 */
export function getChainContracts(env: Env, chainKey: ChainKey): ChainContracts {
  const envBlock = deployments[env]
  if (!envBlock) throw new Error(`Unknown deployment env: ${env}`)
  const chainBlock = envBlock[chainKey]
  if (!chainBlock) throw new Error(`No deployments for ${env}/${chainKey}`)
  return chainBlock
}

/**
 * LZ endpoint IDs for each (env, chainKey) pair. Same source-of-truth shape
 * as the addresses above so the CLI can map a Network's storageChainEid back
 * to the right chainKey without duplicating the table elsewhere.
 *
 * Kept in sync by hand with solidity/scripts/deploy.js CHAINS map. If you
 * edit one, edit the other (or factor out a single shared constants module
 * later — currently a CommonJS / ESM boundary).
 */
export const lzEids: Record<Env, Partial<Record<ChainKey, number>>> = {
  testnet: {
    L1: 40161,    // Sepolia
    L2: 40245,    // Base Sepolia
    L2b: 40231,   // Arbitrum Sepolia
  },
  mainnet: {
    L1: 30101,    // Ethereum
    L2: 30184,    // Base
    L2b: 30110,   // Arbitrum
  },
  dev: {
    L1: 30101,
    L2: 40161,
    L2b: 40231,
  },
}

/**
 * Reverse lookup: storageChainEid → chainKey for a given env. Used by the
 * CLI to translate a Network's on-chain storageChainEid into the abstract
 * chainKey it needs to read deployments[env][chainKey] from.
 */
export function chainKeyForEid(env: Env, eid: number): ChainKey | null {
  const envBlock = lzEids[env]
  if (!envBlock) return null
  for (const [key, value] of Object.entries(envBlock)) {
    if (value === eid) return key
  }
  return null
}

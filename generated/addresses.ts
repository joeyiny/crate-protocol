// Auto-generated file. Do not edit manually.
// Generated from Foundry broadcast files by scripts/generate-deployments.ts

export const addresses = {
  "31337": {
    "TokenFactory": "0x0d8a9ef652601a0e0fc6cfa669312aee21770fc7"
  }
} as const;

export const chains = [31337] as const;

export type ChainId = typeof chains[number];

export type ContractName = keyof typeof addresses[ChainId];

/**
 * Get the address of a contract on a specific chain
 * @param chainId - The chain ID
 * @param contractName - The name of the contract
 * @returns The contract address or undefined if not found
 */
export function getAddress(
  chainId: ChainId,
  contractName: ContractName
): string | undefined {
  return addresses[chainId]?.[contractName as keyof typeof addresses[ChainId]];
}

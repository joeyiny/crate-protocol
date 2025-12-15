// Auto-generated file. Do not edit manually.
// Generated from Foundry broadcast files by scripts/generate-deployments.ts

export const addresses = {
  "31337": {
    "TokenFactory": "0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0"
  },
  "84532": {
    "TokenFactory": "0xe64021fb66e4282de0f86bb47005472786e6737a"
  }
} as const;

export const chains = [31337, 84532] as const;

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

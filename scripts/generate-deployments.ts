#!/usr/bin/env tsx

/* Gets addresses from broadcast files and config/deployments.toml and puts them in addresses.ts and songs.ts */

import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface BroadcastTransaction {
  contractName: string;
  contractAddress: string;
  transaction?: {
    to?: string;
    from?: string;
  };
}

interface BroadcastFile {
  transactions: BroadcastTransaction[];
  chain?: number;
}

interface DeploymentAddresses {
  [chainId: number]: {
    [contractName: string]: string;
  };
}

interface SongAddresses {
  [chainId: number]: {
    [songKey: string]: string;
  };
}

const BROADCAST_DIR = resolve(__dirname, "../broadcast");
const OUTPUT_FILE = resolve(__dirname, "../generated/addresses.ts");
const SONGS_JSON = resolve(__dirname, "../generated/songs.json");
const SONGS_OUTPUT_FILE = resolve(__dirname, "../generated/songs.ts");
const TARGET_CONTRACTS = new Set(["TokenFactory"]);

function scanBroadcastFiles(): DeploymentAddresses {
  const addresses: DeploymentAddresses = {};

  if (!existsSync(BROADCAST_DIR)) {
    console.log("No broadcast directory found. Creating empty addresses file.");
    return addresses;
  }

  // Read script directories (e.g., DeployStoa.s.sol, DevLaunchSongs.s.sol)
  const scriptDirs = readdirSync(BROADCAST_DIR).filter((dir) => {
    const path = join(BROADCAST_DIR, dir);
    return statSync(path).isDirectory();
  });

  for (const scriptDir of scriptDirs) {
    const scriptPath = join(BROADCAST_DIR, scriptDir);

    // Read chain ID directories (e.g., 31337, 8453)
    const chainDirs = readdirSync(scriptPath).filter((dir) => {
      const path = join(scriptPath, dir);
      return statSync(path).isDirectory() && /^\d+$/.test(dir);
    });

    for (const chainId of chainDirs) {
      const chainPath = join(scriptPath, chainId);
      const runLatestPath = join(chainPath, "run-latest.json");

      if (!existsSync(runLatestPath)) {
        continue;
      }

      try {
        const content = readFileSync(runLatestPath, "utf-8");
        const broadcast: BroadcastFile = JSON.parse(content);
        const chainIdNum = parseInt(chainId, 10);

        if (!addresses[chainIdNum]) {
          addresses[chainIdNum] = {};
        }

        // Extract contract deployments
        for (const tx of broadcast.transactions) {
          if (tx.contractName && tx.contractAddress && TARGET_CONTRACTS.has(tx.contractName)) {
            // Only store the first deployment of each contract name
            if (!addresses[chainIdNum][tx.contractName]) {
              addresses[chainIdNum][tx.contractName] = tx.contractAddress;
              console.log(`Found ${tx.contractName} on chain ${chainIdNum}: ${tx.contractAddress}`);
            }
          }
        }
      } catch (error) {
        console.error(`Error parsing ${runLatestPath}:`, error);
      }
    }
  }

  return addresses;
}

function generateTypeScriptFile(addresses: DeploymentAddresses): string {
  const chains = Object.keys(addresses)
    .map(Number)
    .sort((a, b) => a - b);

  let output = `// Auto-generated file. Do not edit manually.
// Generated from Foundry broadcast files by scripts/generate-deployments.ts

export const addresses = ${JSON.stringify(addresses, null, 2)} as const;

export const chains = [${chains.join(", ")}] as const;

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
`;

  return output;
}



function main() {
  console.log("🔍 Scanning broadcast files...");
  const addresses = scanBroadcastFiles();

  const chainCount = Object.keys(addresses).length;
  const contractCount = Object.values(addresses).reduce((sum, chain) => sum + Object.keys(chain).length, 0);

  console.log(`\n📝 Found ${contractCount} contracts across ${chainCount} chain(s)`);

  console.log("✍️  Generating TypeScript file...");
  const content = generateTypeScriptFile(addresses);

  writeFileSync(OUTPUT_FILE, content, "utf-8");
  console.log(`✅ Generated ${OUTPUT_FILE}`);
}

main();

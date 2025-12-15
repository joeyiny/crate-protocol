// Auto-generated file. Do not edit manually.
// Generated from config/deployments.toml by scripts/generate-deployments.ts

export const songs = {} as const;

export const songChains = [] as const;

export type SongsByChain = typeof songs;

export type SongChainId = typeof songChains[number];

export function getSongAddress(
  chainId: number,
  songKey: string
): string | undefined {
  const chainSongs = songs[String(chainId) as keyof typeof songs];
  if (!chainSongs) {
    return undefined;
  }
  return chainSongs[songKey as keyof typeof chainSongs];
}

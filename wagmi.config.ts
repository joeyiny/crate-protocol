import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

// @ts-check

/** @type {import('@wagmi/cli').Config} */
export default defineConfig({
  out: "./generated-abi.ts",
  contracts: [],
  plugins: [
    foundry({
      project: "./",
      include: ["Crate*"],
    }),
  ],
});

import { BigInt, log } from "@graphprotocol/graph-ts";
import { TokenLaunched as TokenLaunchedEvent } from "../generated/CrateFactoryV1/CrateFactoryV1";
import { CrateToken } from "../generated/schema";
import { CrateTokenV1 } from "../generated/templates";

export function handleTokenLaunched(event: TokenLaunchedEvent): void {
  CrateTokenV1.create(event.params.tokenAddress);
  let entity = new CrateToken(event.params.tokenAddress);

  entity.name = event.params.name;
  entity.symbol = event.params.symbol;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.totalSupply = BigInt.fromString("106500000000000000000000");
  entity.totalCurveSupply = BigInt.fromString("80000000000000000000000");
  entity.amountOfTokensInCurve = BigInt.fromString("80000000000000000000000");
  entity.amountOfEthInCurve = new BigInt(0);
  entity.tokensInCirculation = new BigInt(0);
  entity.save();
}

import { newMockEvent } from "matchstick-as"
import { ethereum, Address } from "@graphprotocol/graph-ts"
import { TokenLaunched } from "../generated/CrateFactoryV1/CrateFactoryV1"

export function createTokenLaunchedEvent(
  tokenAddress: Address,
  name: string,
  symbol: string
): TokenLaunched {
  let tokenLaunchedEvent = changetype<TokenLaunched>(newMockEvent())

  tokenLaunchedEvent.parameters = new Array()

  tokenLaunchedEvent.parameters.push(
    new ethereum.EventParam(
      "tokenAddress",
      ethereum.Value.fromAddress(tokenAddress)
    )
  )
  tokenLaunchedEvent.parameters.push(
    new ethereum.EventParam("name", ethereum.Value.fromString(name))
  )
  tokenLaunchedEvent.parameters.push(
    new ethereum.EventParam("symbol", ethereum.Value.fromString(symbol))
  )

  return tokenLaunchedEvent
}

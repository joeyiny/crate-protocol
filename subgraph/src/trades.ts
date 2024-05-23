import { log } from "@graphprotocol/graph-ts";
import { CrateToken, Trade, Trader, TokenBalance, ProtocolStats } from "../generated/schema";
import { TokenPurchase as TokenPurchaseEvent } from "../generated/templates/CrateBondingCurveV1/CrateBondingCurveV1";
import { TokenTrade as TokenTradeEvent } from "../generated/templates/CrateTokenV1/CrateTokenV1";
import { BigInt } from "@graphprotocol/graph-ts";

export function handleTokenTrade(event: TokenTradeEvent): void {
  let isPurchase = event.params.isPurchase;
  let token = CrateToken.load(event.address);
  if (!token) {
    log.critical("token not found", []);
    return;
  }

  let trader = Trader.load(event.params.trader);
  if (!trader) {
    trader = new Trader(event.params.trader);
    trader.save();
  }

  let trade = new Trade(event.transaction.hash);
  trade.blockNumber = event.block.number;
  trade.blockTimestamp = event.block.timestamp;
  trade.transactionHash = event.transaction.hash;
  trade.ethTraded = event.params.ethAmount;
  trade.tokenTraded = event.params.tokenAmount;
  trade.token = token.id;
  trade.trader = trader.id;
  trade.isPurchase = isPurchase;
  let price = new BigInt(0);
  // Calculate the price per token
  if (!event.params.tokenAmount.isZero()) {
    // Convert ETH amount to a BigDecimal
    let ethAmountBD = event.params.ethAmount;
    // Convert Token amount to a BigDecimal
    let tokenAmountBD = event.params.tokenAmount;
    // Perform the division
    price = ethAmountBD.div(tokenAmountBD);
  }
  trade.price = price;
  trade.save();
  if (isPurchase) {
    token.amountOfEthInCurve = token.amountOfEthInCurve.plus(trade.ethTraded);
    token.amountOfTokensInCurve = token.amountOfTokensInCurve.minus(trade.tokenTraded);
    token.tokensInCirculation = token.tokensInCirculation.plus(trade.tokenTraded);
  } else {
    token.amountOfEthInCurve = token.amountOfEthInCurve.minus(trade.ethTraded);
    token.amountOfTokensInCurve = token.amountOfTokensInCurve.plus(trade.tokenTraded);
    token.tokensInCirculation = token.tokensInCirculation.minus(trade.tokenTraded);
  }

  token.save();

  updateOrCreateTokenBalance(trader, token, event.params.tokenAmount, isPurchase);

  let protocolStats = ProtocolStats.load("singleton");
  if (!protocolStats) {
    protocolStats = new ProtocolStats("singleton");
    protocolStats.volume = BigInt.fromI32(0);
    protocolStats.numberOfTrades = BigInt.fromI32(0);
    protocolStats.tvl = BigInt.fromI32(0);
  }

  // Update ProtocolStats
  protocolStats.volume = protocolStats.volume.plus(trade.ethTraded);
  protocolStats.numberOfTrades = protocolStats.numberOfTrades.plus(BigInt.fromI32(1));
  protocolStats.tvl = token.amountOfEthInCurve; // Update with relevant TVL calculation logic

  protocolStats.save();
}

function updateOrCreateTokenBalance(trader: Trader, token: CrateToken, amount: BigInt, isPurchase: boolean): void {
  let tokenBalanceId = token.id.toHex() + "-" + trader.id.toHex();
  let tokenBalance = TokenBalance.load(tokenBalanceId);

  if (!tokenBalance) {
    tokenBalance = new TokenBalance(tokenBalanceId);
    tokenBalance.token = token.id;
    tokenBalance.trader = trader.id;
    tokenBalance.balance = BigInt.fromI32(0);
  }

  if (isPurchase) {
    tokenBalance.balance = tokenBalance.balance.plus(amount);
  } else {
    tokenBalance.balance = tokenBalance.balance.minus(amount);
  }

  tokenBalance.save();
}

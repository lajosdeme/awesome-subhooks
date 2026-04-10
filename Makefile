include .env

export $(shell sed 's/=.*//' .env)

mine-anti-sandwitch-addr:
	forge script script/MineAntiSandwichHookAddress.s.sol:AntiSandwichHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-liquidity-penalty-addr:
	forge script script/MineLiquidityPenaltyHookAddress.s.sol:LiquidityPenaltyHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-limit-order-addr:
	forge script script/MineLimitOrderHookAddress.s.sol:LimitOrderHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-full-range-addr:
	forge script script/MineFullRangeAddress.s.sol:FullRangeHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-volatility-oracle-addr:
	forge script script/MineVolatilityOracleAddress.s.sol:VolatilityOracleHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-twamm-addr:
	forge script script/MineTWAMMAddress.s.sol:TWAMMHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-oracle-hook-v3-adapters-addr:
	forge script script/MineOracleHookWithV3AdaptersAddress.s.sol:OracleHookWithV3AdaptersAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

mine-geomean:
	forge script script/MineGeomeanOracleAddress.s.sol:GeomeanOracleSubHookAddressMiner --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

test-deploy:
	forge script script/DeployHooks.s.sol:DeployHooks --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY)

deploy:
	forge script script/DeployHooks.s.sol:DeployHooks --rpc-url $(RPC_URL) --sender $(SENDER) --etherscan-api-key $(API_KEY) --verify --broadcast
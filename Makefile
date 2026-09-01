-include .env

.PHONY: all install build test test-gas clean \
        deploy-testnet deploy-mainnet \
        verify-testnet verify-mainnet

# ── Bootstrap ─────────────────────────────────────────────────────────────────
all: clean install build test

install:
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

clean:
	forge clean

# ── Tests ─────────────────────────────────────────────────────────────────────
test:
	forge test -vvv

test-gas:
	forge test --gas-report

test-watch:
	forge test -vvv --watch

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy-testnet:
	@echo "Deploying $BOLT to BSC Testnet..."
	forge script script/Deploy.s.sol:DeployBolt \
		--rpc-url $(BSC_TESTNET_RPC) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--verifier-url https://api-testnet.bscscan.com/api \
		--etherscan-api-key $(BSCSCAN_API_KEY) \
		-vvvv

deploy-mainnet:
	@echo "Deploying $BOLT to BSC Mainnet..."
	@echo "WARNING: This is MAINNET. Press Ctrl+C to abort, Enter to continue."
	@read confirm
	forge script script/Deploy.s.sol:DeployBolt \
		--rpc-url $(BSC_MAINNET_RPC) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--verifier-url https://api.bscscan.com/api \
		--etherscan-api-key $(BSCSCAN_API_KEY) \
		-vvvv

# ── Verify (if auto-verify failed during deploy) ──────────────────────────────
verify-testnet:
	forge verify-contract $(CONTRACT_ADDRESS) \
		src/BoltToken.sol:BinanceLightningBolt \
		--chain-id 97 \
		--etherscan-api-key $(BSCSCAN_API_KEY) \
		--verifier-url https://api-testnet.bscscan.com/api \
		--constructor-args $$(cast abi-encode \
			"constructor(address,address,address,address)" \
			$(MARKETING_WALLET) $(LIQUIDITY_WALLET) \
			$(RESERVE_WALLET) $(PANCAKE_ROUTER_TESTNET))

verify-mainnet:
	forge verify-contract $(CONTRACT_ADDRESS) \
		src/BoltToken.sol:BinanceLightningBolt \
		--chain-id 56 \
		--etherscan-api-key $(BSCSCAN_API_KEY) \
		--verifier-url https://api.bscscan.com/api \
		--constructor-args $$(cast abi-encode \
			"constructor(address,address,address,address)" \
			$(MARKETING_WALLET) $(LIQUIDITY_WALLET) \
			$(RESERVE_WALLET) $(PANCAKE_ROUTER_MAINNET))

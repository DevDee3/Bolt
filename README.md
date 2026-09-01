# ⚡ Binance Lightning Bolt — $BOLT

> The Lightning of BNB Chain  
> Foundry project — contracts, tests, deployment scripts

---

## Project Structure

```
bolt-foundry/
├── src/
│   ├── BoltToken.sol           ← Main $BOLT contract
│   └── mocks/
│       └── MockPancakeRouter.sol  ← PancakeSwap mock for tests
├── test/
│   └── BoltToken.t.sol         ← Full test suite (60+ tests)
├── script/
│   └── Deploy.s.sol            ← Deployment script
├── foundry.toml
├── Makefile
└── .env.example
```

---

## Token Details

| Field          | Value                          |
|----------------|-------------------------------|
| Name           | Binance Lightning Bolt        |
| Symbol         | $BOLT                         |
| Network        | BNB Smart Chain               |
| Total Supply   | 50,000,000,000 BOLT           |
| Decimals       | 18                            |
| Buy Tax        | 4% (2% liq + 2% marketing)   |
| Sell Tax       | 5% (2% liq + 3% marketing)   |
| Max Tax Cap    | 10% (hardcoded, immutable)    |

### Allocation

| Bucket      | Amount       | %   |
|-------------|-------------|-----|
| Presale     | 20,000,000,000 | 40% |
| Liquidity   | 15,000,000,000 | 30% |
| Marketing   | 10,000,000,000 | 20% |
| Reserve     |  5,000,000,000 | 10% |

---

## Quickstart

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Install dependencies

```bash
make install
```

### 3. Set up environment

```bash
cp .env.example .env
# Fill in your values in .env
```

### 4. Build

```bash
make build
```

### 5. Run tests

```bash
make test          # run all tests with verbose output
make test-gas      # run with gas report
```

---

## Deployment

### BSC Testnet

```bash
make deploy-testnet
```

Router used: `0xD99D1c33F9fC3444f8101754aBC46c52416550d1`  
Get testnet BNB: https://testnet.bnbchain.org/faucet-smart

### BSC Mainnet

```bash
make deploy-mainnet
```

Router used: `0x10ED43C718714eb63d5aA57B78B54704E256024E`

> ⚠️ The Makefile prompts for confirmation before mainnet deploy.

### Verify contract (if auto-verify fails)

```bash
# Set CONTRACT_ADDRESS in .env first
make verify-testnet   # or verify-mainnet
```

---

## Post-Deploy Checklist

After deployment, call these functions **in order** via BscScan or your frontend:

```
1. startPresale(rate, softCap, hardCap, minPerWallet, maxPerWallet, duration)
2. [wait for presale to end or hard cap to be reached]
3. finalizePresale()    ← adds liquidity + enables trading
4. Lock LP tokens on PinkLock or Team.Finance
```

### Recommended Presale Params (Mainnet)

```
rate           =  2_000_000_000 * 1e18   // 2B BOLT per 1 BNB
softCap        =  5 ether                // 5 BNB minimum raise
hardCap        =  50 ether               // 50 BNB maximum raise
minPerWallet   =  0.05 ether             // 0.05 BNB min contribution
maxPerWallet   =  2 ether                // 2 BNB max contribution
duration       =  259200                 // 3 days (in seconds)
```

---

## Test Coverage

| Category          | Tests |
|-------------------|-------|
| Deployment        |  10   |
| BEP-20 core       |   6   |
| Presale — start   |   8   |
| Presale — contribute |  9 |
| Presale — finalize |   5  |
| Presale — cancel/refund | 6 |
| Tax mechanics     |   8   |
| Limits            |   6   |
| Admin setters     |  10   |
| Ownership         |   5   |
| Fuzz tests        |   3   |
| **Total**         | **76** |

Run a gas report:

```bash
make test-gas
```

---

## PancakeSwap Router Addresses

| Network      | Address                                      |
|--------------|----------------------------------------------|
| BSC Testnet  | `0xD99D1c33F9fC3444f8101754aBC46c52416550d1` |
| BSC Mainnet  | `0x10ED43C718714eb63d5aA57B78B54704E256024E` |

---

## Security Notes

- Max tax is hardcoded at **10%** — cannot be changed by owner
- Owner **cannot** mint new tokens
- Unsold presale tokens are **burned** on finalization
- Direct BNB sends to contract only accepted from PancakeSwap router
- ReentrancyGuard on all BNB-moving functions
- No external dependencies (no OpenZeppelin) — minimal attack surface

---

## License

MIT

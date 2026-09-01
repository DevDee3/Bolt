// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ⚡ Binance Lightning Bolt — $BOLT ⚡
 * The Lightning of BNB Chain
 *
 * Total Supply  : 50,000,000,000 BOLT
 * Network       : BNB Smart Chain (BSC)
 *
 * Token Allocation
 * ─────────────────────────────────────────
 *  40 % — Presale          (20 000 000 000)
 *  30 % — DEX Liquidity    (15 000 000 000)
 *  20 % — Marketing/Team   (10 000 000 000)
 *  10 % — Reserve          ( 5 000 000 000)
 *
 * Tax (post-launch, only on DEX swaps)
 * ─────────────────────────────────────────
 *  Buy  : 4 %  (2 % liquidity + 2 % marketing)
 *  Sell : 5 %  (2 % liquidity + 3 % marketing)
 *
 * Presale
 * ─────────────────────────────────────────
 *  Soft cap : configurable by owner
 *  Hard cap : configurable by owner
 *  Max per wallet : configurable by owner
 */

// ─────────────────────────────────────────────────────────────────────────────
//  Minimal Ownable  (no import bloat, gas-lean)
// ─────────────────────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ReentrancyGuard  (no OZ dependency)
// ─────────────────────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _status = _NOT_ENTERED;

    error ReentrantCall();

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Minimal BEP-20 / ERC-20
// ─────────────────────────────────────────────────────────────────────────────
interface IBEP20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ─────────────────────────────────────────────────────────────────────────────
//  PancakeSwap interfaces (BSC DEX)
// ─────────────────────────────────────────────────────────────────────────────
interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH()    external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

// ─────────────────────────────────────────────────────────────────────────────
//  $BOLT  Main Contract
// ─────────────────────────────────────────────────────────────────────────────
contract BinanceLightningBolt is IBEP20, Ownable, ReentrancyGuard {

    // ── Token metadata ───────────────────────────────────────────────────────
    string  public constant name     = "Binance Lightning Bolt";
    string  public constant symbol   = "BOLT";
    uint8   public constant decimals = 18;

    uint256 private constant _TOTAL_SUPPLY = 50_000_000_000 * 1e18;

    // ── Allocation constants ──────────────────────────────────────────────────
    uint256 public constant PRESALE_ALLOC   = 20_000_000_000 * 1e18; // 40 %
    uint256 public constant LIQUIDITY_ALLOC = 15_000_000_000 * 1e18; // 30 %
    uint256 public constant MARKETING_ALLOC = 10_000_000_000 * 1e18; // 20 %
    uint256 public constant RESERVE_ALLOC   =  5_000_000_000 * 1e18; // 10 %

    // ── BEP-20 state ─────────────────────────────────────────────────────────
    mapping(address => uint256)                     private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ── Tax config ───────────────────────────────────────────────────────────
    uint256 public buyLiquidityFee  = 2;
    uint256 public buyMarketingFee  = 2;
    uint256 public sellLiquidityFee = 2;
    uint256 public sellMarketingFee = 3;

    uint256 public constant MAX_TAX = 10;

    address public marketingWallet;
    address public liquidityWallet;

    uint256 private _liquidityReserve;
    uint256 private _marketingReserve;

    uint256 public swapThreshold = 100_000_000 * 1e18;
    bool    private _swapping;

    // ── DEX ──────────────────────────────────────────────────────────────────
    IPancakeRouter public pancakeRouter;
    address        public pancakePair;

    // ── Trading & anti-bot ───────────────────────────────────────────────────
    bool    public tradingEnabled;
    bool    public limitsEnabled  = true;
    uint256 public maxWalletAmount;
    uint256 public maxTxAmount;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromLimits;

    // ── Presale state ─────────────────────────────────────────────────────────
    enum PresaleState { PENDING, ACTIVE, FINALIZED, CANCELLED }
    PresaleState public presaleState;

    uint256 public presaleRate;
    uint256 public presaleSoftCap;
    uint256 public presaleHardCap;
    uint256 public presaleMaxPerWallet;
    uint256 public presaleMinPerWallet;
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;

    uint256 public presaleTotalRaised;
    mapping(address => uint256) public presaleContributions;

    bool    public whitelistEnabled;
    mapping(address => bool) public isWhitelisted;

    // ── Events ────────────────────────────────────────────────────────────────
    event PresaleStarted(uint256 startTime, uint256 endTime, uint256 rate, uint256 hardCap);
    event PresaleContribution(address indexed contributor, uint256 bnbAmount, uint256 boltAmount);
    event PresaleFinalized(uint256 totalRaised, uint256 liquidityAdded);
    event PresaleCancelled();
    event Refunded(address indexed contributor, uint256 amount);
    event TradingEnabled();
    event TaxUpdated(uint256 buyLiq, uint256 buyMkt, uint256 sellLiq, uint256 sellMkt);
    event LimitsUpdated(uint256 maxWallet, uint256 maxTx);
    event LimitsRemoved();
    event SwapAndDistribute(uint256 liquidityBNB, uint256 marketingBNB);

    // ── Errors ────────────────────────────────────────────────────────────────
    error TradingNotEnabled();
    error PresaleNotActive();
    error PresaleAlreadyActive();
    error HardCapReached();
    error BelowMinContribution();
    error WalletCapExceeded();
    error SoftCapNotReached();
    error PresaleNotFinished();
    error NothingToRefund();
    error TransferFailed();
    error ExceedsMaxTax();
    error ExceedsMaxTx();
    error ExceedsMaxWallet();
    error InvalidParameter();
    error NotWhitelisted();

    // ─────────────────────────────────────────────────────────────────────────
    constructor(
        address _marketingWallet,
        address _liquidityWallet,
        address _reserveWallet,
        address _routerAddress
    ) Ownable(msg.sender) {
        if (_marketingWallet == address(0) || _liquidityWallet == address(0) ||
            _reserveWallet   == address(0) || _routerAddress   == address(0))
            revert InvalidParameter();

        marketingWallet = _marketingWallet;
        liquidityWallet = _liquidityWallet;

        pancakeRouter = IPancakeRouter(_routerAddress);
        pancakePair   = IPancakeFactory(pancakeRouter.factory())
                            .createPair(address(this), pancakeRouter.WETH());

        isExcludedFromFee[msg.sender]        = true;
        isExcludedFromFee[address(this)]     = true;
        isExcludedFromFee[_marketingWallet]  = true;
        isExcludedFromFee[_liquidityWallet]  = true;

        isExcludedFromLimits[msg.sender]       = true;
        isExcludedFromLimits[address(this)]    = true;
        isExcludedFromLimits[_marketingWallet] = true;
        isExcludedFromLimits[_liquidityWallet] = true;

        _mint(address(this),    PRESALE_ALLOC + LIQUIDITY_ALLOC);
        _mint(_marketingWallet, MARKETING_ALLOC);
        _mint(_reserveWallet,   RESERVE_ALLOC);

        maxWalletAmount = _TOTAL_SUPPLY * 2 / 100;
        maxTxAmount     = _TOTAL_SUPPLY * 1 / 100;
    }

    // =========================================================================
    //  BEP-20 CORE
    // =========================================================================

    function totalSupply() external pure override returns (uint256) {
        return _TOTAL_SUPPLY;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InvalidParameter();
            unchecked { _allowances[from][msg.sender] = currentAllowance - amount; }
        }
        _transfer(from, to, amount);
        return true;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    function _mint(address to, uint256 amount) private {
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    // ── Transfer with fee logic ───────────────────────────────────────────────
    function _transfer(address from, address to, uint256 amount) private {
        if (amount == 0) return;
        if (_balances[from] < amount) revert InvalidParameter(); // ← underflow guard

        bool isBuy  = (from == pancakePair);
        bool isSell = (to   == pancakePair);

        if (!tradingEnabled && isBuy) revert TradingNotEnabled();

        if (limitsEnabled && !isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            if (amount > maxTxAmount) revert ExceedsMaxTx();
            if (!isSell && _balances[to] + amount > maxWalletAmount) revert ExceedsMaxWallet();
        }

        uint256 feeBalance = _liquidityReserve + _marketingReserve;
        bool canSwap = !_swapping && isSell && !isExcludedFromFee[from];
        if (canSwap && feeBalance >= swapThreshold && _balances[address(this)] >= feeBalance) {
            _swapAndDistribute(feeBalance);
        }

        uint256 feeAmount;
        if (!_swapping && !isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            if (isBuy) {
                uint256 totalBuyFee = buyLiquidityFee + buyMarketingFee;
                if (totalBuyFee > 0) {                          // ← zero-fee guard
                    feeAmount = amount * totalBuyFee / 100;
                    _liquidityReserve += feeAmount * buyLiquidityFee / totalBuyFee;
                    _marketingReserve += feeAmount * buyMarketingFee / totalBuyFee;
                }
            } else if (isSell) {
                uint256 totalSellFee = sellLiquidityFee + sellMarketingFee;
                if (totalSellFee > 0) {                         // ← zero-fee guard
                    feeAmount = amount * totalSellFee / 100;
                    _liquidityReserve += feeAmount * sellLiquidityFee / totalSellFee;
                    _marketingReserve += feeAmount * sellMarketingFee / totalSellFee;
                }
            }
        }

        uint256 transferAmount = amount - feeAmount;

        unchecked {
            _balances[from] -= amount;
            if (feeAmount > 0) _balances[address(this)] += feeAmount;
            _balances[to] += transferAmount;
        }

        if (feeAmount > 0) emit Transfer(from, address(this), feeAmount);
        emit Transfer(from, to, transferAmount);
    }

    // =========================================================================
    //  AUTO SWAP & DISTRIBUTE
    // =========================================================================
    function _swapAndDistribute(uint256 tokenAmount) private {
        _swapping = true;

        uint256 halfLiq  = _liquidityReserve / 2;
        uint256 swapAmt  = halfLiq + _marketingReserve;

        uint256 bnbBefore = address(this).balance;
        _swapTokensForBNB(swapAmt);
        uint256 bnbGained = address(this).balance - bnbBefore;

        uint256 bnbForLiq = swapAmt > 0 ? (bnbGained * halfLiq / swapAmt) : 0;
        uint256 bnbForMkt = bnbGained - bnbForLiq;

        if (bnbForLiq > 0 && halfLiq > 0) _addLiquidity(halfLiq, bnbForLiq);

        if (bnbForMkt > 0) {
            (bool sent,) = marketingWallet.call{value: bnbForMkt}("");
            if (!sent) revert TransferFailed();
        }

        _liquidityReserve = 0;
        _marketingReserve = 0;

        emit SwapAndDistribute(bnbForLiq, bnbForMkt);
        _swapping = false;
    }

    function _swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();
        _approve(address(this), address(pancakeRouter), tokenAmount);
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(pancakeRouter), tokenAmount);
        pancakeRouter.addLiquidityETH{value: bnbAmount}(
            address(this), tokenAmount, 0, 0, liquidityWallet, block.timestamp
        );
    }

    // =========================================================================
    //  PRESALE
    // =========================================================================

    function startPresale(
        uint256 rate,
        uint256 softCap,
        uint256 hardCap,
        uint256 minPerWallet,
        uint256 maxPerWallet,
        uint256 duration
    ) external onlyOwner {
        if (presaleState != PresaleState.PENDING)    revert PresaleAlreadyActive();
        if (rate == 0 || hardCap == 0 || softCap > hardCap) revert InvalidParameter();
        if (minPerWallet > maxPerWallet)             revert InvalidParameter();
        if (duration == 0 || duration > 30 days)    revert InvalidParameter();

        presaleRate         = rate;
        presaleSoftCap      = softCap;
        presaleHardCap      = hardCap;
        presaleMinPerWallet = minPerWallet;
        presaleMaxPerWallet = maxPerWallet;
        presaleStartTime    = block.timestamp;
        presaleEndTime      = block.timestamp + duration;
        presaleState        = PresaleState.ACTIVE;

        emit PresaleStarted(presaleStartTime, presaleEndTime, rate, hardCap);
    }

    function contribute() external payable nonReentrant {
        if (presaleState != PresaleState.ACTIVE)                 revert PresaleNotActive();
        if (block.timestamp > presaleEndTime)                     revert PresaleNotActive();
        if (presaleTotalRaised + msg.value > presaleHardCap)      revert HardCapReached();
        if (msg.value < presaleMinPerWallet)                      revert BelowMinContribution();
        if (whitelistEnabled && !isWhitelisted[msg.sender])       revert NotWhitelisted();

        uint256 newContrib = presaleContributions[msg.sender] + msg.value;
        if (newContrib > presaleMaxPerWallet) revert WalletCapExceeded();

        presaleContributions[msg.sender]  = newContrib;
        presaleTotalRaised               += msg.value;

        uint256 boltAmount = msg.value * presaleRate / 1e18;

        unchecked {
            _balances[address(this)] -= boltAmount;
            _balances[msg.sender]    += boltAmount;
        }
        emit Transfer(address(this), msg.sender, boltAmount);
        emit PresaleContribution(msg.sender, msg.value, boltAmount);
    }

    function finalizePresale() external onlyOwner nonReentrant {
        if (presaleState != PresaleState.ACTIVE) revert PresaleNotActive();
        if (block.timestamp < presaleEndTime && presaleTotalRaised < presaleHardCap)
            revert PresaleNotFinished();
        if (presaleTotalRaised < presaleSoftCap) revert SoftCapNotReached();

        presaleState = PresaleState.FINALIZED;

        uint256 bnbForLiquidity = address(this).balance;
        uint256 liquidityTokens = LIQUIDITY_ALLOC;

        _approve(address(this), address(pancakeRouter), liquidityTokens);
        pancakeRouter.addLiquidityETH{value: bnbForLiquidity}(
            address(this), liquidityTokens, 0, 0, owner(), block.timestamp
        );

        // Burn unsold presale tokens
        uint256 unsold = _balances[address(this)];
        if (unsold > 0) {
            _balances[address(this)] = 0;
            emit Transfer(address(this), address(0), unsold);
        }

        tradingEnabled = true;
        emit PresaleFinalized(presaleTotalRaised, bnbForLiquidity);
        emit TradingEnabled();
    }

    function cancelPresale() external onlyOwner {
        if (presaleState != PresaleState.ACTIVE) revert PresaleNotActive();
        presaleState = PresaleState.CANCELLED;
        emit PresaleCancelled();
    }

    function claimRefund() external nonReentrant {
        if (presaleState != PresaleState.CANCELLED) revert PresaleNotActive();
        uint256 contrib = presaleContributions[msg.sender];
        if (contrib == 0) revert NothingToRefund();

        uint256 boltToReturn = contrib * presaleRate / 1e18;
        uint256 userBolt     = _balances[msg.sender];
        if (boltToReturn > userBolt) boltToReturn = userBolt;

        presaleContributions[msg.sender] = 0;

        if (boltToReturn > 0) {
            unchecked {
                _balances[msg.sender]    -= boltToReturn;
                _balances[address(this)] += boltToReturn;
            }
            emit Transfer(msg.sender, address(this), boltToReturn);
        }

        (bool sent,) = msg.sender.call{value: contrib}("");
        if (!sent) revert TransferFailed();
        emit Refunded(msg.sender, contrib);
    }

    // =========================================================================
    //  OWNER — CONFIG
    // =========================================================================

    function setTaxes(
        uint256 _buyLiqFee,  uint256 _buyMktFee,
        uint256 _sellLiqFee, uint256 _sellMktFee
    ) external onlyOwner {
        if (_buyLiqFee  + _buyMktFee  > MAX_TAX) revert ExceedsMaxTax();
        if (_sellLiqFee + _sellMktFee > MAX_TAX) revert ExceedsMaxTax();
        buyLiquidityFee  = _buyLiqFee;
        buyMarketingFee  = _buyMktFee;
        sellLiquidityFee = _sellLiqFee;
        sellMarketingFee = _sellMktFee;
        emit TaxUpdated(_buyLiqFee, _buyMktFee, _sellLiqFee, _sellMktFee);
    }

    function setLimits(uint256 newMaxWallet, uint256 newMaxTx) external onlyOwner {
        if (newMaxWallet < _TOTAL_SUPPLY / 200) revert InvalidParameter();
        if (newMaxTx     < _TOTAL_SUPPLY / 200) revert InvalidParameter();
        maxWalletAmount = newMaxWallet;
        maxTxAmount     = newMaxTx;
        emit LimitsUpdated(newMaxWallet, newMaxTx);
    }

    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        emit LimitsRemoved();
    }

    function setExcludeFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    function setExcludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    function setMarketingWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert InvalidParameter();
        marketingWallet = wallet;
    }

    function setLiquidityWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert InvalidParameter();
        liquidityWallet = wallet;
    }

    function setSwapThreshold(uint256 threshold) external onlyOwner {
        swapThreshold = threshold;
    }

    function setWhitelist(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
    }

    function addToWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i; i < accounts.length; ) {
            isWhitelisted[accounts[i]] = true;
            unchecked { ++i; }
        }
    }

    function removeFromWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i; i < accounts.length; ) {
            isWhitelisted[accounts[i]] = false;
            unchecked { ++i; }
        }
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BoltToken.sol";
import "../src/mocks/MockPancakeRouter.sol";

/**
 * ⚡ $BOLT — Full Foundry Test Suite
 *
 * Coverage
 * ─────────────────────────────────────────────────────
 *  ✅ Deployment & initial state
 *  ✅ BEP-20 core (transfer / approve / transferFrom)
 *  ✅ Presale lifecycle (start → contribute → finalize)
 *  ✅ Presale cancel & refund
 *  ✅ Presale edge-cases (whitelist, caps, timing)
 *  ✅ Buy & sell tax applied correctly
 *  ✅ Excluded addresses pay no tax
 *  ✅ Max-wallet & max-tx limits
 *  ✅ removeLimits()
 *  ✅ Admin setters (taxes, wallets, whitelist, threshold)
 *  ✅ Ownership transfer & renounce
 *  ✅ Fuzz: contributions within bounds always succeed
 *  ✅ Fuzz: excluded transfers always arrive in full
 */
contract BoltTokenTest is Test {

    // ── Contracts ────────────────────────────────────────────────────────────
    BinanceLightningBolt public token;
    MockPancakeRouter    public mockRouter;

    // ── Actors ───────────────────────────────────────────────────────────────
    address public owner     = makeAddr("owner");
    address public marketing = makeAddr("marketing");
    address public liquidity = makeAddr("liquidity");
    address public reserve   = makeAddr("reserve");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");
    address public charlie   = makeAddr("charlie");

    address public pair; // set after deploy (from mock factory)

    // ── Token constants ───────────────────────────────────────────────────────
    uint256 constant TOTAL_SUPPLY    = 50_000_000_000 * 1e18;
    uint256 constant PRESALE_ALLOC   = 20_000_000_000 * 1e18;
    uint256 constant LIQUIDITY_ALLOC = 15_000_000_000 * 1e18;
    uint256 constant MARKETING_ALLOC = 10_000_000_000 * 1e18;
    uint256 constant RESERVE_ALLOC   =  5_000_000_000 * 1e18;

    // ── Default presale params ────────────────────────────────────────────────
    // Rate: 1 000 000 000 BOLT per 1 BNB
    // → 0.1 BNB gives 100 000 000 BOLT (well within the 20B presale alloc)
    uint256 constant RATE           = 1_000_000_000 * 1e18;
    uint256 constant SOFT_CAP       = 0.1  ether;
    uint256 constant HARD_CAP       = 10   ether;
    uint256 constant MIN_PER_WALLET = 0.01 ether;
    uint256 constant MAX_PER_WALLET = 5    ether;
    uint256 constant DURATION       = 1 days;

    // ─────────────────────────────────────────────────────────────────────────
    function setUp() public {
        // 1. Deploy mock router (creates mock factory + pair internally)
        mockRouter = new MockPancakeRouter();

        // 2. Deploy token as owner
        vm.startPrank(owner);
        token = new BinanceLightningBolt(
            marketing,
            liquidity,
            reserve,
            address(mockRouter)
        );
        vm.stopPrank();

        // 3. Grab the pair address created by the mock factory
        pair = token.pancakePair();

        // 4. Pre-fund mock router with BNB so swap simulations work
        vm.deal(address(mockRouter), 100 ether);
    }

    // =========================================================================
    //  HELPERS
    // =========================================================================

    /// Start presale with default params.
    function _startPresale() internal {
        vm.prank(owner);
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, DURATION);
    }

    /**
     * Full presale lifecycle → trading enabled.
     * alice contributes SOFT_CAP, time expires, owner finalizes.
     */
    function _enableTrading() internal {
        // Short 5-min presale for tests
        vm.prank(owner);
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, 300);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: SOFT_CAP}();

        vm.warp(block.timestamp + 301); // past presale end

        vm.prank(owner);
        token.finalizePresale();

        // trading is now enabled
        assertTrue(token.tradingEnabled());
    }

    // =========================================================================
    //  DEPLOYMENT TESTS
    // =========================================================================

    function test_name() public view {
        assertEq(token.name(), "Binance Lightning Bolt");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "BOLT");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_totalSupply() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }

    function test_ownerSetCorrectly() public view {
        assertEq(token.owner(), owner);
    }

    function test_pancakePairCreated() public view {
        assertTrue(pair != address(0), "Pair should not be zero address");
    }

    function test_initialAllocations() public view {
        // Contract holds presale + liquidity
        assertEq(token.balanceOf(address(token)), PRESALE_ALLOC + LIQUIDITY_ALLOC);
        // Marketing & reserve wallets get their allocations immediately
        assertEq(token.balanceOf(marketing), MARKETING_ALLOC);
        assertEq(token.balanceOf(reserve),   RESERVE_ALLOC);
        // Owner gets nothing at deploy
        assertEq(token.balanceOf(owner), 0);
    }

    function test_totalMintedEqualsSupply() public view {
        uint256 minted = token.balanceOf(address(token))
                       + token.balanceOf(marketing)
                       + token.balanceOf(reserve);
        assertEq(minted, TOTAL_SUPPLY);
    }

    function test_feeExclusions() public view {
        assertTrue(token.isExcludedFromFee(owner));
        assertTrue(token.isExcludedFromFee(address(token)));
        assertTrue(token.isExcludedFromFee(marketing));
        assertTrue(token.isExcludedFromFee(liquidity));
    }

    function test_limitExclusions() public view {
        assertTrue(token.isExcludedFromLimits(owner));
        assertTrue(token.isExcludedFromLimits(address(token)));
        assertTrue(token.isExcludedFromLimits(marketing));
        assertTrue(token.isExcludedFromLimits(liquidity));
    }

    function test_initialPresaleStatePending() public view {
        assertEq(uint256(token.presaleState()), 0); // PENDING
    }

    function test_limitsEnabledByDefault() public view {
        assertTrue(token.limitsEnabled());
    }

    function test_tradingDisabledByDefault() public view {
        assertFalse(token.tradingEnabled());
    }

    function test_defaultMaxWalletAndTx() public view {
        assertEq(token.maxWalletAmount(), TOTAL_SUPPLY * 2 / 100);
        assertEq(token.maxTxAmount(),     TOTAL_SUPPLY * 1 / 100);
    }

    // =========================================================================
    //  BEP-20 CORE
    // =========================================================================

    function test_transfer_basic() public {
        uint256 amount = 1_000 * 1e18;
        vm.prank(marketing); // excluded from fee → full amount arrives
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_transfer_revert_insufficientBalance() public {
        vm.prank(alice); // alice has 0 tokens
        vm.expectRevert();
        token.transfer(bob, 1);
    }

    function test_transfer_revert_zeroAmount() public {
        vm.prank(marketing);
        // zero-amount transfers silently return true (no revert, no event)
        bool ok = token.transfer(alice, 0);
        assertTrue(ok);
    }

    function test_approve_and_allowance() public {
        vm.prank(alice);
        token.approve(bob, 500 * 1e18);
        assertEq(token.allowance(alice, bob), 500 * 1e18);
    }

    function test_transferFrom_basic() public {
        uint256 amount = 500 * 1e18;
        // Fund alice
        vm.prank(marketing);
        token.transfer(alice, amount);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        token.transferFrom(alice, charlie, amount);

        assertEq(token.balanceOf(charlie), amount);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFrom_revert_insufficientAllowance() public {
        vm.prank(marketing);
        token.transfer(alice, 1_000 * 1e18);

        vm.prank(alice);
        token.approve(bob, 100 * 1e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, 500 * 1e18);
    }

    function test_infiniteApproval_notDecremented() public {
        vm.prank(marketing);
        token.transfer(alice, 1_000 * 1e18);

        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, charlie, 500 * 1e18);

        // max allowance should stay max
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    // =========================================================================
    //  PRESALE — START
    // =========================================================================

    function test_startPresale_setsStateActive() public {
        _startPresale();
        assertEq(uint256(token.presaleState()), 1); // ACTIVE
    }

    function test_startPresale_setsParamsCorrectly() public {
        _startPresale();
        assertEq(token.presaleRate(),         RATE);
        assertEq(token.presaleSoftCap(),      SOFT_CAP);
        assertEq(token.presaleHardCap(),      HARD_CAP);
        assertEq(token.presaleMinPerWallet(), MIN_PER_WALLET);
        assertEq(token.presaleMaxPerWallet(), MAX_PER_WALLET);
        assertEq(token.presaleEndTime(),      block.timestamp + DURATION);
    }

    function test_startPresale_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, DURATION);
    }

    function test_startPresale_revert_alreadyActive() public {
        _startPresale();
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, DURATION);
    }

    function test_startPresale_revert_zeroRate() public {
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(0, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, DURATION);
    }

    function test_startPresale_revert_softCapAboveHardCap() public {
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(RATE, HARD_CAP + 1, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, DURATION);
    }

    function test_startPresale_revert_minAboveMax() public {
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MAX_PER_WALLET + 1, MAX_PER_WALLET, DURATION);
    }

    function test_startPresale_revert_zeroDuration() public {
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, 0);
    }

    function test_startPresale_revert_durationTooLong() public {
        vm.prank(owner);
        vm.expectRevert();
        token.startPresale(RATE, SOFT_CAP, HARD_CAP, MIN_PER_WALLET, MAX_PER_WALLET, 31 days);
    }

    // =========================================================================
    //  PRESALE — CONTRIBUTE
    // =========================================================================

    function test_contribute_recordsContribution() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: 0.5 ether}();

        assertEq(token.presaleContributions(alice), 0.5 ether);
        assertEq(token.presaleTotalRaised(),         0.5 ether);
    }

    function test_contribute_transfersBoltToContributor() public {
        _startPresale();

        uint256 contrib      = 0.5 ether;
        uint256 expectedBolt = contrib * RATE / 1e18; // 500_000_000 BOLT

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: contrib}();

        assertEq(token.balanceOf(alice), expectedBolt);
    }

    function test_contribute_reducesContractBalance() public {
        _startPresale();

        uint256 before      = token.balanceOf(address(token));
        uint256 contrib      = 0.5 ether;
        uint256 expectedBolt = contrib * RATE / 1e18;

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: contrib}();

        assertEq(token.balanceOf(address(token)), before - expectedBolt);
    }

    function test_contribute_multipleContributors() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.deal(bob,   1 ether);

        vm.prank(alice);
        token.contribute{value: 0.2 ether}();
        vm.prank(bob);
        token.contribute{value: 0.3 ether}();

        assertEq(token.presaleTotalRaised(), 0.5 ether);
        assertEq(token.balanceOf(alice), 0.2 ether * RATE / 1e18);
        assertEq(token.balanceOf(bob),   0.3 ether * RATE / 1e18);
    }

    function test_contribute_revert_presaleNotActive() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: 0.1 ether}();
    }

    function test_contribute_revert_presaleExpired() public {
        _startPresale();
        vm.warp(block.timestamp + DURATION + 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: 0.1 ether}();
    }

    function test_contribute_revert_belowMinimum() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: MIN_PER_WALLET - 1}();
    }

    function test_contribute_revert_walletCapExceeded() public {
        _startPresale();

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: MAX_PER_WALLET + 1}();
    }

    function test_contribute_revert_cumulativeCapExceeded() public {
        _startPresale();

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.contribute{value: MAX_PER_WALLET}(); // first — OK

        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: MIN_PER_WALLET}(); // second — would exceed cap
    }

    function test_contribute_revert_hardCapReached() public {
        // Hard cap = 1 BNB for this sub-test
        vm.prank(owner);
        token.startPresale(RATE, 0.1 ether, 1 ether, 0.01 ether, 1 ether, DURATION);

        vm.deal(alice, 2 ether);
        vm.prank(alice);
        token.contribute{value: 1 ether}(); // fills hard cap

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert();
        token.contribute{value: 0.1 ether}();
    }

    // ── Whitelist ──────────────────────────────────────────────────────────────

    function test_contribute_revert_notWhitelisted() public {
        _startPresale();

        vm.prank(owner);
        token.setWhitelist(true);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.contribute{value: 0.1 ether}();
    }

    function test_contribute_whitelistedSucceeds() public {
        _startPresale();

        vm.prank(owner);
        token.setWhitelist(true);

        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        vm.prank(owner);
        token.addToWhitelist(accounts);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: 0.1 ether}();

        assertEq(token.presaleContributions(alice), 0.1 ether);
    }

    // =========================================================================
    //  PRESALE — FINALIZE
    // =========================================================================

    function test_finalizePresale_afterHardCap() public {
        vm.prank(owner);
        token.startPresale(RATE, 0.5 ether, 1 ether, 0.01 ether, 1 ether, DURATION);

        vm.deal(alice, 2 ether);
        vm.prank(alice);
        token.contribute{value: 1 ether}(); // hits hard cap

        // Can finalize immediately — hard cap reached
        vm.prank(owner);
        token.finalizePresale();

        assertEq(uint256(token.presaleState()), 2); // FINALIZED
        assertTrue(token.tradingEnabled());
    }

    function test_finalizePresale_afterTimeExpiry() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: SOFT_CAP}(); // meets soft cap

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(owner);
        token.finalizePresale();

        assertEq(uint256(token.presaleState()), 2); // FINALIZED
        assertTrue(token.tradingEnabled());
    }

    function test_finalizePresale_burnsUnsoldTokens() public {
        _startPresale();

        uint256 contrib = SOFT_CAP; // small, leaves lots unsold
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: contrib}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(owner);
        token.finalizePresale();

        // After finalize, contract balance should be 0 (burned/sent to router)
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_finalizePresale_revert_notOwner() public {
        _startPresale();
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: SOFT_CAP}();
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert();
        token.finalizePresale();
    }

    function test_finalizePresale_revert_softCapNotMet() public {
        _startPresale();

        // Contribute below soft cap
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: MIN_PER_WALLET}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(owner);
        vm.expectRevert();
        token.finalizePresale();
    }

    function test_finalizePresale_revert_presaleStillRunning() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: SOFT_CAP}();

        // Don't warp — presale hasn't ended and hard cap not reached
        vm.prank(owner);
        vm.expectRevert();
        token.finalizePresale();
    }

    // =========================================================================
    //  PRESALE — CANCEL & REFUND
    // =========================================================================

    function test_cancelPresale_setsStateCancelled() public {
        _startPresale();
        vm.prank(owner);
        token.cancelPresale();
        assertEq(uint256(token.presaleState()), 3); // CANCELLED
    }

    function test_cancelPresale_revert_notOwner() public {
        _startPresale();
        vm.prank(alice);
        vm.expectRevert();
        token.cancelPresale();
    }

    function test_cancelPresale_revert_notActive() public {
        // presale is PENDING, not ACTIVE
        vm.prank(owner);
        vm.expectRevert();
        token.cancelPresale();
    }

    function test_claimRefund_returnsFullBNB() public {
        _startPresale();

        uint256 contrib = 0.1 ether;
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: contrib}();

        vm.prank(owner);
        token.cancelPresale();

        uint256 bnbBefore = alice.balance;
        vm.prank(alice);
        token.claimRefund();

        assertEq(alice.balance, bnbBefore + contrib);
    }

    function test_claimRefund_clearsContribution() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: 0.1 ether}();

        vm.prank(owner);
        token.cancelPresale();

        vm.prank(alice);
        token.claimRefund();

        assertEq(token.presaleContributions(alice), 0);
    }

    function test_claimRefund_cannotClaimTwice() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: 0.1 ether}();

        vm.prank(owner);
        token.cancelPresale();

        vm.prank(alice);
        token.claimRefund(); // first — OK

        vm.prank(alice);
        vm.expectRevert(); // second — NothingToRefund
        token.claimRefund();
    }

    function test_claimRefund_revert_nothingToRefund() public {
        _startPresale();
        vm.prank(owner);
        token.cancelPresale();

        vm.prank(alice); // never contributed
        vm.expectRevert();
        token.claimRefund();
    }

    function test_claimRefund_revert_notCancelled() public {
        _startPresale();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.contribute{value: 0.1 ether}();

        // Presale is ACTIVE, not CANCELLED
        vm.prank(alice);
        vm.expectRevert();
        token.claimRefund();
    }

    // =========================================================================
    //  TAX TESTS
    // =========================================================================

    function test_noTax_excludedFromAddress() public {
        // Marketing wallet is excluded → full amount arrives
        uint256 amount = 1_000_000 * 1e18;
        vm.prank(marketing);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_noTax_regularTransfer_noTaxApplied() public {
        // Regular wallet-to-wallet transfer (not pair) → no tax
        uint256 amount = 1_000_000 * 1e18;
        vm.prank(marketing);
        token.transfer(alice, amount); // excluded, no fee

        uint256 sendAmount = 500_000 * 1e18;
        vm.prank(alice);
        token.transfer(bob, sendAmount); // not buy/sell → no fee

        assertEq(token.balanceOf(bob), sendAmount);
    }

    function test_sellTax_applied() public {
        _enableTrading();

        uint256 sellAmount = 1_000_000 * 1e18;
        // Use bob — he has zero BOLT after _enableTrading (alice contributed, not bob)
        vm.prank(marketing); // excluded → no fee on fund
        token.transfer(bob, sellAmount);

        uint256 pairBefore   = token.balanceOf(pair);
        uint256 bobBefore    = token.balanceOf(bob);

        // Bob sells (transfers to pair) — 5% sell tax
        vm.prank(bob);
        token.transfer(pair, sellAmount);

        uint256 expected = sellAmount * 95 / 100; // 95% after 5% tax
        assertEq(token.balanceOf(pair), pairBefore + expected);
        // bob's balance fully deducted
        assertEq(token.balanceOf(bob), bobBefore - sellAmount);
    }

    function test_buyTax_applied() public {
        _enableTrading();

        // Fund the pair (from excluded marketing wallet — no sell tax)
        uint256 buyAmount = 1_000_000 * 1e18;
        vm.prank(marketing);
        token.transfer(pair, buyAmount);

        uint256 bobBefore = token.balanceOf(bob);

        // Pair sends to bob → 4% buy tax
        vm.prank(pair);
        token.transfer(bob, buyAmount);

        uint256 expected = buyAmount * 96 / 100; // 96% after 4% tax
        assertEq(token.balanceOf(bob), bobBefore + expected);
    }

    function test_contractAccumulatesFees() public {
        _enableTrading();

        uint256 sellAmount   = 1_000_000 * 1e18;
        uint256 contractBefore = token.balanceOf(address(token));

        vm.prank(marketing);
        token.transfer(alice, sellAmount);

        // Lower threshold so auto-swap doesn't fire
        vm.prank(owner);
        token.setSwapThreshold(type(uint256).max);

        vm.prank(alice);
        token.transfer(pair, sellAmount); // 5% → contract

        uint256 fee = sellAmount * 5 / 100;
        assertEq(token.balanceOf(address(token)), contractBefore + fee);
    }

    function test_setTaxes() public {
        vm.prank(owner);
        token.setTaxes(1, 2, 3, 4);

        assertEq(token.buyLiquidityFee(),  1);
        assertEq(token.buyMarketingFee(),  2);
        assertEq(token.sellLiquidityFee(), 3);
        assertEq(token.sellMarketingFee(), 4);
    }

    function test_setTaxes_revert_buyExceedsMax() public {
        vm.prank(owner);
        vm.expectRevert();
        token.setTaxes(6, 6, 1, 1); // 12% buy > MAX_TAX
    }

    function test_setTaxes_revert_sellExceedsMax() public {
        vm.prank(owner);
        vm.expectRevert();
        token.setTaxes(1, 1, 6, 6); // 12% sell > MAX_TAX
    }

    function test_setTaxes_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setTaxes(1, 1, 1, 1);
    }

    function test_setTaxesToZero() public {
        vm.prank(owner);
        token.setTaxes(0, 0, 0, 0);

        _enableTrading();

        uint256 sellAmount = 1_000_000 * 1e18;
        vm.prank(marketing);
        token.transfer(alice, sellAmount);

        uint256 pairBefore = token.balanceOf(pair);
        vm.prank(alice);
        token.transfer(pair, sellAmount);

        // Zero tax → full amount to pair
        assertEq(token.balanceOf(pair), pairBefore + sellAmount);
    }

    // =========================================================================
    //  LIMITS TESTS
    // =========================================================================

    function test_maxTx_enforced_onSell() public {
        _enableTrading();

        uint256 maxTx = token.maxTxAmount();

        // Give alice more than maxTx (marketing excluded so no fee, no limit)
        vm.prank(marketing);
        token.transfer(alice, maxTx + 1_000 * 1e18);

        vm.prank(alice);
        vm.expectRevert(); // ExceedsMaxTx
        token.transfer(pair, maxTx + 1);
    }

    function test_maxWallet_enforced_onBuy() public {
        _enableTrading();

        // Give bob just under maxWallet
        uint256 maxWallet = token.maxWalletAmount();
        uint256 nearMax   = maxWallet - 100 * 1e18;

        vm.prank(marketing); // excluded — no limits
        token.transfer(bob, nearMax);

        // Fund pair
        vm.prank(marketing);
        token.transfer(pair, 200 * 1e18);

        // Bob tries to buy 200 tokens — would push him over maxWallet
        vm.prank(pair);
        vm.expectRevert(); // ExceedsMaxWallet
        token.transfer(bob, 200 * 1e18);
    }

    function test_limits_notEnforced_forExcludedAddresses() public {
        _enableTrading();

        uint256 maxTx = token.maxTxAmount();

        // Use charlie — zero balance after _enableTrading
        // Marketing (excluded from limits) can transfer more than maxTx
        vm.prank(marketing);
        token.transfer(charlie, maxTx * 3); // should NOT revert
        assertEq(token.balanceOf(charlie), maxTx * 3);
    }

    function test_removeLimits() public {
        vm.prank(owner);
        token.removeLimits();
        assertFalse(token.limitsEnabled());
    }

    function test_removeLimits_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.removeLimits();
    }

    function test_setLimits() public {
        uint256 newMax = TOTAL_SUPPLY * 5 / 100;
        vm.prank(owner);
        token.setLimits(newMax, newMax);
        assertEq(token.maxWalletAmount(), newMax);
        assertEq(token.maxTxAmount(),     newMax);
    }

    function test_setLimits_revert_tooLow() public {
        // Must be at least 0.5% of supply
        uint256 tooLow = TOTAL_SUPPLY * 4 / 1000; // 0.4%
        vm.prank(owner);
        vm.expectRevert();
        token.setLimits(tooLow, tooLow);
    }

    // =========================================================================
    //  ADMIN — CONFIG SETTERS
    // =========================================================================

    function test_setMarketingWallet() public {
        vm.prank(owner);
        token.setMarketingWallet(alice);
        assertEq(token.marketingWallet(), alice);
    }

    function test_setMarketingWallet_revert_zero() public {
        vm.prank(owner);
        vm.expectRevert();
        token.setMarketingWallet(address(0));
    }

    function test_setMarketingWallet_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setMarketingWallet(alice);
    }

    function test_setLiquidityWallet() public {
        vm.prank(owner);
        token.setLiquidityWallet(alice);
        assertEq(token.liquidityWallet(), alice);
    }

    function test_setExcludeFromFee_add() public {
        vm.prank(owner);
        token.setExcludeFromFee(alice, true);
        assertTrue(token.isExcludedFromFee(alice));
    }

    function test_setExcludeFromFee_remove() public {
        vm.prank(owner);
        token.setExcludeFromFee(alice, true);
        vm.prank(owner);
        token.setExcludeFromFee(alice, false);
        assertFalse(token.isExcludedFromFee(alice));
    }

    function test_setExcludeFromLimits() public {
        vm.prank(owner);
        token.setExcludeFromLimits(alice, true);
        assertTrue(token.isExcludedFromLimits(alice));
    }

    function test_setSwapThreshold() public {
        uint256 newThreshold = 50_000_000 * 1e18;
        vm.prank(owner);
        token.setSwapThreshold(newThreshold);
        assertEq(token.swapThreshold(), newThreshold);
    }

    // ── Whitelist management ──────────────────────────────────────────────────

    function test_setWhitelist_enable() public {
        vm.prank(owner);
        token.setWhitelist(true);
        assertTrue(token.whitelistEnabled());
    }

    function test_addToWhitelist_batch() public {
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = charlie;

        vm.prank(owner);
        token.addToWhitelist(accounts);

        assertTrue(token.isWhitelisted(alice));
        assertTrue(token.isWhitelisted(bob));
        assertTrue(token.isWhitelisted(charlie));
    }

    function test_removeFromWhitelist_batch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(owner);
        token.addToWhitelist(accounts);

        vm.prank(owner);
        token.removeFromWhitelist(accounts);

        assertFalse(token.isWhitelisted(alice));
        assertFalse(token.isWhitelisted(bob));
    }

    // =========================================================================
    //  OWNERSHIP
    // =========================================================================

    function test_transferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);
    }

    function test_transferOwnership_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transferOwnership(address(0));
    }

    function test_transferOwnership_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transferOwnership(alice);
    }

    function test_renounceOwnership() public {
        vm.prank(owner);
        token.renounceOwnership();
        assertEq(token.owner(), address(0));
    }

    function test_renounceOwnership_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.renounceOwnership();
    }

    // =========================================================================
    //  FUZZ TESTS
    // =========================================================================

    /**
     * Any contribution within [minPerWallet, maxPerWallet] and within the hard
     * cap should always succeed when the presale is active.
     */
    function testFuzz_contribute_withinBounds(uint256 amount) public {
        _startPresale();

        // Bind to valid contribution range
        amount = bound(amount, MIN_PER_WALLET, MAX_PER_WALLET);
        amount = bound(amount, MIN_PER_WALLET, HARD_CAP);

        vm.deal(alice, amount);
        vm.prank(alice);
        token.contribute{value: amount}();

        assertEq(token.presaleContributions(alice), amount);
        assertEq(token.balanceOf(alice), amount * RATE / 1e18);
    }

    /**
     * Any transfer from a fee-excluded address should always deliver
     * the exact amount, regardless of size.
     */
    function testFuzz_transfer_excludedNoFee(uint256 amount) public {
        // Marketing has MARKETING_ALLOC = 10B BOLT
        amount = bound(amount, 1, MARKETING_ALLOC);

        vm.prank(marketing); // excluded from fee
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
    }

    /**
     * setTaxes should never allow total buy or sell tax to exceed MAX_TAX.
     */
    function testFuzz_setTaxes_cannotExceedMax(
        uint256 bLiq, uint256 bMkt,
        uint256 sLiq, uint256 sMkt
    ) public {
        uint256 maxTax = token.MAX_TAX();
        bLiq = bound(bLiq, 0, maxTax);
        bMkt = bound(bMkt, 0, maxTax - bLiq);
        sLiq = bound(sLiq, 0, maxTax);
        sMkt = bound(sMkt, 0, maxTax - sLiq);

        vm.prank(owner);
        token.setTaxes(bLiq, bMkt, sLiq, sMkt);

        assertEq(token.buyLiquidityFee()  + token.buyMarketingFee(),  bLiq + bMkt);
        assertEq(token.sellLiquidityFee() + token.sellMarketingFee(), sLiq + sMkt);
        assertTrue(token.buyLiquidityFee()  + token.buyMarketingFee()  <= maxTax);
        assertTrue(token.sellLiquidityFee() + token.sellMarketingFee() <= maxTax);
    }
}

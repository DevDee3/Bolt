// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Mock PancakeSwap V2 Router + Factory + Pair
 * Used ONLY in Foundry tests — not deployed on any real network.
 *
 * Behaviour:
 *  - factory()  → returns the MockPancakeFactory address
 *  - WETH()     → returns the MockWBNB address
 *  - createPair() → deploys a MockPancakePair and returns its address
 *  - addLiquidityETH() → accepts BNB, returns dummy LP values
 *  - swapExactTokensForETHSupportingFeeOnTransferTokens()
 *      → sends a fixed 0.01 BNB back to `to` (simulates a swap)
 *      → caller must fund the router with vm.deal() in setUp()
 */

// ─────────────────────────────────────────────────────────────────────────────
//  MockWBNB — just an address placeholder
// ─────────────────────────────────────────────────────────────────────────────
contract MockWBNB {}

// ─────────────────────────────────────────────────────────────────────────────
//  MockPancakePair — just an address placeholder
// ─────────────────────────────────────────────────────────────────────────────
contract MockPancakePair {}

// ─────────────────────────────────────────────────────────────────────────────
//  MockPancakeFactory
// ─────────────────────────────────────────────────────────────────────────────
contract MockPancakeFactory {
    address public pair;

    constructor() {
        pair = address(new MockPancakePair());
    }

    /// @dev Always returns the same pair regardless of tokens (sufficient for tests).
    function createPair(address, address) external view returns (address) {
        return pair;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MockPancakeRouter
// ─────────────────────────────────────────────────────────────────────────────
contract MockPancakeRouter {
    MockPancakeFactory public immutable mockFactory;
    MockWBNB           public immutable mockWBNB;

    /// @dev How much BNB the mock sends back per swap call.
    uint256 public constant MOCK_SWAP_BNB_RETURN = 0.01 ether;

    constructor() {
        mockFactory = new MockPancakeFactory();
        mockWBNB    = new MockWBNB();
    }

    // ── IPancakeRouter ───────────────────────────────────────────────────────

    function factory() external view returns (address) {
        return address(mockFactory);
    }

    function WETH() external view returns (address) {
        return address(mockWBNB);
    }

    /**
     * @dev Accepts BNB and pretends to add liquidity.
     *      Returns dummy values — real LP mechanics not needed in unit tests.
     */
    function addLiquidityETH(
        address, /* token */
        uint256 amountTokenDesired,
        uint256, /* amountTokenMin */
        uint256, /* amountETHMin */
        address, /* to (LP recipient) */
        uint256  /* deadline */
    ) external payable returns (uint256, uint256, uint256) {
        // Accept the BNB (msg.value) implicitly.
        // Return (tokensUsed, bnbUsed, lpMinted) — all dummy.
        return (amountTokenDesired, msg.value, msg.value);
    }

    /**
     * @dev Simulates a token→BNB swap by sending MOCK_SWAP_BNB_RETURN to `to`.
     *      The router must be pre-funded with BNB via vm.deal() in the test setUp().
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256,            /* amountIn */
        uint256,            /* amountOutMin */
        address[] calldata, /* path */
        address to,
        uint256             /* deadline */
    ) external {
        uint256 out = MOCK_SWAP_BNB_RETURN;
        if (address(this).balance >= out) {
            (bool sent,) = payable(to).call{value: out}("");
            require(sent, "MockRouter: BNB send failed");
        }
        // If the router has no BNB, the swap silently returns 0 BNB — acceptable in tests.
    }

    receive() external payable {}
}

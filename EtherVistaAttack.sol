// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ─────────────────────────────────────────────────────────────────────────────
//  EtherVista Router — Privileged Rug-Pull via Pair Drain (C01)
//
//  Vulnerability class: C01 — Missing / unvalidated caller authorisation
//  (the router's drain function 0x5ee3f775 is gate-kept by ONLY_RECOVERY_ADMIN;
//   the recovery admin IS the exploiter, making this a deliberate rug-pull)
//
//  Exploit flow (called by recovery-admin EOA, single call, no flash loan):
//    1. Admin EOA holds ≥ 1 TOKEN and has pre-approved the EtherVista Router
//    2. Admin calls Router.5ee3f775(token, 1):
//       a. Router verifies msg.sender == recoveryAdmin            (role check)
//       b. Router reads factory.getPair(token, WETH)  → pair
//       c. Router calls token.transferFrom(admin, pair, 1)
//          (1 token posted to the pair as nominal "input")
//       d. Router calls pair.swap(21.36 WETH out, 0, router, 0x)
//          Pair allows this because the only caller restriction is
//          require(msg.sender == factory.router()), which the EtherVista
//          router satisfies — there is NO constant-product (k) enforcement
//       e. Router now holds ~21.36 WETH
//       f. Router returns 9.02 WETH to pair + calls pair.sync()
//          (re-pegs pair reserves at the new, inflated token price)
//       g. Router returns 4.86 WETH to pair
//       h. Router calls pair.swap(0, 43 855 tokens out, admin, 0x)
//          (admin receives a large token dump)
//       i. Router forwards ~7.47 WETH to admin              (profit)
//    3. Net effect:
//         admin   : +7.47 WETH  (~$18 k)  +43 855 tokens − 1 token
//         pair    : −7.47 WETH net from liquidity providers (victims)
//
//  Root cause:
//    1. pair.swap() validates only msg.sender == factory.router() but does NOT
//       enforce k = x*y, allowing the router to extract arbitrary WETH.
//    2. Router.5ee3f775 is protected by ONLY_RECOVERY_ADMIN — a privileged role
//       held by the EtherVista team, enabling a deliberate rug-pull at any time.
//
//  Attack tx : 0xb2c7332d9e1be6a86d9d37083aa4cc0d94b60eb95cc9b29494555a3c09764930
//  Attack block: 26152259  (09 Oct 2026  03:47:59 UTC)
//  Fork block  : 26152258
// ─────────────────────────────────────────────────────────────────────────────

// ── interfaces ────────────────────────────────────────────────────────────────

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount)    external returns (bool);
    function balanceOf(address account)              external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @dev EtherVista pair — UniswapV2 fork with router-only swap guard.
///      swap() requires msg.sender == factory.router() but does NOT
///      verify the constant-product invariant.
interface IEtherVistaPair {
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32  blockTimestampLast
    );
    function token0() external view returns (address);
    function token1() external view returns (address);
    /// @dev Caller must be factory.router(); no k-invariant check.
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes   calldata data
    ) external;
    function sync() external;
    /// @dev c45a0155() returns the factory — EtherVista pair fingerprint.
    function c45a0155() external view returns (address);
}

/// @dev EtherVista factory.
interface IEtherVistaFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function router()                                external view returns (address);
}

/// @dev EtherVista Router — exposes only the exploited entry point.
///      Selector 0x5ee3f775 maps to the admin drain / fee-actualization path.
///      ONLY_RECOVERY_ADMIN: callable by the designated admin EOA only.
interface IEtherVistaRouter {
    // raw call via bytes4(0x5ee3f775) — args: (address token, uint256 amount)
}

// ── constants ─────────────────────────────────────────────────────────────────

library EtherVistaAddresses {
    address internal constant ROUTER  = 0x469424b628a9d2036e41496e814Db500D683b120;
    address internal constant FACTORY = 0x9a27cb5ae0B2cEe0bb71f9A85C0D60f3920757B4;
    address internal constant WETH    = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant TOKEN   = 0xC9bCa88B04581699fAb5aa276CCafF7Df957cbbf;
    address internal constant PAIR    = 0xfdd05552F1377aA488AFed744c8024358AF02041;
    /// @dev Recovery admin EOA — the privileged account that controls the router.
    ///      This is the tx sender in the original attack.
    address internal constant RECOVERY_ADMIN = 0xBBf8f3fe8e4FdF6b594E6107144D78293D2018Fa;
}

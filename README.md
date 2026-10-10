# EtherVista-18k-PoC

>**Chain:** Ethereum  
>**Root Cause:** C01 — Privileged rug-pull via unchecked pair-drain function

<img width="1790" height="359" alt="image" src="https://github.com/user-attachments/assets/b996e017-fd42-4226-b78e-c1f2198ea8f7" />

---

## Summary

| Field            | Value |
|------------------|-------|
| Chain            | Ethereum mainnet |
| Attack block     | 26152259 (09 Oct 2026 03:47:59 UTC) |
| Fork block       | 26152258 |
| TX hash          | `0xb2c7332d9e1be6a86d9d37083aa4cc0d94b60eb95cc9b29494555a3c09764930` |
| Profit           | **7.477 WETH** (`7_477_952_467_865_157_795 wei` ≈ $18k) |
| Vulnerability    | **C01 — Privileged rug-pull via unchecked pair-drain function** |
| Gas used         | ~316 650 |

## Root cause

The EtherVista Router contains a privileged function at selector **`0x5ee3f775`**
(internally guarded by `ONLY_RECOVERY_ADMIN`). When called by the admin:

1. The router calls `pair.swap(amount0Out = ENTIRE_WETH_RESERVE, 0, router, 0x)`.
2. The pair's `swap()` enforces **only** `require(msg.sender == factory.router())`.
   It does **not** verify the constant-product invariant `k = x * y`.
3. The router extracts virtually all WETH from the pair, then redistributes
   a fraction back with `sync()` and a second swap, keeping the difference
   as "admin fee" sent directly to the caller.

Because the admin EOA is the EtherVista deployer, this constitutes a
deliberate **rug-pull**: LP holders are silently drained whenever the admin
decides to call the function.

### Vulnerability class: C01 — Missing / unvalidated caller authorisation

The pair's `swap()` has access control (`router only`), but the **router itself**
is the privileged attacker.  The role `ONLY_RECOVERY_ADMIN` grants unrestricted
WETH extraction rights with no on-chain governance or time-lock.

Exploit TX: [View transaction on Phalcon](https://app.blocksec.com/phalcon/explorer/tx/eth/0xb2c7332d9e1be6a86d9d37083aa4cc0d94b60eb95cc9b29494555a3c09764930)

## Crafted calldata

1. Admin EOA holds ≥ 1 TOKEN and has pre-approved Router for 100 tokens.
3. Admin calls `Router.0x5ee3f775(TOKEN, 1)`.
4. Router calls `token.transferFrom(admin, pair, 1)` — 1 token posted.
5. Router calls `pair.swap(21.365 WETH out, 0, router, 0x)` — drains nearly
   all WETH (pair allowed because msg.sender == router, k not checked).
6. Router sends **9.026 WETH** back to pair + calls `pair.sync()` — resets
   reserves at an inflated token price.
7. Router sends **4.860 WETH** back to pair then calls
   `pair.swap(0, 43 855 tokens out, admin, 0x)` — dumps tokens on admin.

<img width="1465" height="373" alt="image" src="https://github.com/user-attachments/assets/54d28395-63d2-45a4-89b6-714946b4be91" />

9. Router sends **7.477 WETH** to admin — net profit from the drain.

**Net balance change:**

| Entity | WETH   | TOKEN |
|--------|--------|-------|
| Pair   | −7.477 WETH | −43 855 tokens |
| Admin  | +7.477 WETH | +43 855 tokens |

### Addresses

| Role                    | Address |
|-------------------------|---------|
| EtherVista Router       | `0x469424b628a9d2036e41496e814Db500D683b120` |
| EtherVista Factory      | `0x9a27cb5ae0B2cEe0bb71f9A85C0D60f3920757B4` |
| Token (attacked pair)   | `0xC9bCa88B04581699fAb5aa276CCafF7Df957cbbf` |
| WETH/Token Pair         | `0xfdd05552F1377aA488AFed744c8024358AF02041` |
| WETH                    | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| Recovery Admin (attacker EOA) | `0xBBf8f3fe8e4FdF6b594E6107144D78293D2018Fa` |

### Pair state at fork block

| Reserve  | Before              | After               |
|----------|---------------------|---------------------|
| WETH     | 21 365 578 509 624 935 898 wei | 13 887 626 041 759 778 103 wei |
| TOKEN    | 125 302 577 879 645 672 649 896 | 81 446 675 683 369 908 739 445 |

### Running the PoC

```bash
forge test -vvv
# Expected output: PASS  profit = 7_477_952_467_865_157_795 wei
```

Requirements: `forge` ≥ 1.7, internet access to `https://eth.drpc.org`.

### Proof of concept output

```text
=== BEFORE ===
pair  WETH  balance (wei) : 21365578509624935898
pair  TOKEN balance (wei) : 125302577879645672649896
admin WETH  balance (wei) : 0
admin TOKEN balance (wei) : 5864694170948497
=== AFTER ===
pair  WETH  balance (wei) : 13887626041759778103
pair  TOKEN balance (wei) : 81446675683369908739445
admin WETH  balance (wei) : 7477952467865157795
admin TOKEN balance (wei) : 43855902196275763910452
=== DELTA ===
pair WETH net change (wei) : 7477952467865157795
admin WETH profit    (wei) : 7477952467865157795
gas used                   : 311862

Suite result: ok. 1 passed; 0 failed; 0 skipped
```

**Output:**

Excerpt from the recorded trace: [attack_trace.coffee](./attack_trace.coffee).

```text
Transaction successfully executed.
Gas used: 316650
```

---

>
>Company : https://blockraider.io/
>
>Community : https://discord.gg/Vqqt7jyRr7
>
>Disclosure : https://t.me/blockraider_alerts_bot

<img width="161" height="51" alt="blockraider" src="https://github.com/user-attachments/assets/dc86222a-b5fb-49e8-9a9d-350973b7521d" />

# Yet Another Maximized Wrapped Ether implementation (YAM WETH)
Inspired by the commonly used [WETH9](https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2)
implementation and memes about it potentially being insolvent. Aims to be a more efficient
implementation while adding functionality that enhance the UX and efficiency of its general use.

## WETH9 Anti-patterns
To understand the optimizations possible with YAM-WETH we must first understand some of the common
anti-patterns introduced by WETH9's simplistic implementation. WETH9 namely lacks direct wrapping
and unwrapping methods (`withdraw`, `deposit`). Every wrap and unwrap occurs directly to and from
the caller's balance, however interfacing contract's often want to unwrap / wrap ETH on behalf of
other accounts.

- `YAM_WETH.depositTo{ value: amount }(recipient);` replaces:
  ```solidity
  WETH.deposit{ value: amount}();
  WETH.transfer(recipient, amount);
  ```
- `YAM_WETH.withdrawTo(recipient, amount);` replaces:
  ```solidity
  receive() external payable {
      require(msg.sender == address(WETH));
  }
  // ...
  WETH.withdraw(amount);
  SafeTransferLib.safeTransferETH(recipient, amount);
  ```
- `YAM_WETH.withdrawFrom(account, amount);` replaces:
  ```solidity
  receive() external payable {
      require(msg.sender == address(WETH));
  }
  // ...
  WETH.transferFrom(account, address(this), amount);
  WETH.withdraw(amount);
  ```
- `YAM_WETH.withdrawFromTo(from, to, amount);` replaces:
  ```solidity
  receive() external payable {
      require(msg.sender == address(WETH));
  }
  // ...
  WETH.transferFrom(from, address(this), amount);
  WETH.withdraw(amount);
  SafeTransferLib.safeTransferETH(to, amount);
  ```

Instead of having to perform these common patterns as distinctive calls YAM-WETH allows contracts to
directly perform them via a single call.

## Further Features
Beyond making common patterns more efficient YAM-WETH adds the following features which WETH9 does
not have:
- Multicall support: EOAs can safely bundle multiple calls into one transaction.
- EIP-2612 `permit`s: Allows users to gas-lessly approve contracts
- [Permit2](https://github.com/Uniswap/permit2) approval by default: Uniswap's Permit2 approval meta
  router is always approved, saving users the added approval.
- Primary operator: Allows users to set a primary operator which can spend tokens on their behalf,
  advantage over `approve` is that `transferFrom` calls by the primary operator are cheaper vs.
  `transferFrom` calls that rely on a granted allowance.
- Batched wrapping: Outside of `multicall` wrapping WETH on behalf of multiple accounts is made
  highly efficient via the purpose made `depositToMany`  and `depositAmountsToMany` methods.

## Storage Layout
To save gas a non-standard storage layout is used:

Slot Name | Slot Determination | Values Stored (Bits)
----|----|----
Total Supply | `slot = 0` | (95-0: `totalSupply`)

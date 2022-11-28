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

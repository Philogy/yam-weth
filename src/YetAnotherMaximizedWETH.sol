// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract YAM_WETH {
    uint256 internal constant TOTAL_SUPPLY_SLOT = 0;

    address public immutable PERMIT2;

    uint256 internal constant BALANCE_MASK = 0xffffffffffffffffffffffff;
    uint256 internal constant ADDR_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    bytes32 internal constant TRANSFER_EVENT_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    bytes32 internal constant APPROVAL_EVENT_SIG = 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    event PrimaryOperatorSet(address indexed account, address indexed prevOperator, address indexed newOperator);

    bytes32 internal constant PRIMARY_OPERATOR_EVENT_SIG =
        0x887b30d73fc01ab8c24c20c0b64cdd39b55b1e2b705237e4e4945e634e31ba74;

    /// @notice The reentrancy mutex slot
    /// @dev Will be removed in favor of transient storage post EIP-1153
    uint256 private MUTEX;

    error InsufficientBalance();
    error InsufficientFreeBalance();
    error InsufficientPermission();
    error ZeroAddress();
    error TotalSupplyOverflow();
    error NoReentrancy();
    error LoanExceedsBalance();
    error OutstandingDebt();

    modifier succeeds() {
        _;
        assembly {
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }

    constructor(address _permit2) {
        PERMIT2 = _permit2;
    }

    receive() external payable {
        deposit();
    }

    function name() external pure returns (string memory) {
        assembly {
            // "Yet Another Maximized Wrapped Ether Contract" (len: 44)
            mstore(0x4c, 0x68657220436f6e7472616374)
            mstore(0x40, 0x59657420416e6f74686572204d6178696d697a65642057726170706564204574)
            mstore(0x20, 0x2c)
            mstore(0x00, 0x20)
            return(0x00, 0x80)
        }
    }

    function symbol() external pure returns (string memory) {
        assembly {
            // "WETH"
            mstore(0x24, 0x57455448)
            mstore(0x20, 0x04)
            mstore(0x00, 0x20)
            return(0x00, 0x60)
        }
    }

    function decimals() external pure returns (uint8) {
        assembly {
            mstore(0x00, 0x12)
            return(0x00, 0x20)
        }
    }

    function approve(address _spender, uint256 _allowance) external payable succeeds returns (bool) {
        assembly {
            mstore(0x00, caller())
            mstore(0x20, _spender)
            sstore(keccak256(0x00, 0x40), _allowance)
            mstore(0x00, _allowance)
            log3(0x00, 0x20, APPROVAL_EVENT_SIG, caller(), _spender)
        }
    }

    function setPrimaryOperator(address _newOperator) external payable succeeds returns (bool) {
        assembly {
            let callerData := sload(caller())
            let prevOperator := shr(96, callerData)
            sstore(caller(), or(shl(96, _newOperator), and(callerData, BALANCE_MASK)))
            log4(0x00, 0x00, PRIMARY_OPERATOR_EVENT_SIG, caller(), prevOperator, _newOperator)
        }
    }

    function transfer(address _to, uint256 _amount) external payable succeeds returns (bool) {
        _transfer(_getData(msg.sender), msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) external payable succeeds returns (bool) {
        bytes32 fromData = _useAllowance(_from, _amount);
        _transfer(fromData, _from, _to, _amount);
    }

    function deposit() public payable succeeds returns (bool) {
        _depositAllTo(msg.sender);
    }

    function depositTo(address _recipient) external payable succeeds returns (bool) {
        _depositAllTo(_recipient);
    }

    function depositAmount(uint256 _amount) external payable succeeds returns (bool) {
        _depositAmountTo(msg.sender, _amount);
    }

    function depositAmountTo(address _recipient, uint256 _amount) external payable succeeds returns (bool) {
        _depositAmountTo(_recipient, _amount);
    }

    function depositToMany(address[] calldata _recipients, uint256 _amount) external payable succeeds returns (bool) {
        assembly {
            let recipientOffset := add(_recipients.offset, 0x04)
            let totalRecipients := calldataload(recipientOffset)
            let totalAmount := mul(totalRecipients, _amount)
            // `totalAmount` overflow check
            if iszero(eq(div(totalAmount, _amount), totalRecipients)) {
                revert(0x00, 0x00)
            }

            // totalSupply checks and updates
            let prevTotalSupply := sload(TOTAL_SUPPLY_SLOT)
            let newTotalSupply := add(prevTotalSupply, totalAmount)
            if or(gt(newTotalSupply, BALANCE_MASK), lt(newTotalSupply, prevTotalSupply)) {
                // `revert TotalSupplyOverflow()`
                mstore(0x00, 0xe5cfe957)
                revert(0x1c, 0x04)
            }
            if gt(newTotalSupply, selfbalance()) {
                // `revert InsufficientFreeBalance()`
                mstore(0x00, 0xa3bf9d5b)
                revert(0x1c, 0x04)
            }
            sstore(TOTAL_SUPPLY_SLOT, newTotalSupply)

            mstore(0x00, _amount)
            let hasErrors := 0
            // prettier-ignore
            for { let i := totalRecipients } i { i := sub(i, 1) } {
                let recipient := calldataload(add(recipientOffset, shl(5, i)))
                hasErrors := or(hasErrors, or(iszero(recipient), sub(recipient, and(recipient, ADDR_MASK))))
                sstore(recipient, add(sload(recipient), _amount))
                log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, recipient)
            }
            if hasErrors {
                revert(0x00, 0x00)
            }
        }
    }

    struct Deposit {
        address recipient;
        uint256 amount;
    }

    function depositAmountsToMany(Deposit[] calldata _deposits) external payable succeeds returns (bool) {
        assembly {
            let depositsOffset := add(_deposits.offset, 0x04)
            let totalDeposits := calldataload(depositsOffset)

            let prevDepositTotal := 0
            let depositTotal := 0

            let hasErrors := 0
            // prettier-ignore
            for { let i := totalDeposits } i { i := sub(i, 1) } {
                let pos := shl(6, i)
                prevDepositTotal := depositTotal
                let recipient := calldataload(add(depositsOffset, sub(pos, 1)))
                let amount := calldataload(add(depositsOffset, pos))
                depositTotal := add(depositTotal, amount)
                // Checks that `depositTotal += amount` did not overflow and that recipient is
                // a valid, non-zero address
                hasErrors :=
                    or(
                        hasErrors,
                        or(
                            gt(prevDepositTotal, depositTotal),
                            or(sub(recipient, and(recipient, ADDR_MASK)), iszero(recipient))
                        )
                    )
                sstore(recipient, add(sload(recipient), amount))
                mstore(0x00, amount)
                log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, recipient)
            }
            if hasErrors {
                revert(0x00, 0x00)
            }

            // totalSupply checks and updates
            let prevTotalSupply := sload(TOTAL_SUPPLY_SLOT)
            let newTotalSupply := add(prevTotalSupply, depositTotal)
            if or(gt(newTotalSupply, BALANCE_MASK), lt(newTotalSupply, prevTotalSupply)) {
                // `revert TotalSupplyOverflow()`
                mstore(0x00, 0xe5cfe957)
                revert(0x1c, 0x04)
            }
            if gt(newTotalSupply, selfbalance()) {
                // `revert InsufficientFreeBalance()`
                mstore(0x00, 0xa3bf9d5b)
                revert(0x1c, 0x04)
            }
            sstore(TOTAL_SUPPLY_SLOT, newTotalSupply)
        }
    }

    function withdraw(uint256 _amount) external payable succeeds returns (bool) {
        _withdrawTo(msg.sender, _amount);
    }

    function withdrawTo(address _to, uint256 _amount) external payable succeeds returns (bool) {
        _withdrawTo(_to, _amount);
    }

    function withdrawFrom(address _from, uint256 _amount) external payable succeeds returns (bool) {
        _withdrawFromTo(_from, msg.sender, _amount);
    }

    function withdrawFromTo(address _from, address _to, uint256 _amount) external payable succeeds returns (bool) {
        _withdrawFromTo(_from, _to, _amount);
    }

    function balanceOf(address _account) external view returns (uint256) {
        assembly {
            if iszero(_account) {
                revert(0x00, 0x00)
            }
            let bal := and(sload(_account), BALANCE_MASK)
            mstore(0x00, bal)
            return(0x00, 0x20)
        }
    }

    function allowance(address _account, address _spender) external view returns (uint256) {
        assembly {
            let data := sload(_account)
            mstore(0x00, not(0))
            if iszero(or(eq(shr(96, data), _spender), eq(_spender, PERMIT2))) {
                mstore(0x00, _account)
                mstore(0x20, _spender)
                mstore(0x00, sload(keccak256(0x00, 0x40)))
            }
            return(0x00, 0x20)
        }
    }

    function totalSupply() external view returns (uint256) {
        assembly {
            mstore(0x00, sload(TOTAL_SUPPLY_SLOT))
            return(0x00, 0x20)
        }
    }

    function primaryOperatorOf(address _account) external view returns (address) {
        assembly {
            if iszero(_account) {
                revert(0x00, 0x00)
            }
            let data := sload(_account)
            mstore(0x00, shr(96, data))
            return(0x00, 0x20)
        }
    }

    function _depositAllTo(address _to) internal {
        assembly {
            if iszero(_to) {
                // `revert ZeroAddress()`
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }

            let prevTotalSupply := sload(TOTAL_SUPPLY_SLOT)
            let depositAmount := sub(selfbalance(), prevTotalSupply)
            if gt(selfbalance(), BALANCE_MASK) {
                // `revert TotalSupplyOverflow()`
                mstore(0x00, 0xe5cfe957)
                revert(0x1c, 0x04)
            }
            sstore(TOTAL_SUPPLY_SLOT, selfbalance())
            sstore(_to, add(sload(_to), depositAmount))
            mstore(0x00, depositAmount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, _to)
        }
    }

    function _depositAmountTo(address _to, uint256 _amount) internal {
        assembly {
            if iszero(_to) {
                // `revert ZeroAddress()`
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }

            // No amount check because amount is explicit
            let prevTotalSupply := sload(TOTAL_SUPPLY_SLOT)
            let newTotalSupply := add(prevTotalSupply, _amount)
            if or(gt(newTotalSupply, BALANCE_MASK), lt(newTotalSupply, prevTotalSupply)) {
                // `revert TotalSupplyOverflow()`
                mstore(0x00, 0xe5cfe957)
                revert(0x1c, 0x04)
            }
            if gt(newTotalSupply, selfbalance()) {
                // `revert InsufficientFreeBalance()`
                mstore(0x00, 0xa3bf9d5b)
                revert(0x1c, 0x04)
            }

            sstore(TOTAL_SUPPLY_SLOT, newTotalSupply)
            sstore(_to, add(sload(_to), _amount))
            mstore(0x00, _amount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, _to)
        }
    }

    function _withdrawTo(address _to, uint256 _amount) internal {
        _withdrawDirectFromTo(_getData(msg.sender), msg.sender, _to, _amount);
    }

    function _withdrawFromTo(address _from, address _to, uint256 _amount) internal {
        bytes32 fromData = _useAllowance(_from, _amount);
        _withdrawDirectFromTo(fromData, _from, _to, _amount);
    }

    function _transfer(bytes32 _fromData, address _from, address _to, uint256 _amount) internal {
        assembly {
            if iszero(_to) {
                // `revert ZeroAddress()`
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            if gt(_amount, and(_fromData, BALANCE_MASK)) {
                // `revert InsufficientBalance()`
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(_from, sub(_fromData, _amount))
            sstore(_to, add(sload(_to), _amount))
            mstore(0x00, _amount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, _from, _to)
        }
    }

    function _useAllowance(address _from, uint256 _amount) internal returns (bytes32 fromData) {
        assembly {
            fromData := sload(_from)

            if iszero(or(eq(caller(), shr(96, fromData)), eq(caller(), PERMIT2))) {
                // Not primary operator or Permit2, check allowance
                mstore(0x00, _from)
                mstore(0x20, caller())
                let allowanceSlot := keccak256(0x00, 0x40)
                let senderAllowance := sload(allowanceSlot)
                if iszero(eq(senderAllowance, not(0))) {
                    // No infinite approval
                    if gt(_amount, senderAllowance) {
                        // `revert InsufficientPermission()`
                        mstore(0x00, 0xdeda9030)
                        revert(0x1c, 0x04)
                    }
                    sstore(allowanceSlot, sub(senderAllowance, _amount))
                }
            }
        }
    }

    function _getData(address _account) internal view returns (bytes32 data) {
        assembly {
            data := sload(_account)
        }
    }

    function _withdrawDirectFromTo(bytes32 _fromData, address _from, address _to, uint256 _amount) internal {
        assembly {
            if gt(_amount, and(_fromData, BALANCE_MASK)) {
                // `revert InsufficientBalance()`
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(_from, sub(_fromData, _amount))
            sstore(TOTAL_SUPPLY_SLOT, sub(sload(TOTAL_SUPPLY_SLOT), _amount))
            mstore(0x00, _amount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, _from, 0)

            let success := call(gas(), _to, _amount, 0x00, 0x00, 0x00, 0x00)
            if iszero(success) {
                returndatacopy(0x00, 0x00, returndatasize())
                return(0x00, returndatasize())
            }
        }
    }

    /// @notice Sends a flash loan of `amount` WETH to the caller from the `from`
    ///         address' balance.
    /// @dev    Reverts if the caller does not repay their loan by the end of the
    ///         subcontext's execution.
    ///         Will be updated to use transient storage post EIP-1153.
    /// @param  from   - The receiver of the flash loan. Must be a contract with a
    ///                 `flashWeth(uint256)` function.
    /// @param  amount - The amount of WETH in WEI to be loaned to `msg.sender`.
    function flashLoan(address from, uint256 amount) external {
        assembly {
            // Do not allow nested flash loans
            if eq(sload(MUTEX.slot), 0x01) {
                // "NoReentrancy()" error signature
                mstore(returndatasize(), 0x583fe886)
                revert(0x1c, 0x04)
            }

            // Lock the mutex
            sstore(MUTEX.slot, 0x01)

            // Get the initial WETH balance of the `from` address
            let fromInitialBalance := sload(from)

            // Do not allow loaning more tokens than `from`'s balance
            if gt(amount, fromInitialBalance) {
                // "LoanExceedsBalance()" error signature
                mstore(returndatasize(), 0x912b4508)
                revert(0x1c, 0x04)
            }

            // Update the `from` address' balance
            sstore(from, sub(fromInitialBalance, amount))
            // Update the caller's balance
            sstore(caller(), add(sload(caller()), amount))

            // Store the `flashWeth(uint256)` signature and the `amount`
            // in scratch space.
            mstore(returndatasize(), 0xdd27fe7a)
            mstore(0x20, amount)

            // Call the `from` contract's `flashWeth(uint256)` function.
            // If the call reverts, bubble up the returndata from the call.
            if iszero(call(gas(), caller(), returndatasize(), 0x1c, 0x24, returndatasize(), returndatasize())) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }

            // Ensure that the loan from the above call's subcontext
            // has been repaid to the `from` address.
            if lt(sload(from), fromInitialBalance) {
                // "OutstandingDebt()" error signature
                mstore(0x00, 0xe90cbfe8)
                revert(0x1c, 0x04)
            }

            // Clear mutex slot
            sstore(MUTEX.slot, 0x00)

            stop()
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract YAM_WETH {
    uint256 internal constant TOTAL_SUPPLY_SLOT = 0;

    // TODO: Set real address
    address internal constant PERMIT2 = 0x5B34BD375516Ef47A12bb8AB066f2Cb528a90E74;

    uint256 internal constant BALANCE_MASK = 0xffffffffffffffffffffffff;

    bytes32 internal constant TRANSFER_EVENT_SIG = 0x5b34bd375516ef47a12bb8ab066f2cb528a90e74ccc4e1fa540274953b32829c;
    bytes32 internal constant APPROVAL_EVENT_SIG = 0x21bd8b32bd9fdf66c11d1101cae7a294f2d39bc08bac77b0f88fa907721c260b;
    // event `PrimaryOperatorSet(address indexed operator)`
    bytes32 internal constant PRIMARY_OPERATOR_EVENT_SIG =
        0xa4fc55e949965ca58de1b448de3f5c17e96f249e4793ee91ccc6dc901b1763ac;

    error InsufficientBalance();
    error InsufficientFreeBalance();
    error InsufficientPermission();
    error ZeroAddress();
    error TotalSupplyOverflow();

    modifier succeeds() {
        _;
        assembly {
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
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

    function setPrimaryOperator(address _primaryOperator) external payable succeeds returns (bool) {
        assembly {
            sstore(caller(), or(shl(96, _primaryOperator), and(sload(caller()), BALANCE_MASK)))
            log2(0x00, 0x00, PRIMARY_OPERATOR_EVENT_SIG, _primaryOperator)
        }
    }

    function transfer(address _to, uint256 _amount) external payable succeeds returns (bool) {
        assembly {
            if iszero(_to) {
                // `revert ZeroAddress()`
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            let fromData := sload(caller())
            if gt(_amount, and(fromData, BALANCE_MASK)) {
                // `revert InsufficientBalance()`
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(caller(), sub(fromData, _amount))
            sstore(_to, add(sload(_to), _amount))
            mstore(0x00, _amount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, caller(), _to)
        }
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external payable succeeds returns (bool) {
        assembly {
            if iszero(_to) {
                // `revert ZeroAddress()`
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        bytes32 fromData = _useAllowance(_from, _amount);
        assembly {
            if gt(_amount, and(fromData, BALANCE_MASK)) {
                // `revert InsufficientBalance()`
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }

            sstore(_from, sub(fromData, _amount))
            sstore(_to, add(sload(_to), _amount))

            mstore(0x00, _amount)
            log3(0x00, 0x20, TRANSFER_EVENT_SIG, _from, _to)
        }
    }

    function depositAll() external payable succeeds returns (bool) {
        _depositAllTo(msg.sender);
    }

    function depositAllTo(address _recipient) external payable succeeds returns (bool) {
        _depositAllTo(_recipient);
    }

    function deposit(uint256 _amount) external payable succeeds returns (bool) {
        _depositAmountTo(msg.sender, _amount);
    }

    function depositTo(address _recipient, uint256 _amount) external payable succeeds returns (bool) {
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
            // prettier-ignore
            for { let i := totalRecipients } i { i := sub(i, 1) } {
                let recipient := calldataload(add(recipientOffset, shl(5, i)))
                sstore(recipient, add(sload(recipient), _amount))
                log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, recipient)
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
            let overflowed := 0

            // prettier-ignore
            for { let i := totalDeposits } i { i := sub(i, 1) } {
                let pos := shl(6, i)
                prevDepositTotal := depositTotal
                let recipient := calldataload(add(depositsOffset, sub(pos, 1)))
                let amount := calldataload(add(depositsOffset, pos))
                depositTotal := add(depositTotal, amount)
                overflowed := or(overflowed, gt(prevDepositTotal, depositTotal))

                sstore(recipient, add(sload(recipient), amount))
                mstore(0x00, amount)
                log3(0x00, 0x20, TRANSFER_EVENT_SIG, 0, recipient)
            }

            // totalSupply checks and updates
            let prevTotalSupply := sload(TOTAL_SUPPLY_SLOT)
            let newTotalSupply := add(prevTotalSupply, depositTotal)
            if or(or(gt(newTotalSupply, BALANCE_MASK), lt(newTotalSupply, prevTotalSupply)), overflowed) {
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

    function withdrawFromTo(
        address _from,
        address _to,
        uint256 _amount
    ) external payable succeeds returns (bool) {
        _withdrawFromTo(_from, _to, _amount);
    }

    function balanceOf(address _account) external view returns (uint256) {
        assembly {
            let bal := and(sload(_account), BALANCE_MASK)
            mstore(shl(0xff, iszero(_account)), bal)
            return(0x00, 0x20)
        }
    }

    function allowance(address _account, address _spender) external view returns (uint256) {
        assembly {
            mstore(0x00, _account)
            mstore(0x20, _spender)
            mstore(0x00, sload(keccak256(0x00, 0x40)))
            return(0x00, 0x20)
        }
    }

    function totalSupply() external view returns (uint256) {
        assembly {
            mstore(0x00, sload(TOTAL_SUPPLY_SLOT))
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
            if depositAmount {
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
        bytes32 fromData;
        assembly {
            fromData := sload(caller())
        }
        _withdrawDirectFromTo(fromData, msg.sender, _to, _amount);
    }

    function _withdrawFromTo(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        bytes32 fromData = _useAllowance(_from, _amount);
        _withdrawDirectFromTo(fromData, _from, _to, _amount);
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

    function _withdrawDirectFromTo(
        bytes32 _fromData,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
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
}

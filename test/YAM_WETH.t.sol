// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {YAM_WETH} from "../src/YetAnotherMaximizedWETH.sol";
import {HonestBorrower} from "./flashloan/HonestBorrower.sol";
import {ReentrantBorrower} from "./flashloan/ReentrantBorrower.sol";
import {OverflowBorrower} from "./flashloan/OverflowBorrower.sol";
import {RunawayBorrower} from "./flashloan/RunawayBorrower.sol";

contract YAM_WETH_Test is Test {
    YAM_WETH weth;

    address mainUser = vm.addr(1);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event PrimaryOperatorSet(address indexed account, address indexed prevOperator, address indexed newOperator);

    function setUp() public {
        weth = new YAM_WETH();
    }

    function testName() public {
        assertEq(weth.name(), "Yet Another Maximized Wrapped Ether Contract");
    }

    function testSymbol() public {
        assertEq(weth.symbol(), "WETH");
    }

    function testDefaultBalance(address _account) public {
        vm.assume(_account != address(0));
        assertEq(weth.balanceOf(_account), 0);
    }

    function testDeposit(address _account, uint96 _amount) public {
        vm.assume(_account != address(0));
        vm.deal(_account, _amount);
        vm.prank(_account);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), _account, _amount);
        assertTrue(weth.deposit{value: _amount}());
        assertEq(weth.balanceOf(_account), _amount);
    }

    function testSetOperator(address _account, address _operator1, address _operator2, uint96 _initialBalance) public {
        vm.assume(_account != address(0));
        setupBalance(_account, _initialBalance);

        vm.prank(_account);
        vm.expectEmit(true, true, true, true);
        emit PrimaryOperatorSet(_account, address(0), _operator1);
        weth.setPrimaryOperator(_operator1);
        assertEq(weth.balanceOf(_account), _initialBalance);
        assertEq(weth.primaryOperatorOf(_account), _operator1);

        vm.prank(_account);
        vm.expectEmit(true, true, true, true);
        emit PrimaryOperatorSet(_account, _operator1, _operator2);
        assertTrue(weth.setPrimaryOperator(_operator2));
        assertEq(weth.balanceOf(_account), _initialBalance);
        assertEq(weth.primaryOperatorOf(_account), _operator2);
    }

    function testTransfer(
        address _from,
        address _to,
        address _fromOperator,
        address _toOperator,
        uint96 _fromStartBal,
        uint96 _toStartBal,
        uint96 _transferAmount
    ) public {
        vm.assume(_from != address(0));
        vm.assume(_to != address(0));
        vm.assume(_from != _to);
        vm.assume(_transferAmount <= _fromStartBal);
        vm.assume(uint256(_fromStartBal) + uint256(_toStartBal) <= uint256(type(uint96).max));
        setupBalance(_from, _fromStartBal);
        setupBalance(_to, _toStartBal);
        setupOperator(_from, _fromOperator);
        setupOperator(_to, _toOperator);

        vm.prank(_from);
        vm.expectEmit(true, true, true, true);
        emit Transfer(_from, _to, _transferAmount);
        assertTrue(weth.transfer(_to, _transferAmount));
        assertEq(weth.balanceOf(_from), _fromStartBal - _transferAmount, "from bal mismatch");
        assertEq(weth.balanceOf(_to), _toStartBal + _transferAmount, "to bal mismatch");
        assertEq(weth.primaryOperatorOf(_from), _fromOperator);
        assertEq(weth.primaryOperatorOf(_to), _toOperator);
    }

    function calldata1() public {
        YAM_WETH.Deposit[] memory deposits = new YAM_WETH.Deposit[](3);
        deposits[0] = YAM_WETH.Deposit(vm.addr(20), 1);
        deposits[1] = YAM_WETH.Deposit(vm.addr(21), 2);
        deposits[2] = YAM_WETH.Deposit(vm.addr(21), 3);
        bytes memory data = abi.encodeCall(YAM_WETH.depositAmountsToMany, (deposits));
        emit log_named_bytes("data", data);
    }

    function setupBalance(address _account, uint96 _balance) internal {
        vm.deal(_account, _balance);
        vm.prank(_account);
        weth.deposit{value: _balance}();
    }

    function setupOperator(address _account, address _operator) internal {
        vm.prank(_account);
        weth.setPrimaryOperator(_operator);
    }

    ////////////////////////////////////////////////////////////////
    //                      FLASH LOAN TESTS                      //
    ////////////////////////////////////////////////////////////////

    /// @notice Tests a successful flash loan
    function test_flashLoan_repayLoan_success() public {
        // Deploy a borrower
        HonestBorrower borrower = new HonestBorrower(weth, address(this));

        // Get 10 WETH
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();

        // Start a loan and repay it in full
        borrower.startLoan(1 ether);

        assertEq(weth.balanceOf(address(this)), 10 ether);
        assertEq(weth.balanceOf(address(borrower)), 0);
    }

    /// @notice Ensures that the call to `flashLoan` reverts if it is
    /// reentered within any subcontext of the original call.
    function test_flashLoan_reentrancy_reverts() public {
        ReentrantBorrower borrower = new ReentrantBorrower(weth, address(this));

        // Get 10 WETH
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();

        vm.expectRevert(YAM_WETH.NoReentrancy.selector);
        borrower.startLoan(1 ether);
    }

    /// @notice Ensures that the call to `flashLoan` reverts if more
    /// tokens than the `from` address has were requested.
    function test_flashLoan_overflow_reverts() public {
        OverflowBorrower borrower = new OverflowBorrower(weth, address(this));

        // Get 10 WETH
        vm.deal(address(this), 1 ether);
        weth.deposit{value: 1 ether}();

        vm.expectRevert(YAM_WETH.LoanExceedsBalance.selector);
        borrower.startLoan(1 ether);
    }

    /// @notice Ensures that the call to `flashLoan` reverts if debt is not
    /// repaid by the end of the subcontext's execution
    function test_flashLoan_runaway_reverts() public {
        RunawayBorrower borrower = new RunawayBorrower(weth, address(this));

        // Get 10 WETH
        vm.deal(address(this), 1 ether);
        weth.deposit{value: 1 ether}();

        vm.expectRevert(YAM_WETH.OutstandingDebt.selector);
        borrower.startLoan(1 ether);
    }
}

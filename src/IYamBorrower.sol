pragma solidity 0.8.15;

/// @title IYamBorrower
/// @dev This interface must be adhered to by contracts receiving YAMWETH
///      flash loans.
interface IYamBorrower {
    /// @notice Called when a flashloan to this contract is received.
    ///         The outstand loan must be paid back by the end of
    ///         this function's execution.
    function flashWeth(uint256 amount) external;
}

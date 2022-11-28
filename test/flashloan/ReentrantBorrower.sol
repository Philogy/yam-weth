pragma solidity 0.8.15;

import {IYamBorrower} from "../../src/IYamBorrower.sol";
import {YAM_WETH} from "../../src/YetAnotherMaximizedWETH.sol";

contract ReentrantBorrower is IYamBorrower {
    YAM_WETH weth;
    address from;

    constructor(YAM_WETH _weth, address _from) {
        weth = _weth;
        from = _from;
    }

    /// @notice Called when a flashloan to this contract is initiated.
    function flashWeth(uint256 amount) external {
        weth.flashLoan(from, amount);
    }

    /// @notice Initiates a flash loan subcontext
    function startLoan(uint256 amount) external {
        weth.flashLoan(from, amount);
    }
}

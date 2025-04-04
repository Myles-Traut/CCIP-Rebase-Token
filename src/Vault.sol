// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/**
 * @title Vault
 * @notice A vault that allows users to deposit ETH in exchange for an equal amount of RebaseToken
 * @notice Users can redeem their ETH by calling withdraw and burning any RebaseTokens they have
 */
contract Vault {
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function deposit() public payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) public {
        // mitigate dust if user burns all their tokens
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function rebaseTokenAddress() public view returns (address) {
        return address(i_rebaseToken);
    }
}

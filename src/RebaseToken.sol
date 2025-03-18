// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/*
    *@title Rebase Token
    * @notice This is a cross chain rebase toen that incentavises users to deposit into a vault
    * @notice The interest rate in the smart contract will only ever decrease over time
    * @notice each user will have their own interest rate that is the global interest rate at the time of deposit
*/
contract RebaseToken is ERC20, Ownable2Step, AccessControl {
    //-------------------------//
    //--------- ERRORS --------//
    //-------------------------//
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 _oldInterestRate, uint256 _newInterestRate);

    //-------------------------//
    //--------- EVENTS --------//
    //-------------------------//
    event InterestRateUpdated(uint256 indexed _newInterestRate);

    //-------------------------//
    //-------- STORAGE --------//
    //-------------------------//
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e10;

    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastUpdatedTimestamp) private s_userLastUpdatedTimestamp;

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    //-------------------------//
    //---- STATE CHANGING -----//
    //-------------------------//

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // mitigate dust if user burns all their tokens
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Transfer tokens to a recipient
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool success
     * @dev A user can deposit a small amount with one wallet and then a large amount at a later date with another wallet.
     * They can then transfer all tokens to the first wallet and get the higher interest rate.
     * This is a known issue.
     * A mitigation could be to set the _recipients interest rate to the global interest rate on transfer.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        // mint outstanding interest to caller and recipient
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        // check if sending entire balance and mitigate dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // if recipient has no balance, set their interest rate to that of the sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        // mint outstanding interest to caller and recipient
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        // check if sending entire balance and mitigate dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        // if recipient has no balance, set their interest rate to that of the sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    //-------------------------//
    //-- INTERNAL FUNCTIONS ---//
    //-------------------------//

    function _mintAccruedInterest(address _user) internal {
        // (1) find the current balance of rebase tokens that have been minted to the user (principal)
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        // (2)calculate their current balance including any interest (balanceOf)
        uint256 currentBalance = balanceOf(_user);
        // calculate the amount of tokens that need to be minted to the user (2) - (1) = amount to mint
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        // set users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint
        _mint(_user, balanceIncrease);
    }

    function _calculateAccruedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // We need to caculate the interest accrued since the last update
        // This is going to be linear growth with time
        // 1. Calculate time since last update
        // 2. Calculate the amount of linear growth
        // (principal amount) + (principal amount * interest rate * time elapsed)
        // or (principal amount) * (1 + (interest rate * time elapsed))
        // Deposit: 10 tokens
        // Interest rate: 0.5 tokens per second
        // Time elapsed: 2 seconds
        // (10) + 10 * 0.5 * 2

        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_interestRate * timeElapsed);
    }

    //-------------------------//
    //------- GETTERS --------//
    //-------------------------//
    /**
     * @notice Get the principal balance of a user. This is the amount of tokens that have currently been minted to the user, not including any interest that has accrued since the last time the user interacted with he protocol.
     * @param _user The address of the user
     * @return uint256 The principal balance of the user
     */
    function getPrincipalBalance(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Get the current balance of a user. This is the amount of tokens that have currently been minted to the user, including any interest that has accrued since the last time the user interacted with he protocol.
     * @param _user The address of the user
     * @return uint256 The current balance of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principal balance of the user
        // multiply the principal by the interest accrued since the last update
        return (super.balanceOf(_user) * _calculateAccruedInterestSinceLastUpdate(_user) / PRECISION_FACTOR);
    }

    /**
     * @notice Get the interest rate of a user
     * @param _user The address of the user
     * @return uint256 The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the current global interest rate
     * @return uint256 The current interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the last updated timestamp of a user
     * @param _user The address of the user
     * @return uint256 The last updated timestamp of the user
     */
    function getUserLastUpdatedTimestamp(address _user) external view returns (uint256) {
        return s_userLastUpdatedTimestamp[_user];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("OWNER");
    address public user = makeAddr("USER");

    function setUp() public {
        deal(owner, 1 ether);

        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addVaultRewards(uint256 _amount) public {
        (bool success,) = payable(address(vault)).call{value: _amount}("");
        require(success, "Failed to send ETH to vault");
    }

    function testDepositLinearInterest(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vm.warp(block.timestamp + 1 hours);

        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startingBalance);

        vm.warp(block.timestamp + 1 hours);

        uint256 endingBalance = rebaseToken.balanceOf(user);
        assertGt(endingBalance, middleBalance);

        assertApproxEqAbs(endingBalance - middleBalance, middleBalance - startingBalance, 1);
    }

    function testRedeemStraightAway(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
    }

    function testRedeemAfterTime(uint256 _depositAmount, uint256 _time) public {
        _time = bound(_time, 1000, type(uint96).max);
        _depositAmount = bound(_depositAmount, 1e5, type(uint96).max);

        deal(user, _depositAmount);
        vm.prank(user);
        vault.deposit{value: _depositAmount}();

        vm.warp(block.timestamp + _time);
        uint256 balanceAfterTime = rebaseToken.balanceOf(user);

        deal(owner, balanceAfterTime - _depositAmount);
        vm.prank(owner);
        addVaultRewards(balanceAfterTime - _depositAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, balanceAfterTime);
        assertGt(ethBalance, _depositAmount);
    }

    function testTransfer(uint256 _amount, uint256 _amountToSend) public {
        _amount = bound(_amount, 1e5 + 1e5, type(uint96).max);
        _amountToSend = bound(_amountToSend, 1e5, _amount - 1e5);

        // Deposit
        deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();

        address user2 = makeAddr("USER2");

        assertEq(rebaseToken.balanceOf(user), _amount);
        assertEq(rebaseToken.balanceOf(user2), 0);

        // Owner reduces Interest Rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // Transfer
        vm.prank(user);
        rebaseToken.transfer(user2, _amountToSend);

        // Assert
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, _amount - _amountToSend);
        assertEq(user2BalanceAfterTransfer, _amountToSend);

        // Check that interest rate has been inherited (5e10, not 4e10)
        assertEq(rebaseToken.getInterestRate(), 4e10);
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testTransferFrom(uint256 _amount, uint256 _amountToSend) public {
        _amount = bound(_amount, 1e5 + 1e5, type(uint96).max);
        _amountToSend = bound(_amountToSend, 1e5, _amount - 1e5);

        // Deposit
        deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();

        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        assertEq(rebaseToken.balanceOf(user), _amount);
        assertEq(rebaseToken.balanceOf(user3), 0);

        // Owner reduces Interest Rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // Transfer
        vm.prank(user);
        rebaseToken.approve(user2, _amountToSend);

        vm.prank(user2);
        rebaseToken.transferFrom(user, user3, _amountToSend);

        // Assert
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user3BalanceAfterTransfer = rebaseToken.balanceOf(user3);

        assertEq(userBalanceAfterTransfer, _amount - _amountToSend);
        assertEq(user3BalanceAfterTransfer, _amountToSend);

        // Check that interest rate has been inherited (5e10, not 4e10)
        assertEq(rebaseToken.getInterestRate(), 4e10);
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user3), 5e10);
    }

    function testCannotCallSetInterestRate(uint256 _newInterestRate) public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        bytes32 MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, MINT_AND_BURN_ROLE));
        rebaseToken.mint(user, 1e18, userInterestRate);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, MINT_AND_BURN_ROLE));
        rebaseToken.burn(user, 1e18);
    }

    function testGetPrincipalBalanceOf(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);

        deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();

        assertEq(rebaseToken.getPrincipalBalanceOf(user), _amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.getPrincipalBalanceOf(user), _amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.getPrincipalBalanceOf(user), _amount);    
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.rebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 _newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        _newInterestRate = bound(_newInterestRate, initialInterestRate, type(uint96).max);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(
            RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector,
            initialInterestRate,
            _newInterestRate
        ));
        rebaseToken.setInterestRate(_newInterestRate);

        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    function testSetInterestRateEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RebaseToken.InterestRateUpdated(1e10);
        rebaseToken.setInterestRate(1e10);
    }

    function testCannotGrantRole() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.grantMintAndBurnRole(user);
    }
}

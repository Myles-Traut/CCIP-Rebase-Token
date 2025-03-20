// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

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

    function test_Deposit_Linear_Interest(uint256 _amount) public {
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

    function test_Redeem_Straight_Away(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
    }

    function test_Redeem_After_Time(uint256 _depositAmount, uint256 _time) public {
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
}

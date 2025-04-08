// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "@ccip-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    uint256 public sepoliaFork;
    uint256 public arbSepoliaFork;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Register.NetworkDetails public sepoliaNetworkDetails;
    Register.NetworkDetails public arbSepoliaNetworkDetails;

    RebaseToken public sepoliaToken;
    RebaseToken public arbSepoliaToken;

    Vault public vault;

    RebaseTokenPool public sepoliaPool;
    RebaseTokenPool public arbSepoliaPool;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public SEND_VALUE = 1e5;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arb_sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // Make the ccipLocalSimulatorFork persistent across chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // 1. Deploy and configure on Sepolia
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        sepoliaToken.grantMintAndBurnRole(address(vault));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        // 2. Deploy and configure on ArbSepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();

        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            true,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            true,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    // struct ChainUpdate {
    //     uint64 remoteChainSelector; // ──╮ Remote chain selector
    //     bool allowed; // ────────────────╯ Whether the chain should be enabled
    //     bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
    //     bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
    //     RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
    //     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
    // }

    function configureTokenPool(
        uint256 _fork,
        address _localPool,
        uint64 _remoteChainSelector,
        bool _allowed,
        address _remotePoolAddress,
        address _remoteTokenAddress
    ) public {
        vm.selectFork(_fork);

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            allowed: _allowed,
            remotePoolAddress: abi.encode(_remotePoolAddress),
            remoteTokenAddress: abi.encode(_remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(owner);
        TokenPool(_localPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 _amountToBridge,
        uint256 _localFork,
        uint256 _remoteFork,
        Register.NetworkDetails memory _localNetworkDetails,
        Register.NetworkDetails memory _remoteNetworkDetails,
        RebaseToken _localToken,
        RebaseToken _remoteToken
    ) public {
        vm.selectFork(_localFork);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(_localToken), amount: _amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: _localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false}))
        });
        uint256 fee =
            IRouterClient(_localNetworkDetails.routerAddress).getFee(_remoteNetworkDetails.chainSelector, message);

        // Drip some Link to the User
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        vm.prank(user);
        IERC20(_localNetworkDetails.linkAddress).approve(_localNetworkDetails.routerAddress, fee);

        vm.prank(user);
        IERC20(address(_localToken)).approve(_localNetworkDetails.routerAddress, _amountToBridge);

        uint256 localBalanceBefore = _localToken.balanceOf(user);

        vm.prank(user);
        IRouterClient(_localNetworkDetails.routerAddress).ccipSend(_remoteNetworkDetails.chainSelector, message);

        uint256 localBalanceAfter = _localToken.balanceOf(user);

        assertEq(localBalanceAfter, localBalanceBefore - _amountToBridge);

        vm.selectFork(_remoteFork);
        vm.warp(block.timestamp + 20 minutes);

        uint256 remoteBalanceBefore = _remoteToken.balanceOf(user);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(_remoteFork);

        uint256 remoteBalanceAfter = _remoteToken.balanceOf(user);

        assertEq(remoteBalanceAfter, remoteBalanceBefore + _amountToBridge);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        deal(user, SEND_VALUE);

        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);

        // Bridge Tokens to ArbSepolia
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);

        // Bridge Tokens back to Sepolia
        bridgeTokens(
            arbSepoliaToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }
}

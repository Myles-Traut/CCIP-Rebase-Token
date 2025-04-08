// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address _tokenToSendAddress,
        uint256 _amountToSend,
        address _receiverAddress,
        address _routerAddress,
        address _linkTokenAddress,
        uint64 _destinationChainSelector
    ) public {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _tokenToSendAddress, amount: _amountToSend});

        vm.startBroadcast();
        // struct EVM2AnyMessage {
        //      bytes receiver; // abi.encode(receiver address) for dest EVM chains
        //      bytes data; // Data payload
        //     EVMTokenAmount[] tokenAmounts; // Token transfers
        //     address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        //     bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
        //   }
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: _linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 ccipFee = IRouterClient(_routerAddress).getFee(_destinationChainSelector, message);
        IERC20(_linkTokenAddress).approve(_routerAddress, ccipFee);
        IERC20(_tokenToSendAddress).approve(_routerAddress, _amountToSend);
        IRouterClient(_routerAddress).ccipSend(_destinationChainSelector, message);
        vm.stopBroadcast();
    }
}

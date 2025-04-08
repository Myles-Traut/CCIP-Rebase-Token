// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePool is Script {
    function run(
        address _localPool,
        uint64 _remoteChainSelector,
        address _remotePoolAddress,
        address _remoteTokenAddress,
        bool _outboundRateLimiterIsEnabled,
        uint128 _outboundRateLimiterCapacity,
        uint128 _outboundRateLimiterRate,
        bool _inboundRateLimiterIsEnabled,
        uint128 _inboundRateLimiterCapacity,
        uint128 _inboundRateLimiterRate
    ) public {
        vm.startBroadcast();

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(_remotePoolAddress),
            remoteTokenAddress: abi.encode(_remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _outboundRateLimiterIsEnabled,
                capacity: _outboundRateLimiterCapacity,
                rate: _outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _inboundRateLimiterIsEnabled,
                capacity: _inboundRateLimiterCapacity,
                rate: _inboundRateLimiterRate
            })
        });

        TokenPool(_localPool).applyChainUpdates(chainsToAdd);

        vm.stopBroadcast();
    }
}

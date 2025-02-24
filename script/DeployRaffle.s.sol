// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {
        deployRaffleContract();
    }

    function deployRaffleContract() public returns (Raffle, HelperConfig) {
        // the helperConfig contract
        HelperConfig helperConfig = new HelperConfig();

        // the network config
        // on local network --> deploy mocks -then-> get local config
        // on sepolia network --> get local config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // if there are no subscriptionID, this will set it to a new one
        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscription createSubscriptionContract = new CreateSubscription();
            (
                config.subscriptionId,
                config.vrfCoordinator
            ) = createSubscriptionContract.createSubscription(
                config.vrfCoordinator,
                config.account
            );

            // fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator,
                config.subscriptionId,
                config.link,
                config.account
            );
        }

        // when there is a subscriptionID, deploy the contract
        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();

        // no need to braodcast, cause inside the function there is a broadcast
        addConsumer.addConsumer(
            address(raffle),
            config.vrfCoordinator,
            config.subscriptionId,
            config.account
        );

        return (raffle, helperConfig);
    }
}

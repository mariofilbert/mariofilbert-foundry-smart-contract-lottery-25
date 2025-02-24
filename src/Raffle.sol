// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/**
 * @author  Mario Filbert
 * @title   Raffle - A sample Raffle contract
 * @dev     Implements Chainlink VRF v2.5
 * @notice  A contract for creating a sample raffle
 */

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__SendMoreToEnter();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    }

    /* State Variables */
    bool private enableNativePayment = false;
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // @dev The duration of the lottery in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        // inherited from the VRFConsumerBaseV2Plus
        // s_vrfCoordinator.requestRandomWords();
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent!");
        // require(msg.value >= i_entranceFee, SendMoreToEnter());
        // console.log(msg.value);
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnter();
        }
        s_players.push(payable(msg.sender));

        // 1. Makes migration easier
        // 2. Makes front end "indexing" easier
        // emitting an event makes it easier and cheaper to read logs and track changes without having to query the blockchain (reading from storage is expensive)
        emit RaffleEntered(msg.sender);

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
    }

    // When should the winner be picked?
    /**
     * @dev This is the function that the Chainlink nodes will call to see if the lottery is ready to pick a winner
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. The subscription has LINK
     * @param - ignored
     * @return  upkeepNeeded  - true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;

        return (upkeepNeeded, "");
    }

    // 1. Getting a random number
    // 2. Use random number to pick a player
    // 3. Making the call automatic
    function performUpkeep(bytes calldata /* performData */) external {
        // (before automation)
        // checking if enough time has passed
        // if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //     revert();
        // }
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                //gas price is keyHash
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATION,
                //gas limit is callbackGasLimit
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: enableNativePayment
                    })
                )
            });

        // s_vrfCoordinator.requestRandomWords(request);
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        // a bit redundant because the vrfCoordinator also emits the requestID, but is done to making test a bit easier
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions Pattern

    // the override keyword is used to override the virtual function (which was defined in the abstract contract(VRFConsumerBaseV2Plus) that has no functionality)
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        // Checks
        // conditionals (if statements, require)

        // ex: there are 10 player --> s_player = 10;
        // rng (random number) = 12 --> 12 % 10 = 2, then player @ array 2 is the winner of the raffle (s_players[2])
        //
        // this random number will be used to pick a player

        //Effect (Internal Contract State)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;

        // wiping out the old players
        s_players = new address payable[](0);
        // resetting the timestamp
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract Interaction)
        (bool success, ) = recentWinner.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

// import {FailingRecipient} from "test/mocks/FailingRecipient.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    // address public FAILING_RECIPIENT = makeAddr("FailingRecipient");

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffleContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /*/////////////////////////////////////////////////////////////*/
    ////////////////////////// RAFFLE TEST //////////////////////////
    /*/////////////////////////////////////////////////////////////*/

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenPaymentNotEnough() public {
        // Arrage
        vm.prank(PLAYER);

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnter.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenEnteredSuccessfully() public {
        // Arrage
        vm.prank(PLAYER);
        // console.log(
        //     "player balance:",
        //     PLAYER.balance,
        //     "entranceFee:",
        //     entranceFee
        // );
        // Act
        raffle.enterRaffle{value: entranceFee}();

        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);

        // Act
        // the three first bool values are the indexed parameters (as long as there is an indexed paramater it will be true)
        // the fourth bool value is th non-indexed parameter
        // the last address is the address that emits the event
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testPlayersNotAllowedToEnterWhenRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // settting the timestamp to the next interval + 1
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*/////////////////////////////////////////////////////////////*/
    ////////////////////// CHECK UPKEEP TEST ////////////////////////
    /*/////////////////////////////////////////////////////////////*/

    // named this way because this test function assumed that the contract state is already OPEN, in this case:
    // there are players, the raffle is open, and enough time has passed
    function testCheckUpkeepReturnsIfItHasNoBalance() public {
        // Arrange
        // this two lines of code ensures that enough
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeed, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeed);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // settting the timestamp to the next interval + 1
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // changing the state of the raffle to calculating (closed)
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // settting the timestamp to the next interval + 1
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //  Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    /*/////////////////////////////////////////////////////////////*/
    ////////////////////// PERFORM UPKEEP TEST //////////////////////
    /*/////////////////////////////////////////////////////////////*/

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // settting the timestamp to the next interval + 1
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        // making a false condition
        uint256 currentBalance = 0;
        uint numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = numPlayers + 1;

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // settting the timestamp to the next interval + 1
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // an example of getting data from emitted events
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        // Arrange

        // Act
        vm.recordLogs(); // record logs emitted from events
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // the entries is set to a struct Log { bytes32[] topics;bytes data; address emitter; } coming from the Vm.Log
        // at entries index 0, will be the first log that is emitted from the vrfCoordinator, which is why in this one index 1 is used
        // the topics is also using index number 1, as the number 0 is reserved for smth else
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // if this function test is ran, this raffle state is the second element of the nested array inside the second array
        assert(uint256(raffleState) == 1);
        assert(uint256(requestId) != 0);
    }

    /*/////////////////////////////////////////////////////////////*/
    ///////////////////// FULFILL RANDOM WORDS TEST /////////////////
    /*/////////////////////////////////////////////////////////////*/

    // skipping the test if the chain is not local because VRFCoordinatorV2_5Mock does not exist on-chain
    // also only Chainlink can fulfill request on mainnet/testnet
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    // an example of stateless fuzz test
    function testFullfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        // Act / Assert / Arrange
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendMoney()
        public
        raffleEntered
        skipFork
    {
        // Arrange
        uint256 additionalEntrance = 3; // 4 people total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrance;
            i++
        ) {
            address newPlayer = address(uint160(i));
            // prank & deal
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs(); // record logs emitted from events
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrance + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }

    /* Still Failing
    // function testFulfillRandomWordsRevertsWhenTransferFailed()
    //     public
    //     skipFork
    //     raffleEntered
    // {

    //     FailingRecipient failingRecipient = new FailingRecipient();
    //     address player2 = address(failingRecipient);
    //     vm.deal(player2, 1 ether);
    //     vm.prank(player2);
    //     raffle.enterRaffle{value: entranceFee}();

    //     vm.warp(block.timestamp + interval + 1);
    //     vm.roll(block.number + 1);

    //     vm.recordLogs(); // record logs emitted from events
    //     raffle.performUpkeep("");
    //     Vm.Log[] memory entries = vm.getRecordedLogs();
    //     bytes32 requestId = entries[1].topics[1];

    //     // vm.expectRevert();
    //     vm.expectRevert(Raffle.Raffle__TransferFailed.selector);
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
    //         uint256(requestId),
    //         address(raffle)
    //     );
    // } */
}

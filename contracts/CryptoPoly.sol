// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract CryptoPoy {

	//enum Colors{BROWN, CIAN, MAGENTA, ORANGE, RED, YELLOW, GREEN, BLUE,
	//			SERVICE, STATION, COMMUNITY, LUCKY}

	//These two must be a URI
	string public communityCardsURI;
	string public luckyCardsURI;

	mapping(address => uint256) getPlayer; //starting from 1

	uint256 enteringPrice = 100;

	struct Player {
		uint256 balance;
		uint256 slot;
		uint256	isInJail;
		address	wallet;
		uint256[12] heritage; //the order is the "Colors" one
		//mapping(Colors => uint256) heritage;
	}

	//REFERENCE (http://www.jdawiseman.com/papers/trivia/monopoly-rents.html)
	//mortgage = cost/2
	struct Slot {
		uint256 owner; //owner = 0 if it has no owners
		uint256 progress; //site-only, 1h, 2h, 3h, 4houses & hotel
		uint256 cost;
		uint256[6] rent;
		//Colors color;
		uint256 color; //the order is the "Colors" one
	}

	Player[] players; //size equals maxPlayersAmount
	Slot[40] slots;

	uint256 public timeLimit;
	uint256 public immutable turnTime = 1 minutes;
	uint256 public doubleDiceStreak;
	bool public isReward;

	uint256 public playersAmount;
	uint256 public immutable maxPlayersAmount = 8;
	uint256 public luckyCardsAmount = 20; //TODO: get actual amount of lucky and community cards
	uint256 public communityCardsAmount = 10;

	uint256 public turnIndex;
	bool	public hasRolled;
	uint256 public auctionIndex; //above zero if an auction is in progress
	uint256 public auctionPrice;
	uint256 public auctionOwner; //starting from 1

//===========================================================================================
	//TODO: manage time, end of game, reset of variables, progress of houses, cards, when a player is in bankrupcy

	modifier onlyTurn {
		if (timeLimit + turnTime < block.timestamp)
			_next_turn();
		require(getPlayer[msg.sender] - 1 == turnIndex, "Wait to your turn!");
		_;
	}

	modifier noAuction {
		require(auctionIndex == 0, "There's an auction in progress!");
		_;
	}

	modifier afterRoll {
		require(hasRolled = true, "You can only do this after rolling the dice");
		_;
	}

	modifier notStarted {
		require(timeLimit == 0, "The game is in progress!");
		_;
	}

	modifier started {
		require(timeLimit > 0, "The game has not started yet!");
		_;
	}

	modifier inTime {
		if (timeLimit > block.timestamp)
			_next_turn();
		_;
	}

	constructor(string memory _communityCardsURI, string memory _luckyCardsURI,
				uint256[40] memory _costs, uint256[40][6] memory _rents, uint256[40] memory _colors,
				uint256 _enteringPrice) {
		communityCardsURI = _communityCardsURI;
		luckyCardsURI = _luckyCardsURI;
		for (uint256 i = 0; i < 40; i++) {
			slots[i].cost = _costs[i];
			for (uint256 j = 0; j < 6; j++)
				slots[i].rent[j] = _rents[i][j];
			slots[i].color = _colors[i];
		}
		enteringPrice = _enteringPrice;
	}

	function join_party() public payable notStarted {
		Player memory currentPlayer;

		require(playersAmount < maxPlayersAmount, "Game is full!");
		require(msg.value == enteringPrice, "Please enter the exact entering price!");
		currentPlayer.balance = 1500;
		currentPlayer.wallet = msg.sender;
		playersAmount++;
		getPlayer[msg.sender] = playersAmount;

		players.push(currentPlayer);
	}

	function start_game() public notStarted { //TODO: any player can start the game
		require(playersAmount >= 3, "Not enough players to start!");
		turnIndex = random(playersAmount);
		for (uint256 i = 0; i < playersAmount; i++)
			players[i].balance = 1500;
	}

	function run() public started inTime onlyTurn noAuction {
		uint256 playerIndex = getPlayer[msg.sender] - 1;

		_roll(playerIndex);
		if (players[playerIndex].isInJail > 0)
			players[playerIndex].isInJail--;
		if (doubleDiceStreak == 0 || doubleDiceStreak > 2)
			_next_turn();
	}

	function buy(bool _yes) public started onlyTurn noAuction afterRoll {
		uint256 playerIndex = getPlayer[msg.sender] - 1;
		Slot storage currentSlot = slots[auctionIndex];

		require(currentSlot.owner == 0, "This property has already an owner!");

		if (_yes == true && timeLimit + turnTime < block.timestamp) {
			require(players[playerIndex].balance > currentSlot.cost, "You have insufficient funds!");
			players[playerIndex].balance -= currentSlot.cost;
			players[playerIndex].heritage[currentSlot.color]++;
			currentSlot.owner = playerIndex + 1;
			_next_turn();
		} else{
			auctionIndex = players[playerIndex].slot;
			timeLimit = block.timestamp + 2 minutes;
		}
	}

	function bid(uint256 _amount) public started {
		uint256 playerIndex = getPlayer[msg.sender] - 1;
		Slot storage currentSlot = slots[auctionIndex];

		require(auctionIndex > 0, "There's no properties to bid for");
		require(_amount > players[playerIndex].balance, "You have insufficient funds!");

		if (block.timestamp < timeLimit) {
			if (_amount > auctionPrice) {
				auctionOwner = playerIndex + 1;
				auctionPrice = _amount;
			}
		} else {
			currentSlot.owner = auctionOwner;
			players[auctionOwner - 1].balance -= auctionPrice;
			auctionIndex = 0;
			auctionPrice = 0;
			auctionOwner = 0;
			_next_turn();
		}
	}

	function pay_free() public started onlyTurn noAuction {
		Player storage currentPlayer = players[getPlayer[msg.sender] - 1];

		require(currentPlayer.slot == 10, "You're not in jail!");
		require(currentPlayer.balance > 50, "You have insufficient funds!");
		require(currentPlayer.isInJail < 3, "Wait the next turn to do this!");

		currentPlayer.balance -= 50;
		currentPlayer.isInJail = 0;
	}

//===========================================================================================

	function _roll(uint256 _playerIndex) internal {
		uint256[2] memory dice;
		Player storage currentPlayer = players[_playerIndex];
		dice[0] = random(6) + 1; //TODO: optimize to only use random once
		dice[1] = random(6) + 1;

		if(dice[0] == dice[1]){
			if (currentPlayer.isInJail > 0)
				currentPlayer.isInJail = 0;
			else
				++doubleDiceStreak;
		}
		if (doubleDiceStreak < 3 && currentPlayer.isInJail == 0){
			currentPlayer.slot += dice[0] + dice[1];

			if (currentPlayer.slot >= 40){
				isReward = true;
				currentPlayer.slot -= 40;
			}
			_check_slot(_playerIndex);
		} else if (doubleDiceStreak > 2) {
			if (isReward == true)
				isReward = false;
			players[_playerIndex].slot = 10;
			players[_playerIndex].isInJail = 3;
		}
	}

	function _next_turn() internal {
		uint256 i = 1;

		if (isReward == true) {
			players[turnIndex].balance += 200;
			isReward = false;
		}
		if (doubleDiceStreak > 0)
			doubleDiceStreak = 0;
		while (players[turnIndex + i].balance == 0)
			i++;
		turnIndex = (turnIndex + i < playersAmount) ? turnIndex + i : turnIndex + i - playersAmount;
		hasRolled = false;
		timeLimit = block.timestamp + turnTime;
	}

	function _check_slot(uint256 _playerIndex) internal {
		Player storage currentPlayer = players[_playerIndex];
		Slot storage currentSlot = slots[currentPlayer.slot];

		if (currentSlot.color < 7 && currentSlot.color > 0) {
			if (currentSlot.owner > 0) { //TODO: manage when player is out of funds
				currentPlayer.balance -= currentSlot.rent[currentSlot.progress];
				players[currentSlot.owner - 1].balance += currentSlot.rent[currentSlot.progress];
			}
		} else if (currentPlayer.slot == 19) {
			currentPlayer.slot = 10;
			currentPlayer.isInJail = 3;
		}
	}

	function _end_game() internal {

	}

	function random(uint256 _module) internal returns(uint256) {
		//TODO: get truly random number using chainlink
	}

}

// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract CryptoPoy {

	enum Colors{BROWN, CIAN, MAGENTA, ORANGE, RED, YELLOW, GREEN, BLUE,
				SERVICE, STATION, COMMUNITY, LUCKY}

	//These two must be a URI
	string public communityCardsURI;
	string public luckyCardsURI;

	mapping(address => uint256) getPlayer;

	struct Player {
		uint256 balance;
		uint256 slot;
		uint256	isInJail;
		address	wallet;
		mapping(Colors => uint256) heritage;
	}

	//REFERENCE (http://www.jdawiseman.com/papers/trivia/monopoly-rents.html)
	//mortgage = cost/2
	struct Slot {
		uint256 owner; //owner = 0 if it has no owners
		uint256 progress; //site-only, 1h, 2h, 3h, 4houses & hotel
		uint256 cost;
		uint256[6] rent;
		Colors color;
		bool sold;
	}

	Player[8] players; //size equals maxPlayersAmount
	Slot[40] slots;

	uint256 public lastTime;
	uint256 public turnTime = 1 minutes;

	uint256 public playersAmount;
	uint256 public maxPlayersAmount = 8;
	uint256 public luckyCardsAmount = 20; //TODO: get true amount of lucky and community cards
	uint256 public communityCardsAmount = 10;

	uint256 public turnIndex = maxPlayersAmount;
	uint256 public auctionIndex;
	uint256 public auctionPrice;

//===========================================================================================
	//TODO: manage time, end of game and reset of variables

	constructor(string memory _communityCardsURI, string memory _luckyCardsURI,
				uint256[40] memory _costs, uint256[40][6] memory _rents, Colors[40] memory _colors) {
		communityCardsURI = _communityCardsURI;
		luckyCardsURI = _luckyCardsURI;
		for (uint256 i = 0; i < 40; i++) {
			slots[i].cost = _costs[i];
			for (uint256 j = 0; j < 6; j++)
				slots[i].rent[j] = _rents[i][j];
			slots[i].color = _colors[i];
		}
	}

	function run() public {
		uint256 playerIndex = getPlayer[msg.sender];

		if (turnIndex == maxPlayersAmount) { //game has not started
			turnIndex = random(playersAmount);
			for (uint256 i = 0; i < playersAmount; i++)
				players[i].balance = 1500;
		}
		require(playerIndex == turnIndex, "Wait to your turn!");
		_roll(playerIndex);
		require(players[playerIndex].isInJail-- == 0, "You're still in jail!");

		turnIndex = (turnIndex > playersAmount - 1) ? 0 : turnIndex + 1;
	}

	function _roll(uint256 _playerIndex) internal {
		uint256[2] memory dice;
		uint256 times;
		bool isReward;
		Player storage currentPlayer = players[_playerIndex];

		while(dice[0] == dice[1] && ++times < 3){

			dice[0] = random(6) + 1; //TODO: optimize to only use random once
			dice[1] = random(6) + 1;

			if (dice[0] == dice[1] && currentPlayer.isInJail > 0)
				currentPlayer.isInJail = 0;

			if (currentPlayer.isInJail == 0) {
				currentPlayer.slot += dice[0] + dice[1];

				if (currentPlayer.slot >= 40){
					isReward = true;
					currentPlayer.slot -= 40;
				}
				_check_slot(_playerIndex);
			}
		}

		if (times > 2) {
			if (isReward == true)
				isReward = false;
			players[_playerIndex].slot = 10;
			players[_playerIndex].isInJail = 3;
		} else if (isReward == true)
			players[_playerIndex].balance += 200;
	}

	function _check_slot(uint256 _playerIndex) internal {
		Player storage currentPlayer = players[_playerIndex];
		Slot storage currentSlot = slots[currentPlayer.slot];

		if (currentPlayer.slot == 19) {
			currentPlayer.slot = 10;
			currentPlayer.isInJail = 3;
		} else if (currentSlot.owner > 0) { //TODO: manage when player is out of funds
				currentPlayer.balance -= currentSlot.rent[currentSlot.progress];
				players[currentSlot.owner - 1].balance += currentSlot.rent[currentSlot.progress];
		} else {
			auctionIndex = currentPlayer.slot;
			currentSlot.owner = _playerIndex + 1;
		}
	}

	function bid(uint256 _amount) public {
		uint256 playerIndex = getPlayer[msg.sender];
		Slot storage currentSlot = slots[auctionIndex];

		require(_amount > players[playerIndex].balance, "You have insufficient funds!");
		require(auctionIndex > 0, "There's no properties to bid for");
		if (currentSlot.owner == playerIndex + 1) {
			if (_amount == currentSlot.cost) {
				currentSlot.sold = true;
				auctionIndex = 0;
			} else
				currentSlot.owner = 0;
		} else
			require(_amount > auctionPrice, "Amount must be higher than the previous bid!");
		auctionPrice = _amount;
	}

	function random(uint256 _module) internal returns(uint256) {
		//TODO: get truly random number using chainlink
	}

}

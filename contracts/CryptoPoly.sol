// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract CryptoPoy {

	//enum Colors{BROWN, CIAN, MAGENTA, ORANGE, RED, YELLOW, GREEN, BLUE,
	//			SERVICE, STATION, COMMUNITY, LUCKY}
	uint256[12] colorsAmounts = [2, 3, 3, 3, 3, 3, 3, 2, 2, 4, 3, 3];

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
		uint256[] slotsOwned;
		uint256 houses;
		uint256 hotels;
	}

	//REFERENCE (http://www.jdawiseman.com/papers/trivia/monopoly-rents.html)
	//mortgage = cost/2
	struct Slot {
		uint256 owner; //owner = 0 if it has no owners
		uint256 progress; //site-only, 1h, 2h, 3h, 4houses & hotel
		uint256 cost;
		uint256[6] rent;
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

	uint256 public houses = 32;
	uint256 public hotels = 12;

	uint256 public turnIndex;
	bool	public hasRolled;
	uint256 public auctionIndex; //above zero if an auction is in progress
	uint256 public auctionPrice;
	uint256 public auctionOwner; //starting from 1

	uint256 public tradeFrom;
	uint256 public tradeTo;
	uint256 public tradeAmount;
	uint256 public tradeItem;

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
				uint256[40] memory _costs, uint256[40][6] memory _rents, uint256[40] memory _colors) {
		communityCardsURI = _communityCardsURI;
		luckyCardsURI = _luckyCardsURI;
		for (uint256 i = 0; i < 40; i++) {
			slots[i].cost = _costs[i];
			for (uint256 j = 0; j < 6; j++)
				slots[i].rent[j] = _rents[i][j];
			slots[i].color = _colors[i];
		}
	}

	function join_party() public payable notStarted {
		require(playersAmount < maxPlayersAmount, "Game is full!");
		require(msg.value == enteringPrice, "Please enter the exact entering price!");

		Player memory currentPlayer;

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
		Slot storage currentSlot = slots[auctionIndex];

		require(currentSlot.owner == 0, "This property has already an owner!");
		uint256 playerIndex = getPlayer[msg.sender] - 1;

		if (_yes == true && timeLimit + turnTime < block.timestamp) {
			require(players[playerIndex].balance > currentSlot.cost, "You have insufficient funds!");
			players[playerIndex].balance -= currentSlot.cost;
			//players[playerIndex].heritage[currentSlot.color]++;
			currentSlot.owner = playerIndex + 1;
			_next_turn();
		} else{
			auctionIndex = players[playerIndex].slot;
			timeLimit = block.timestamp + 2 minutes;
		}
	}

	function upgrade(uint256 _slot, uint256 _buyTo, uint256 _amount) public started onlyTurn noAuction afterRoll { //buyTo starting from 1
		Player storage currentPlayer = players[getPlayer[msg.sender] - 1];

		require(slots[_slot].owner == getPlayer[msg.sender], "You are not the owner!");
		require(_is_upgradeable(_slot, currentPlayer.slotsOwned) == true, "The progress of each slot you own is not enough!");

		if (slots[currentPlayer.slot].progress < 5) {
			if (_buyTo == 0)
				require(houses > 0, "There are no houses left to buy!");
			else
				_buy_to(true, _buyTo, _amount);
			return ;
		} else {
			if (_buyTo == 0)
				require(hotels > 0, "There are no hotels left to buy!");
			else
				_buy_to(false, _buyTo, _amount);
			return ;
		}
		require(currentPlayer.balance > 150, "You have insufficient funds!");
		slots[_slot].progress++;
	}

	function bid(uint256 _amount) public started {
		uint256 playerIndex = getPlayer[msg.sender] - 1;

		require(auctionIndex > 0, "There's no properties to bid for");
		require(_amount > players[playerIndex].balance, "You have insufficient funds!");

		if (block.timestamp < timeLimit) {
			if (_amount > auctionPrice) {
				auctionOwner = playerIndex + 1;
				auctionPrice = _amount;
			}
		} else {
			players[auctionOwner - 1].balance -= auctionPrice;
			_own(auctionOwner - 1, players[auctionOwner - 1].slot);
			auctionIndex = 0;
			auctionPrice = 0;
			auctionOwner = 0;
			_check_bankrupt(auctionOwner - 1);
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

	function _next_turn() internal { //check if broke players can still play (they shouldn't)
		uint256 i = 1;

		if (isReward == true) {
			players[turnIndex].balance += 200;
			isReward = false;
		}
		if (doubleDiceStreak > 0)
			doubleDiceStreak = 0;
		while (players[turnIndex + i].balance == 0)
			i++;
		turnIndex = (turnIndex + i < players.length) ? turnIndex + i : turnIndex + i - players.length;
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

	function _check_bankrupt(uint256 _playerIndex) internal {
		if (players[_playerIndex].balance == 0) {
			Player storage currentPlayer = players[_playerIndex];

			playersAmount--;
			for (uint256 i = 0; i < currentPlayer.slotsOwned.length; i++) {
				slots[currentPlayer.slotsOwned[i]].owner = 0;
			}
			delete currentPlayer.slotsOwned;
		}
	}

	function _is_upgradeable(uint256 _slot, uint256[] memory _slotsOwned) internal view returns (bool) {
		uint256 color = slots[_slot].color;
		uint256[4] memory sameColorArray;
		uint256 array_length;
		uint256 currentProgress = slots[_slot].progress;

		for (uint256 i = 0; i < _slotsOwned.length; i++)
			if (slots[_slotsOwned[i]].color == color) {
				sameColorArray[array_length] = _slotsOwned[i];
				array_length++;
			}
		require (array_length < colorsAmounts[color], "You don't have a monopoly!");
		for (uint256 i = 0; i < array_length; i++)
			if (currentProgress > slots[sameColorArray[i]].progress)
				return false;
		return true;
	}

	/* function _buy_to(bool _house, uint256 _playerIndex, uint256 _amount) internal {
		if (_house == true)

	} */

	function _end_game() internal {

		for (uint256 i = 0; i < players.length; i++)
			getPlayer[players[i].wallet] = 0;
	}

	function _own(uint256 _playerIndex, uint256 _slot) internal {
		slots[_slot].owner = _playerIndex + 1;
		//players[_playerIndex].heritage[slots[_slot].color]++;
		players[_playerIndex].slotsOwned.push(players[_playerIndex].slot);
	}

	function random(uint256 _module) internal returns(uint256) {
		//TODO: get truly random number using chainlink
	}

}

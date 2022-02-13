// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CryptoPoker is Ownable {

	struct Player {
		uint256 balance;
		uint256 bet;
		uint256[2] hand; //hacer que para ver tus cartas tengas que firmar con la cartera (no puede ser un array de dos numeros sino un hash)
	}

	uint256 public lastTime = 0;
	uint256 public turnTime = 30 seconds;

	uint256 public potAmount = 0;
	uint256 public smallBlindAmount;
	uint256 public lastBidAmount;

	uint256 public dealerIndex = 0;
	uint256 public turnIndex = dealerIndex + 1;
	uint256 public roundIndex = 0; //preflop, flop, turn, river (0 -> 3)

	uint256 public currentPlayers;
	uint256[5] public tableCards;
	Player[6] public players;

	mapping(address => uint256) getPlayer;
	mapping(uint256 => address) getWallet;

	constructor (
		uint256 _smallBlindAmount
	) {
		smallBlindAmount = _smallBlindAmount;
	}

	function bet(uint256 _amount, uint256 _player) internal {

		require(players[_player].balance >= _amount, "Insufficient funds!");
		if (roundIndex == 0) {
			if (_player == dealerIndex + 1)
				require(_amount >= smallBlindAmount * 2, "Bid must be higher");
			else if (_player == dealerIndex + 2)
				require(_amount >= smallBlindAmount, "Bid must be higher");
		} else
			require(_amount >= lastBidAmount, "Bid must be higher");

		players[_player].bet += _amount;
		players[_player].balance -= _amount;
	}

	function run(uint256 _bidAmount) public {

		uint256 player = getPlayer[msg.sender];
		uint256 time = block.timestamp;

		if (player == dealerIndex + 1) {
			if (roundIndex == 0)
				give_cards();
			if (roundIndex == 1)
				flop(); //show 3 cards
			else if (roundIndex == 2)
				turn(); //show 1 card more
			else if (roundIndex == 3)
				river(); //show last card
		}

		require(player == turnIndex, "Wait to your turn!");

		if (lastTime > 0)
			_bidAmount += ((time - lastTime) / turnTime) * smallBlindAmount * 2;
		bet(_bidAmount, player);

		lastBidAmount = _bidAmount;
		lastTime = block.timestamp;
		turnIndex = (turnIndex + 1 >= currentPlayers) ? 0 : turnIndex + 1;
		if (turnIndex == dealerIndex + 1)
			roundIndex = (roundIndex < 3) ? roundIndex + 1 : 0;
	}

	function give_cards() internal {

	}

}

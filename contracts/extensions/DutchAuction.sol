// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '../interfaces/IJBDirectory.sol';
import '../libraries/JBConstants.sol';
import '../libraries/JBTokens.sol';
import '../structs/JBSplit.sol';

import './JBSplitPayerUtil.sol';

interface IDutchAuctionHouse {
  event CreateDutchAuction(address seller, IERC721 collection, uint256 item, uint256 startingPrice);

  event PlaceBid(address bidder, IERC721 collection, uint256 item, uint256 bidAmount);

  event ConcludeAuction(
    address seller,
    address bidder,
    IERC721 collection,
    uint256 item,
    uint256 closePrice
  );

  function create(
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    uint256 endingPrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits
  ) external;

  function bid(IERC721, uint256) external payable;

  function settle(IERC721 collection, uint256 item) external;

  function currentPrice(IERC721 collection, uint256 item) external view returns (uint256 price);
}

struct AuctionData {
  address seller;
  uint256 prices;
  uint256 bid;
  uint64 startTime;
}

contract DutchAuctionHouse is IDutchAuctionHouse, Ownable, ReentrancyGuard {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error AUCTION_EXISTS();
  error INVALID_AUCTION();
  error AUCTION_ENDED();
  error INVALID_BID();
  error INVALID_PRICE();

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
    @notice Collection of active auctions.
   */
  mapping(bytes32 => AuctionData) public auctions;

  /**
    @notice Jukebox splits for active auctions.
   */
  mapping(bytes32 => JBSplit[]) public auctionSplits;

  /**
    @notice Timestamp of contract deployment, used as auction expiration offset.
   */
  uint256 public deploymentOffset;

  uint256 public projectId;
  IJBPaymentTerminal public feeReceiver;
  uint256 public feeRate;
  IJBDirectory public directory;
  uint256 public periodDuration;

  /**
    @notice

    @param _projectId Project that manages this auction contract.
    @param _feeReceiver An instance of IJBPaymentTerminal which will get auction fees.
    @param _feeRate Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
    @param _periodDuration Number of seconds for each pricing period.
    @param _owner xxx
    @param _directory If splits are specified, a JBDirecotry instance is needed to distribute them.

    @dev feeReceiver addToBalanceOf will be called to send fees.
   */
  constructor(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) Ownable() {
    deploymentOffset = block.timestamp;

    projectId = _projectId;
    feeReceiver = _feeReceiver;
    feeRate = _feeRate;
    periodDuration = _periodDuration;
    directory = _directory;

    if (msg.sender != _owner) {
      transferOwnership(_owner);
    }
  }

  /**
    @notice Creates a new auction for an item from an ERC721 contract. This is a Dutch auction which begins at startingPrice and drops in equal increments to endingPrice by exipration. Price reduction happens at the interval specified in periodDuration. Number of periods is determined automatically and price decrement is the price difference over number of periods.

    @dev startingPrice and endingPrice must each fit into uint96.

    @dev WARNING, if using a JBSplits collection, make sure each of the splits is properly configured. The default project and default reciever during split processing is set to 0 and will therefore result in loss of funds if the split doesn't provide sufficient instructions.

    @param collection ERC721 contract.
    @param item Token id to list.
    @param startingPrice Starting price for the auction from which it will drop.
    @param endingPrice Minimum pride for the auction at which it will end at exipration time.
    @param expiration Seconds, offset from deploymentOffset, at which the auction concludes.
    @param saleSplits Jukebox splits collection that will receive auction proceeds.
   */
  function create(
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    uint256 endingPrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits
  ) external override nonReentrant {
    bytes32 auctionId = keccak256(abi.encodePacked(address(collection), item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller != address(0)) {
      revert AUCTION_EXISTS();
    }

    if (startingPrice > type(uint96).max) {
      revert INVALID_PRICE();
    }

    if (endingPrice > type(uint96).max || endingPrice >= startingPrice) {
      revert INVALID_PRICE();
    }

    uint256 auctionPrices = uint256(uint96(startingPrice));
    auctionPrices |= uint256(uint96(endingPrice)) << 96;
    auctionPrices |= uint256(uint64(expiration)) << 192;

    auctions[auctionId] = AuctionData(
      msg.sender,
      auctionPrices,
      0,
      uint64(block.timestamp - deploymentOffset)
    );

    uint256 length = saleSplits.length;
    for (uint256 i = 0; i < length; i += 1) {
      auctionSplits[auctionId].push(saleSplits[i]);
    }

    collection.transferFrom(msg.sender, address(this), item);

    emit CreateDutchAuction(msg.sender, collection, item, startingPrice);
  }

  /**
    @notice Places a bid on an existing auction. Refunds previous bid if needed. The contract will only store the highest bid. The bid can be below current price in anticipation of the auction eventually reaching that price. The bid must be at or above the end price.

    @param collection ERC721 contract.
    @param item Token id to bid on.
   */
  function bid(IERC721 collection, uint256 item) external payable override nonReentrant {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 expiration = uint256(uint64(auctionDetails.prices >> 192));

    if (block.timestamp > deploymentOffset + expiration) {
      revert AUCTION_ENDED();
    }

    if (auctionDetails.bid != 0) {
      uint256 currentBidAmount = uint96(auctionDetails.bid >> 160);
      if (currentBidAmount >= msg.value) {
        revert INVALID_BID();
      }

      payable(address(uint160(auctionDetails.bid))).transfer(currentBidAmount);
    } else {
      uint256 endingPrice = uint256(uint96(auctionDetails.prices >> 96));

      if (endingPrice > msg.value) {
        revert INVALID_BID();
      }
    }

    uint256 newBid = uint256(uint160(msg.sender));
    newBid |= uint256(uint96(msg.value)) << 160;

    auctions[auctionId].bid = newBid;

    emit PlaceBid(msg.sender, collection, item, msg.value);
  }

  /**
    @notice Settles the auction after expiration if no valid bids were received by sending the item back to the seller. If a valid bid matches the current price at the time of settle call, the item is sent to the bidder and the proceeds are distributed.

    @param collection ERC721 contract.
    @param item Token id to settle.
   */
  function settle(IERC721 collection, uint256 item) external override nonReentrant {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 lastBidAmount = uint256(uint96(auctionDetails.bid >> 160));
    uint256 minSettlePrice = currentPrice(collection, item);
    if (lastBidAmount >= minSettlePrice) {
      uint256 balance = lastBidAmount;
      uint256 fee = PRBMath.mulDiv(balance, feeRate, JBConstants.SPLITS_TOTAL_PERCENT);
      feeReceiver.addToBalanceOf(projectId, fee, JBTokens.ETH, '', '');

      unchecked {
        balance -= fee;
      }

      if (auctionSplits[auctionId].length > 0) {
        balance = JBSplitPayerUtil.payToSplits(
          auctionSplits[auctionId],
          balance,
          JBTokens.ETH,
          18,
          directory,
          0,
          payable(address(0))
        );
      } else {
        payable(address(uint160(auctionDetails.seller))).transfer(balance);
      }

      address buyer = address(uint160(auctionDetails.bid));

      collection.transferFrom(address(this), buyer, item);

      emit ConcludeAuction(auctionDetails.seller, buyer, collection, item, lastBidAmount);
    } else {
      collection.transferFrom(address(this), auctionDetails.seller, item);

      emit ConcludeAuction(auctionDetails.seller, address(0), collection, item, 0);
    }

    delete auctions[auctionId];
    delete auctionSplits[auctionId];
  }

  /**
    @notice Returns the current price for an items subject to the price range and elapsed duration.

    @param collection ERC721 contract.
    @param item Token id to get the price of.
   */
  function currentPrice(IERC721 collection, uint256 item)
    public
    view
    override
    returns (uint256 price)
  {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 endTime = uint256(uint64(auctionDetails.prices >> 192));
    uint256 periods = (endTime - auctionDetails.startTime) / periodDuration;
    uint256 startingPrice = uint256(uint96(auctionDetails.prices));
    uint256 endingPrice = uint256(uint96(auctionDetails.prices >> 96));
    uint256 periodPrice = (startingPrice - endingPrice) / periods;
    uint256 elapsedPeriods = (block.timestamp - deploymentOffset - auctionDetails.startTime) /
      periodDuration;
    price = startingPrice - elapsedPeriods * periodPrice;
  }

  // TODO: consider admin functions to modify feeSplits, etc
  // TODO: consider admin functions to recover eth & token balances
}

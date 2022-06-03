// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import 'hardhat/console.sol';
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

contract DutchAuctionHouse is IDutchAuctionHouse {
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
  mapping(bytes32 => AuctionData) public _auctions;

  /**
    @notice Jukebox splits for active auctions.
   */
  mapping(bytes32 => JBSplit[]) public _auctionSplits;

  /**
    @notice Timestamp of contract deployment, used as auction expiration offset.
   */
  uint256 public _deploymentOffset;

  JBSplit[] public _feeSplits;
  IJBDirectory public _directory;
  address payable public _feeReceiver;
  uint256 public _fee;
  uint256 public _periodDuration;

  /**
   @notice

   @param feeSplits Jukebox splits collection to which auction fees should be distributed.
   @param directory If splits are specified, a JBDirecotry instance is needed to distribute them.
   @param feeReceiver If feeSplits are not specified, this address will receive the fees from auctions.
   @param fee Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
   @param periodDuration Number of seconds for each pricing period.
   */
  constructor(
    JBSplit[] memory feeSplits,
    IJBDirectory directory,
    address payable feeReceiver,
    uint256 fee,
    uint256 periodDuration
  ) {
    _deploymentOffset = block.timestamp;

    uint256 length = feeSplits.length;
    for (uint256 i = 0; i < length; i += 1) {
      _feeSplits.push(feeSplits[i]);
    }

    _directory = directory;

    _feeReceiver = feeReceiver;
    _fee = fee;
    _periodDuration = periodDuration;
  }

  /**
    @notice Creates a new auction for an item from an ERC721 contract.

    @dev startingPrice and reservePrice must each fit into uint96.

    @param collection ERC721 contract.
    @param item Token id to list.
    @param startingPrice Minimum auction price. 0 is a valid price.
    @param endingPrice Reserve price at which the item will be sold once the auction expires. Below this price, the item will be returned to the seller.
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
  ) external override {
    bytes32 auctionId = keccak256(abi.encodePacked(address(collection), item));
    AuctionData memory auctionDetails = _auctions[auctionId];

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

    _auctions[auctionId] = AuctionData(
      msg.sender,
      auctionPrices,
      0,
      uint64(block.timestamp - _deploymentOffset)
    );

    uint256 length = saleSplits.length;
    for (uint256 i = 0; i < length; i += 1) {
      _auctionSplits[auctionId].push(saleSplits[i]);
    }

    collection.transferFrom(msg.sender, address(this), item);

    emit CreateDutchAuction(msg.sender, collection, item, startingPrice);
  }

  /**
    @notice Places a bid on an existing auction. Refunds previous bid if needed.

    @param collection ERC721 contract.
    @param item Token id to list.
   */
  function bid(IERC721 collection, uint256 item) external payable override {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = _auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 expiration = uint256(uint64(auctionDetails.prices >> 192));

    if (block.timestamp > _deploymentOffset + expiration) {
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

    _auctions[auctionId].bid = newBid;

    emit PlaceBid(msg.sender, collection, item, msg.value);
  }

  /**
    @notice Settles the auction after expiration by either sending the item to the winning bidder or sending it back to the seller in the event that no bids met the reserve price.

    @param collection ERC721 contract.
    @param item Token id to list.
   */
  function settle(IERC721 collection, uint256 item) external override {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = _auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 lastBidAmount = uint256(uint96(auctionDetails.bid >> 160));
    uint256 minSettlePrice = currentPrice(collection, item);
    if (lastBidAmount >= minSettlePrice) {
      uint256 balance = lastBidAmount;
      if (_feeSplits.length > 0) {
        balance = JBSplitPayerUtil.payToSplits(
          _feeSplits,
          lastBidAmount,
          JBTokens.ETH,
          18,
          _directory,
          0, // TODO: defaultProjectId
          _feeReceiver
        );
      } else {
        uint256 fee = PRBMath.mulDiv(balance, _fee, JBConstants.SPLITS_TOTAL_PERCENT);
        _feeReceiver.transfer(fee);
        unchecked {
          balance -= fee;
        }
      }

      if (_auctionSplits[auctionId].length > 0) {
        balance = JBSplitPayerUtil.payToSplits(
          _auctionSplits[auctionId],
          balance,
          JBTokens.ETH,
          18,
          _directory,
          0, // TODO: defaultProjectId
          _feeReceiver
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

    delete _auctions[auctionId];
    delete _auctionSplits[auctionId];
  }

  function currentPrice(IERC721 collection, uint256 item)
    public
    view
    override
    returns (uint256 price)
  {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = _auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 endTime = uint256(uint64(auctionDetails.prices >> 192));
    uint256 periods = (endTime - auctionDetails.startTime) / _periodDuration;
    uint256 startingPrice = uint256(uint96(auctionDetails.prices));
    uint256 endingPrice = uint256(uint96(auctionDetails.prices >> 96));
    uint256 periodPrice = (startingPrice - endingPrice) / periods;
    uint256 elapsedPeriods = (block.timestamp - _deploymentOffset - auctionDetails.startTime) /
      _periodDuration;
    price = startingPrice - elapsedPeriods * periodPrice;
  }

  // TODO: consider admin functions to modify feeSplits, etc
  // TODO: consider admin functions to recover eth & token balances
}

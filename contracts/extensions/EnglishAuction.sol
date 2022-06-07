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

interface IEnglishAuctionHouse {
  event CreateEnglishAuction(
    address seller,
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    string memo
  );

  event PlaceBid(address bidder, IERC721 collection, uint256 item, uint256 bidAmount, string memo);

  event ConcludeAuction(
    address seller,
    address bidder,
    IERC721 collection,
    uint256 item,
    uint256 closePrice,
    string memo
  );

  function create(
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    uint256 reservePrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits,
    string calldata _memo
  ) external;

  function bid(
    IERC721,
    uint256,
    string calldata _memo
  ) external payable;

  function settle(
    IERC721 collection,
    uint256 item,
    string calldata _memo
  ) external;

  function setFeeRate(uint256 _feeRate) external;

  function setFeeReceiver(IJBPaymentTerminal _feeReceiver) external;
}

struct AuctionData {
  address seller;
  uint256 prices;
  uint256 bid;
}

contract EnglishAuctionHouse is Ownable, IEnglishAuctionHouse, ReentrancyGuard {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error AUCTION_EXISTS();
  error INVALID_AUCTION();
  error AUCTION_IN_PROGRESS();
  error AUCTION_ENDED();
  error INVALID_BID();
  error INVALID_PRICE();
  error INVALID_FEERATE();

  /**
    @notice Fee rate cap set to 10%.
   */
  uint256 public constant feeRateCap = 100000000;

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

  uint256 public immutable projectId;
  IJBPaymentTerminal public feeReceiver;
  uint256 public feeRate;
  IJBDirectory public directory;

  /**
   @notice

   @param _projectId Project that manages this auction contract.
   @param _feeReceiver An instance of IJBPaymentTerminal which will get auction fees.
   @param _feeRate Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
   @param _owner Contract admin if, should be msg.sender or another address.
   @param _directory JBDirectory instance to enable JBX integration.

   @dev feeReceiver addToBalanceOf will be called to send fees.
   */
  constructor(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    address _owner,
    IJBDirectory _directory
  ) Ownable() {
    deploymentOffset = block.timestamp;

    projectId = _projectId;
    feeReceiver = _feeReceiver;
    feeRate = _feeRate;
    directory = _directory;

    if (msg.sender != _owner) {
      transferOwnership(_owner);
    }
  }

  /**
    @notice Creates a new auction for an item from an ERC721 contract.

    @dev startingPrice and reservePrice must each fit into uint96. expiration is 64 bit.

    @dev WARNING, if using a JBSplits collection, make sure each of the splits is properly configured. The default project and default reciever during split processing is set to 0 and will therefore result in loss of funds if the split doesn't provide sufficient instructions.

    @param collection ERC721 contract.
    @param item Token id to list.
    @param startingPrice Minimum auction price. 0 is a valid price.
    @param reservePrice Reserve price at which the item will be sold once the auction expires. Below this price, the item will be returned to the seller.
    @param expiration Seconds, offset from deploymentOffset, at which the auction concludes.
    @param saleSplits Jukebox splits collection that will receive auction proceeds.
   */
  function create(
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    uint256 reservePrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits,
    string calldata _memo
  ) external override nonReentrant {
    bytes32 auctionId = keccak256(abi.encodePacked(address(collection), item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller != address(0)) {
      revert AUCTION_EXISTS();
    }

    if (startingPrice > type(uint96).max) {
      revert INVALID_PRICE();
    }

    if (reservePrice > type(uint96).max) {
      revert INVALID_PRICE();
    }

    if (expiration > type(uint64).max) {
      revert INVALID_PRICE();
    }

    uint256 auctionPrices = uint256(uint96(startingPrice));
    auctionPrices |= uint256(uint96(reservePrice)) << 96;
    auctionPrices |= uint256(uint64(expiration)) << 192;

    auctions[auctionId] = AuctionData(msg.sender, auctionPrices, 0);

    uint256 length = saleSplits.length;
    for (uint256 i = 0; i < length; i += 1) {
      auctionSplits[auctionId].push(saleSplits[i]);
    }

    collection.transferFrom(msg.sender, address(this), item);

    emit CreateEnglishAuction(msg.sender, collection, item, startingPrice, _memo);
  }

  /**
    @notice Places a bid on an existing auction. Refunds previous bid if needed.

    @param collection ERC721 contract.
    @param item Token id to bid on.
   */
  function bid(
    IERC721 collection,
    uint256 item,
    string calldata _memo
  ) external payable override nonReentrant {
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
      uint256 startingPrice = uint256(uint96(auctionDetails.prices));

      if (startingPrice > msg.value) {
        revert INVALID_BID();
      }
    }

    uint256 newBid = uint256(uint160(msg.sender));
    newBid |= uint256(uint96(msg.value)) << 160;

    auctions[auctionId].bid = newBid;

    emit PlaceBid(msg.sender, collection, item, msg.value, _memo);
  }

  /**
    @notice Settles the auction after expiration by either sending the item to the winning bidder or sending it back to the seller in the event that no bids met the reserve price.

    @param collection ERC721 contract.
    @param item Token id to settle.
   */
  function settle(
    IERC721 collection,
    uint256 item,
    string calldata _memo
  ) external override nonReentrant {
    bytes32 auctionId = keccak256(abi.encodePacked(collection, item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.seller == address(0)) {
      revert INVALID_AUCTION();
    }

    uint256 expiration = uint256(uint64(auctionDetails.prices >> 192));
    if (block.timestamp < deploymentOffset + expiration) {
      revert AUCTION_IN_PROGRESS();
    }

    uint256 lastBidAmount = uint256(uint96(auctionDetails.bid >> 160));
    uint256 reservePrice = uint256(uint96(auctionDetails.prices >> 96));
    if (lastBidAmount >= reservePrice) {
      uint256 balance = lastBidAmount;
      uint256 fee = PRBMath.mulDiv(balance, feeRate, JBConstants.SPLITS_TOTAL_PERCENT);
      feeReceiver.addToBalanceOf(projectId, fee, JBTokens.ETH, _memo, '');

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
        payable(auctionDetails.seller).transfer(balance);
      }

      address buyer = address(uint160(auctionDetails.bid));

      collection.transferFrom(address(this), buyer, item);

      emit ConcludeAuction(auctionDetails.seller, buyer, collection, item, lastBidAmount, _memo);
    } else {
      collection.transferFrom(address(this), auctionDetails.seller, item);

      emit ConcludeAuction(auctionDetails.seller, address(0), collection, item, 0, _memo);
    }

    delete auctions[auctionId];
    delete auctionSplits[auctionId];
  }

  /**
    @notice Change fee rate, admin only.

    @param _feeRate Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
    */
  function setFeeRate(uint256 _feeRate) external override onlyOwner {
    if (_feeRate > feeRateCap) {
      revert INVALID_FEERATE();
    }

    feeRate = _feeRate;
  }

  /**
    @param _feeReceiver JBX terminal to send fees to.

    @dev addToBalanceOf on the feeReceiver will be called to send fees.
    */
  function setFeeReceiver(IJBPaymentTerminal _feeReceiver) external override onlyOwner {
    feeReceiver = _feeReceiver;
  }

  // TODO: consider admin functions to recover eth & token balances, pause?
}

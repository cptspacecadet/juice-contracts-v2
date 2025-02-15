// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '../interfaces/IJBDirectory.sol';
import '../libraries/JBConstants.sol';
import '../libraries/JBTokens.sol';
import '../structs/JBSplit.sol';

import './JBSplitPayerUtil.sol';

interface IDutchAuctionHouse {
  event CreateDutchAuction(
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
    uint256 endingPrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits,
    string calldata
  ) external;

  function bid(
    IERC721 collection,
    uint256 item,
    string calldata _memo
  ) external payable;

  function settle(
    IERC721 collection,
    uint256 item,
    string calldata _memo
  ) external;

  function currentPrice(IERC721 collection, uint256 item) external view returns (uint256 price);

  function setFeeRate(uint256) external;

  function setAllowPublicAuctions(bool) external;

  function setFeeReceiver(IJBPaymentTerminal) external;

  function addAuthorizedSeller(address) external;

  function removeAuthorizedSeller(address) external;
}

struct AuctionData {
  uint256 info; // seller, duration
  uint256 prices;
  uint256 bid;
}

contract DutchAuctionHouse is AccessControl, JBSplitPayerUtil, ReentrancyGuard, IDutchAuctionHouse {
  bytes32 public constant AUTHORIZED_SELLER_ROLE = keccak256('AUTHORIZED_SELLER_ROLE');
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error AUCTION_EXISTS();
  error INVALID_AUCTION();
  error AUCTION_ENDED();
  error INVALID_BID();
  error INVALID_PRICE();
  error INVALID_FEERATE();
  error NOT_AUTHORIZED();

  /**
    @notice Fee rate cap set to 10%.
   */
  uint256 public constant FEE_RATE_CAP = 100000000;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
    @notice Collection of active auctions.
   */
  mapping(bytes32 => AuctionData) public auctions;

  /**
    @notice Juicebox splits for active auctions.
   */
  mapping(bytes32 => JBSplit[]) public auctionSplits;

  /**
    @notice Timestamp of contract deployment, used as auction expiration offset.
   */
  uint256 public deploymentOffset;

  uint256 public immutable projectId;
  IJBPaymentTerminal public feeReceiver;
  IJBDirectory public directory;
  uint256 public settings; // periodDuration(64), allowPublicAuctions(bool), feeRate (32)

  /**
    @notice

    @param _projectId Project that manages this auction contract.
    @param _feeReceiver An instance of IJBPaymentTerminal which will get auction fees.
    @param _feeRate Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
    @param _periodDuration Number of seconds for each pricing period.
    @param _owner Contract admin if, should be msg.sender or another address.
    @param _directory JBDirectory instance to enable JBX integration.

    @dev feeReceiver addToBalanceOf will be called to send fees.
   */
  constructor(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) {
    deploymentOffset = block.timestamp;

    projectId = _projectId;
    feeReceiver = _feeReceiver;
    settings = setBoolean(_feeRate, 32, _allowPublicAuctions);
    settings |= uint256(uint64(_periodDuration)) << 33;
    directory = _directory;

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(AUTHORIZED_SELLER_ROLE, _owner);
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
    @param saleSplits Juicebox splits collection that will receive auction proceeds.
   */
  function create(
    IERC721 collection,
    uint256 item,
    uint256 startingPrice,
    uint256 endingPrice,
    uint256 expiration,
    JBSplit[] calldata saleSplits,
    string calldata _memo
  ) external override nonReentrant {
    if (!getBoolean(settings, 32) && !hasRole(AUTHORIZED_SELLER_ROLE, msg.sender)) {
      revert NOT_AUTHORIZED();
    }

    bytes32 auctionId = keccak256(abi.encodePacked(address(collection), item));
    AuctionData memory auctionDetails = auctions[auctionId];

    if (auctionDetails.info != 0) {
      revert AUCTION_EXISTS();
    }

    if (startingPrice > type(uint96).max) {
      revert INVALID_PRICE();
    }

    if (endingPrice > type(uint96).max || endingPrice >= startingPrice) {
      revert INVALID_PRICE();
    }

    {
      // scope to reduce stack depth
      uint256 auctionInfo = uint256(uint160(msg.sender));
      auctionInfo |= uint256(uint64(block.timestamp - deploymentOffset)) << 160;

      uint256 auctionPrices = uint256(uint96(startingPrice));
      auctionPrices |= uint256(uint96(endingPrice)) << 96;
      auctionPrices |= uint256(uint64(expiration)) << 192;

      auctions[auctionId] = AuctionData(auctionInfo, auctionPrices, 0);
    }

    uint256 length = saleSplits.length;
    for (uint256 i = 0; i < length; i += 1) {
      auctionSplits[auctionId].push(saleSplits[i]);
    }

    collection.transferFrom(msg.sender, address(this), item);

    emit CreateDutchAuction(msg.sender, collection, item, startingPrice, _memo);
  }

  /**
    @notice Places a bid on an existing auction. Refunds previous bid if needed. The contract will only store the highest bid. The bid can be below current price in anticipation of the auction eventually reaching that price. The bid must be at or above the end price.

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

    if (auctionDetails.info == 0) {
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

    emit PlaceBid(msg.sender, collection, item, msg.value, _memo);
  }

  /**
    @notice Settles the auction after expiration if no valid bids were received by sending the item back to the seller. If a valid bid matches the current price at the time of settle call, the item is sent to the bidder and the proceeds are distributed.

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

    if (auctionDetails.info == 0) {
      revert INVALID_AUCTION();
    }

    uint256 lastBidAmount = uint256(uint96(auctionDetails.bid >> 160));
    uint256 minSettlePrice = currentPrice(collection, item);

    if (lastBidAmount < minSettlePrice) {
      collection.transferFrom(address(this), address(uint160(auctionDetails.info)), item);

      emit ConcludeAuction(
        address(uint160(auctionDetails.info)),
        address(0),
        collection,
        item,
        0,
        _memo
      );

      delete auctions[auctionId];
      delete auctionSplits[auctionId];

      return;
    }

    uint256 balance = lastBidAmount;
    uint256 fee = PRBMath.mulDiv(balance, uint32(settings), JBConstants.SPLITS_TOTAL_PERCENT);
    feeReceiver.addToBalanceOf{value: fee}(projectId, fee, JBTokens.ETH, _memo, '');

    unchecked {
      balance -= fee;
    }

    if (auctionSplits[auctionId].length > 0) {
      balance = payToSplits(
        auctionSplits[auctionId],
        balance,
        JBTokens.ETH,
        18,
        directory,
        0,
        payable(address(0))
      );
    } else {
      payable(address(uint160(auctionDetails.info))).transfer(balance);
    }

    address buyer = address(uint160(auctionDetails.bid));

    collection.transferFrom(address(this), buyer, item);

    emit ConcludeAuction(
      address(uint160(auctionDetails.info)),
      buyer,
      collection,
      item,
      lastBidAmount,
      _memo
    );
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

    if (auctionDetails.info == 0) {
      revert INVALID_AUCTION();
    }

    uint256 endTime = uint256(uint64(auctionDetails.prices >> 192));
    uint256 startTime = uint256(uint64(auctionDetails.info >> 160));
    uint256 periods = (endTime - startTime) / uint64(uint256(settings) >> 33);
    uint256 startingPrice = uint256(uint96(auctionDetails.prices));
    uint256 endingPrice = uint256(uint96(auctionDetails.prices >> 96));
    uint256 periodPrice = (startingPrice - endingPrice) / periods;
    uint256 elapsedPeriods = (block.timestamp - deploymentOffset - startTime) /
      uint64(uint256(settings) >> 33);
    price = startingPrice - elapsedPeriods * periodPrice;
  }

  /**
    @notice Change fee rate, admin only.

    @param _feeRate Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
    */
  function setFeeRate(uint256 _feeRate) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_feeRate > FEE_RATE_CAP) {
      revert INVALID_FEERATE();
    }

    settings |= uint256(uint32(_feeRate));
  }

  /**
    @param _allowPublicAuctions Sets or clears the flag to enable users other than admin role to create auctions.

    */
  function setAllowPublicAuctions(bool _allowPublicAuctions)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    settings = setBoolean(settings, 32, _allowPublicAuctions);
  }

  /**
    @param _feeReceiver JBX terminal to send fees to.

    @dev addToBalanceOf on the feeReceiver will be called to send fees.
    */
  function setFeeReceiver(IJBPaymentTerminal _feeReceiver)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    feeReceiver = _feeReceiver;
  }

  function addAuthorizedSeller(address _seller) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _grantRole(AUTHORIZED_SELLER_ROLE, _seller);
  }

  function removeAuthorizedSeller(address _seller) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _revokeRole(AUTHORIZED_SELLER_ROLE, _seller);
  }

  // TODO: consider admin functions to recover eth & token balances

  //*********************************************************************//
  // ------------------------------ utils ------------------------------ //
  //*********************************************************************//

  function getBoolean(uint256 _source, uint256 _index) internal pure returns (bool) {
    uint256 flag = (_source >> _index) & uint256(1);
    return (flag == 1 ? true : false);
  }

  function setBoolean(
    uint256 _source,
    uint256 _index,
    bool _value
  ) internal pure returns (uint256 update) {
    if (_value) {
      update = _source | (uint256(1) << _index);
    } else {
      update = _source & ~(uint256(1) << _index);
    }
  }
}

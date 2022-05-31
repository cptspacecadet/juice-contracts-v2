// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import {ERC721 as ERC721Rari} from '@rari-capital/solmate/src/tokens/ERC721.sol';

import '../interfaces/IJBDirectory.sol';
import '../interfaces/IJBFundingCycleDataSource.sol';
import '../interfaces/IJBPayDelegate.sol';
import '../interfaces/IJBRedemptionDelegate.sol';
import '../interfaces/extensions/INFTRewardDataSourceDelegate.sol';
import '../interfaces/extensions/IToken721UriResolver.sol';

import '../structs/JBDidPayData.sol';
import '../structs/JBDidRedeemData.sol';
import '../structs/JBRedeemParamsData.sol';
import '../structs/JBTokenAmount.sol';

/**
  @title Jukebox data source delegate that offers project contributors NFTs.

  @notice This contract allows project creators to reward contributors with NFTs. Intended use is to incentivize initial project support by minting a limited number of NFTs to the first N contributors.

  @dev Keep in mind that this PayDelegate and RedeemDelegate implementation will simply pass through the weight and reclaimAmount it is called with.
 */
contract NFTRewardDataSourceDelegate is
  ERC721Rari,
  Ownable,
  INFTRewardDataSourceDelegate,
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate
{
  using Strings for uint256;

  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PAYMENT_EVENT();
  error INCORRECT_OWNER();
  error INVALID_ADDRESS();
  error INVALID_TOKEN();
  error SUPPLY_EXHAUSTED();

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @notice
    Project id of the project this configuration is associated with.
  */
  uint256 private _projectId;

  /**
    @notice
    Parent controller.
  */
  IJBDirectory private _directory;

  /**
    @notice Minimum contribution amount to trigger NFT distribution, denominated in some currency defined as part of this object.

    @dev Only one NFT will be minted for any amount at or above this value.
  */
  JBTokenAmount private _minContribution;

  /**
    @notice
    NFT mint cap as part of this configuration.
  */
  uint256 private _maxSupply;

  /**
    @notice Current supply.

    @dev Also used to check if rewards supply was exhausted and as nextTokenId
  */
  uint256 private _supply;

  /**
    @notice
    Token base uri.
  */
  string private _baseUri;

  /**
    @notice
    Custom token uri resolver, superceeds base uri.
  */
  IToken721UriResolver private _tokenUriResolver;

  /**
    @notice
    Contract opensea-style metadata uri.
  */
  string private _contractUri;

  /**
    @param projectId JBX project id this reward is associated with.
    @param directory JBX directory.
    @param maxSupply Total number of reward tokens to distribute.
    @param minContribution Minimum contribution amount to be eligible for this reward.
    @param _name The name of the token.
    @param _symbol The symbol that the token should be represented by.
    @param _uri Token base URI.
    @param _tokenUriResolverAddress Custom uri resolver.
    @param _contractMetadataUri Contract metadata uri.
    @param _admin Set an alternate owner.
  */
  constructor(
    uint256 projectId,
    IJBDirectory directory,
    uint256 maxSupply,
    JBTokenAmount memory minContribution,
    string memory _name,
    string memory _symbol,
    string memory _uri,
    IToken721UriResolver _tokenUriResolverAddress,
    string memory _contractMetadataUri,
    address _admin
  ) ERC721Rari(_name, _symbol) {
    // JBX
    _projectId = projectId;
    _directory = directory;
    _maxSupply = maxSupply;
    _minContribution = minContribution;

    // ERC721
    _baseUri = _uri;
    _tokenUriResolver = _tokenUriResolverAddress;
    _contractUri = _contractMetadataUri;

    if (_admin != address(0)) {
      _transferOwnership(_admin);
    }
  }

  //*********************************************************************//
  // ------------------- IJBFundingCycleDataSource --------------------- //
  //*********************************************************************//

  function payParams(JBPayParamsData calldata _data)
    external
    view
    override
    returns (
      uint256 weight,
      string memory memo,
      IJBPayDelegate delegate
    )
  {
    return (_data.weight, _data.memo, IJBPayDelegate(address(this)));
  }

  function redeemParams(JBRedeemParamsData calldata _data)
    external
    pure
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      IJBRedemptionDelegate delegate
    )
  {
    return (_data.reclaimAmount.value, _data.memo, IJBRedemptionDelegate(address(0)));
  }

  //*********************************************************************//
  // ------------------------ IJBPayDelegate --------------------------- //
  //*********************************************************************//

  function didPay(JBDidPayData calldata _data) external override {
    if (!_directory.isTerminalOf(_projectId, IJBPaymentTerminal(msg.sender))) {
      revert INVALID_PAYMENT_EVENT();
    }

    if (_supply == _maxSupply) {
      return;
    }

    if (
      _data.amount.value >= _minContribution.value &&
      _data.amount.currency == _minContribution.currency
    ) {
      uint256 tokenId = _supply;
      _mint(_data.beneficiary, tokenId);

      _supply += 1;
    }
  }

  //*********************************************************************//
  // -------------------- IJBRedemptionDelegate ------------------------ //
  //*********************************************************************//

  /**
  @notice NFT redemption is not supported.
   */
  // solhint-disable-next-line
  function didRedeem(JBDidRedeemData calldata _data) external override {
    // not a supported workflow for NFTs
  }

  //*********************************************************************//
  // ---------------------------- IERC165 ------------------------------ //
  //*********************************************************************//

  function supportsInterface(bytes4 _interfaceId)
    public
    view
    override(ERC721Rari, IERC165)
    returns (bool)
  {
    return
      _interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
      _interfaceId == type(IJBPayDelegate).interfaceId ||
      _interfaceId == type(IJBRedemptionDelegate).interfaceId ||
      super.supportsInterface(_interfaceId); // check with rari-ERC721
  }

  //*********************************************************************//
  // ----------------------------- ERC721 ------------------------------ //
  //*********************************************************************//

  /**
    @notice
    The total supply of this ERC721.

    ignored: _projectId the ID of the project to which the token belongs. This is ignored.

    @return The total supply of this ERC721, as a fixed point number.
  */
  function totalSupply(uint256) external view override returns (uint256) {
    return _supply;
  }

  /**
    @notice
    Returns the full URI for the asset.
  */
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    if (_ownerOf[tokenId] == address(0)) {
      revert INVALID_TOKEN();
    }

    if (address(_tokenUriResolver) != address(0)) {
      return _tokenUriResolver.tokenURI(tokenId);
    }

    return bytes(_baseUri).length > 0 ? string(abi.encodePacked(_baseUri, tokenId.toString())) : '';
  }

  /**
    @notice
    Returns the contract metadata uri.
  */
  function contractURI() public view override returns (string memory contractUri) {
    contractUri = _contractUri;
  }

  /**
    @notice
    Approves an account to spend tokens on the `msg.sender`s behalf.

    ignored: _projectId the ID of the project to which the token belongs. This is ignored.
    @param _spender The address that will be spending tokens on the `msg.sender`s behalf.
    @param _id NFT id to approve.
  */
  function approve(
    uint256,
    address _spender,
    uint256 _id
  ) external override {
    approve(_spender, _id);
  }

  /**
    @notice
    Transfer tokens to an account.

    ignored: _projectId The ID of the project to which the token belongs. This is ignored.
    @param _to The destination address.
    @param _id NFT id to transfer.
  */
  function transfer(
    uint256,
    address _to,
    uint256 _id
  ) external override {
    transferFrom(msg.sender, _to, _id);
  }

  /**
    @notice
    Transfer tokens between accounts.

    ignored: _projectId The ID of the project to which the token belongs. This is ignored.
    @param _from The originating address.
    @param _to The destination address.
    @param _id The amount of the transfer, as a fixed point number with 18 decimals.
  */
  function transferFrom(
    uint256,
    address _from,
    address _to,
    uint256 _id
  ) external override {
    transferFrom(_from, _to, _id);
  }

  /**
    @notice
    Returns the number of tokens held by the given address.
   */
  function ownerBalance(address _account) external view override returns (uint256) {
    if (_account == address(0)) {
      revert INVALID_ADDRESS();
    }

    return _balanceOf[_account];
  }

  /**
    @notice
    Confirms that the given address owns the provided token.
   */
  function isOwner(address _account, uint256 _id) external view override returns (bool) {
    return _ownerOf[_id] == _account;
  }

  function mint(address _account) external override onlyOwner returns (uint256 tokenId) {
    if (_supply == _maxSupply) {
      revert SUPPLY_EXHAUSTED();
    }

    tokenId = _supply;
    _mint(_account, tokenId);

    _supply += 1;
  }

  /**
    @notice
    Owner-only function to set a contract metadata uri to contain opensea-style metadata.

    @param _contractMetadataUri New metadata uri.
  */
  function setContractUri(string calldata _contractMetadataUri) external override onlyOwner {
    _contractUri = _contractMetadataUri;
  }

  /**
    @notice
    Owner-only function to set a new token base uri.

    @param _uri New base uri.
  */
  function setTokenUri(string calldata _uri) external override onlyOwner {
    _baseUri = _uri;
  }

  /**
    @notice
    Owner-only function to set a token uri resolver. If set to address(0), value of baseUri will be used instead.

    @param _tokenUriResolverAddress New uri resolver contract.
  */
  function setTokenUriResolver(IToken721UriResolver _tokenUriResolverAddress)
    external
    override
    onlyOwner
  {
    _tokenUriResolver = _tokenUriResolverAddress;
  }
}

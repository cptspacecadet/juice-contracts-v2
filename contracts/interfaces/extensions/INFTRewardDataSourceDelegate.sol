// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './IToken721UriResolver.sol';
import './ITokenSupplyDetails.sol';

interface INFTRewardDataSourceDelegate is ITokenSupplyDetails {
  function approve(
    uint256,
    address _spender,
    uint256 _id
  ) external;

  function transfer(
    uint256 _projectId,
    address _to,
    uint256 _id
  ) external;

  function transferFrom(
    uint256 _projectId,
    address _from,
    address _to,
    uint256 _id
  ) external;

  function mint(address) external returns (uint256);

  function isOwner(address _account, uint256 _id) external view returns (bool);

  function contractURI() external view returns (string memory);

  function setContractUri(string calldata _contractMetadataUri) external;

  function setTokenUri(string calldata _uri) external;

  function setTokenUriResolver(IToken721UriResolver _tokenUriResolverAddress) external;
}

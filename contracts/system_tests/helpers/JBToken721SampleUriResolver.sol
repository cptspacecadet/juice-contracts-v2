// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '../../interfaces/extensions/IToken721UriResolver.sol';

/**
  @notice Sample implementation of IToken721UriResolver for tests.
 */
contract JBToken721SampleUriResolver is IToken721UriResolver {
  string public baseUri;

  constructor(string memory _uri) {
    baseUri = _uri;
  }

  function tokenURI(uint256) external view override returns (string memory uri) {
    uri = baseUri;
  }
}

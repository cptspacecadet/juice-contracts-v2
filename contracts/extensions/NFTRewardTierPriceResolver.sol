// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '../structs/JBTokenAmount.sol';
import '../interfaces/extensions/ITokenSupplyDetails.sol';

struct RewardTier {
  uint256 rangeFloor;
  // uint256 idOffset;
  uint256 tierAllowance;
}

contract NFTRewardTieredPriceResolver {
  address public contributionToken;
  uint256 public globalMintAllowance;
  uint256 public userMintCap;
  RewardTier[] public tiers;

  /**
    @notice blah

    @dev Tiers list must be sorted by floor otherwise contributors won't be rewarded properly.

    @param _contributionToken blah
    @param _mintCap blah
    @param _tiers blah
   */
  constructor(
    address _contributionToken,
    uint256 _mintCap,
    RewardTier[] memory _tiers
  ) {
    contributionToken = _contributionToken;
    globalMintAllowance = _mintCap;

    for (uint256 i; i < _tiers.length; i++) {
      tiers.push(_tiers[i]);
    }
  }

  /**
    @notice blah

    @dev blah

    @param account blah
    @param contribution blah
    @param token Reward token to be issued as a reward, used to read token data only.
   */
  function validateContribution(
    address account,
    JBTokenAmount calldata contribution,
    ITokenSupplyDetails token
  ) public returns (uint256 tokenId) {
    if (contribution.token != contributionToken) {
      return 0;
    }

    if (globalMintAllowance == 0) {
      return 0;
    }

    if (token.totalOwnerBalance(account) >= userMintCap) {
      return 0;
    }

    tokenId = 0;
    for (uint256 i; i < tiers.length - 1; i++) {
      if (
        tiers[i].rangeFloor <= contribution.value &&
        i == tiers.length - 1 &&
        tiers[i].tierAllowance > 0
      ) {
        tokenId = tiers[i].idOffset + tiers[i].tierAllowance;
        unchecked {
          --tiers[i].tierAllowance;
          --globalMintAllowance;
        }
        break;
      } else if (
        tiers[i].rangeFloor <= contribution.value &&
        tiers[i + 1].rangeFloor > contribution.value &&
        tiers[i].tierAllowance > 0
      ) {
        tokenId = tiers[i].idOffset + tiers[i].tierAllowance;
        unchecked {
          --tiers[i].tierAllowance;
          --globalMintAllowance;
        }
        break;
      }
    }
  }
}
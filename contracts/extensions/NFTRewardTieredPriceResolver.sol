// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '../structs/JBTokenAmount.sol';
import '../interfaces/extensions/IPriceResolver.sol';
import '../interfaces/extensions/ITokenSupplyDetails.sol';

struct RewardTier {
  uint256 contributionFloor;
  uint256 idCeiling;
  uint256 remainingAllowance;
}

contract NFTRewardTieredPriceResolver is IPriceResolver {
  address public contributionToken;
  uint256 public globalMintAllowance;
  uint256 public userMintCap;
  RewardTier[] public tiers;

  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PRICE_SORT_ORDER(uint256);
  error INVALID_ID_SORT_ORDER(uint256);

  /**
    @notice blah

    @dev Tiers list must be sorted by floor otherwise contributors won't be rewarded properly.

    @param _contributionToken blah
    @param _mintCap blah
    @param _userMintCap blah
    @param _tiers blah
   */
  constructor(
    address _contributionToken,
    uint256 _mintCap,
    uint256 _userMintCap,
    RewardTier[] memory _tiers
  ) {
    contributionToken = _contributionToken;
    globalMintAllowance = _mintCap;
    userMintCap = _userMintCap;

    if (_tiers.length > 0) {
      tiers.push(_tiers[0]);
      for (uint256 i = 1; i < _tiers.length; i++) {
        if (_tiers[i].contributionFloor < _tiers[i - 1].contributionFloor) {
          revert INVALID_PRICE_SORT_ORDER(i);
        }

        if (_tiers[i].idCeiling - _tiers[i].remainingAllowance < _tiers[i - 1].idCeiling) {
          revert INVALID_ID_SORT_ORDER(i);
        }

        tiers.push(_tiers[i]);
      }
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
  ) public override returns (uint256 tokenId) {
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
    for (uint256 i; i < tiers.length; i++) {
      if (
        tiers[i].contributionFloor <= contribution.value &&
        i == tiers.length - 1 &&
        tiers[i].remainingAllowance > 0
      ) {
        tokenId = tiers[i].idCeiling - tiers[i].remainingAllowance;
        unchecked {
          --tiers[i].remainingAllowance;
          --globalMintAllowance;
        }
        break;
      } else if (
        tiers[i].contributionFloor <= contribution.value &&
        tiers[i + 1].contributionFloor > contribution.value &&
        tiers[i].remainingAllowance > 0
      ) {
        tokenId = tiers[i].idCeiling - tiers[i].remainingAllowance;
        unchecked {
          --tiers[i].remainingAllowance;
          --globalMintAllowance;
        }
        break;
      }
    }
  }
}

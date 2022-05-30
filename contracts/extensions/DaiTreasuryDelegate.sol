// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '../interfaces/IJBAllowanceTerminal.sol';
import '../interfaces/IJBController.sol';
import '../interfaces/IJBFundingCycleDataSource.sol';
import '../interfaces/IJBPayDelegate.sol';
import '../interfaces/IJBPaymentTerminal.sol';
import '../interfaces/IJBRedemptionDelegate.sol';
import '../libraries/JBCurrencies.sol';
import '../libraries/JBTokens.sol';

import '../structs/JBDidPayData.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

interface IWETH9 is IERC20 {
  /// @notice Deposit ether to get wrapped ether
  function deposit() external payable;

  /// @notice Withdraw wrapped ether to get ether
  function withdraw(uint256) external;
}

interface IDaiTreasuryDelegate {
  receive() external payable;
}

/**
  @title Automated DAI treasury

  @notice Converts ether sent to it into WETH and swaps it for DAI, then mints a token balance to the sender for the amount of DAI that it received. The redeem workflow will burn these tokens and return ether to the sender.

  @notice Intended usecase is for other projects to use a SplitPayer to send some portion of their deposits here as a diversification strategy instead of holding all contributions as ether.

  @dev This contract will mint & burn share tokens via JBController. Tokens are issued and burned 1:1 to the amount of underlying token, in this case DAI. As an example, if 1 ether is sent into didPay, it will be wrapped into WETH and swapped for DAI. If WETH/DAI rate is 2000, the caller will get 2000 tokens.

  @dev This contract will own the DAI balance until it's redeemed back into ether and sent out.
 */
contract DaiTreasuryDelegate is
  IDaiTreasuryDelegate,
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IUniswapV3SwapCallback
{
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error Callback_unauth();

  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  /**
    @notice JBController reference to directly manage project token balances.
   */
  IJBController private immutable _jbxController;

  /**
    @notice Balance token, in this case DAI, that is held by the delegate on behalf of depositors.
   */
  IERC20Metadata private constant _balanceToken =
    IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI

  /**
    @notice Uniswap v3 pool to use for swaps.
   */
  IUniswapV3Pool private constant _tokenPool =
    IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8); // TODO: this should be abstracted into a SwapProvider that can offer interfaces other than just uniswap

  /**
    @notice Hardwired WETH address for use as "cash" in the swaps.
   */
  IWETH9 private constant _weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  /**
    @notice Default direction for use with IUniswapV3Pool.swap as zeroForOne intended for ether (WETH) swaps into _balanceToken.

    @dev For DAI/WETH pool at 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8 default direction, WETH -> DAI is `false`.
   */
  bool private immutable _defaultDirection;

  constructor(IJBController jbxController) {
    _jbxController = jbxController;
    _defaultDirection = address(_weth) < address(_balanceToken);
  }

  //*********************************************************************//
  // ---------------------- external functions ------------------------- //
  //*********************************************************************//

  /**
    @notice IJBPayDelegate implementation

    @notice Will swap incoming ether via WETH into DAI using Uniswap v3 and mint project tokens via JBController in the same amount as the DAI received from the swap so it can be later redeemed 1:1. It's expected to be called by a terminal of a different project looking to diversify some ether holdings into DAI.

    @dev The function is expected to be able to pull an allowance from the calling terminal for the amount in _data.amount.
   */
  function didPay(JBDidPayData calldata _data) public override {
    (IJBAllowanceTerminal(msg.sender)).useAllowanceOf(
      _data.projectId,
      _data.amount.value,
      JBCurrencies.ETH,
      address(0),
      _data.amount.value,
      payable(this),
      _data.memo
    );

    (int256 amount0, int256 amount1) = _tokenPool.swap(
      address(this),
      _defaultDirection,
      int256(_data.amount.value),
      0,
      ''
    );

    _jbxController.mintTokensOf(
      _data.projectId,
      _defaultDirection ? uint256(amount1) : uint256(amount0),
      msg.sender,
      '',
      false, // _preferClaimedTokens,
      false // _useReservedRate
    );
  }

  /**
    @notice IJBRedemptionDelegate implementation

    @notice This function will swap the a portion of the owned DAI balance in the same amount as _data.amount, convert the resulting WETH into ether and send it back to the caller.

    @dev _data.amount will be validated against the project token. _data.amount will be burned from the caller via JBController.
   */
  function didRedeem(JBDidRedeemData calldata _data) public override {
    _jbxController.burnTokensOf(
      msg.sender,
      _data.projectId,
      _data.projectTokenCount,
      _data.memo,
      false //preferClaimedTokens
    );

    (int256 amount0, int256 amount1) = _tokenPool.swap(
      address(this),
      !_defaultDirection,
      int256(_data.projectTokenCount),
      0,
      ''
    );

    _weth.withdraw(_defaultDirection ? uint256(amount0) : uint256(amount1));

    (IJBPaymentTerminal(msg.sender)).addToBalanceOf(
      _data.projectId,
      _defaultDirection ? uint256(amount0) : uint256(amount1),
      JBTokens.ETH,
      _data.memo,
      _data.metadata
    );
  }

  /**
    @notice IJBFundingCycleDataSource implementation

    @dev This function returns 0 weight because didPay will mint tokens via JBController. The reason for this is that weight is used as a multiplier in JBTerminal.pay and the token amount minted needs to match the exact DAI balance received from the swap.
    */
  function payParams(JBPayParamsData calldata _data)
    public
    view
    override
    returns (
      uint256 weight,
      string memory memo,
      IJBPayDelegate delegate
    )
  {
    return (0, _data.memo, IJBPayDelegate(address(this)));
  }

  /**
    @notice IJBFundingCycleDataSource implementation

    @dev This function returns 0 weight because JBTerminal.redeemTokensOf uses it as a multiplier, but we need to burn the exact amount of tokens being redeemed via a swap from DAI back into ether. didRedeem will perform the burn.
   */
  function redeemParams(JBRedeemParamsData calldata _data)
    public
    view
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      IJBRedemptionDelegate delegate
    )
  {
    return (0, _data.memo, IJBRedemptionDelegate(address(this)));
  }

  /**
    @notice IUniswapV3SwapCallback implementation

    @notice This method will fund the swap.
   */
  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata
  ) external override {
    if (msg.sender != address(_tokenPool)) revert Callback_unauth();

    if (amount0Delta < 0 && _defaultDirection) {
      // deposit
      _weth.deposit{value: uint256(amount0Delta)}();

      _weth.transfer(address(_tokenPool), uint256(amount0Delta)); // _weth == _tokenPool.token0
    } else if (amount1Delta < 0 && !_defaultDirection) {
      // deposit
      _weth.deposit{value: uint256(amount0Delta)}();

      _weth.transfer(address(_tokenPool), uint256(amount1Delta)); // _weth == _tokenPool.token1
    } else if (amount0Delta < 0) {
      // redeem
      IERC20Metadata(_balanceToken).transfer(address(_tokenPool), uint256(amount0Delta));
    } else if (amount1Delta < 0) {
      // redeem
      IERC20Metadata(_balanceToken).transfer(address(_tokenPool), uint256(amount1Delta));
    }
  }

  /**
    @notice IERC165 implementation
   */
  function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
    return
      interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
      interfaceId == type(IJBPayDelegate).interfaceId ||
      interfaceId == type(IJBRedemptionDelegate).interfaceId ||
      interfaceId == type(IUniswapV3SwapCallback).interfaceId;
  }

  /**
    @dev didPay() receives ether from the terminal to wrap & send to the pool.
  */
  // solhint-disable-next-line no-empty-blocks
  receive() external payable override {}
}

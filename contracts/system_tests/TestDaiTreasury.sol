// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './helpers/TestBaseWorkflow.sol';

import '../interfaces/IJBController.sol';
import '../interfaces/IJBFundingCycleStore.sol';
import '../interfaces/IJBFundingCycleDataSource.sol';
import '../interfaces/IJBOperatable.sol';
import '../interfaces/IJBPayDelegate.sol';
import '../interfaces/IJBReconfigurationBufferBallot.sol';
import '../interfaces/IJBRedemptionDelegate.sol';
import '../interfaces/IJBPayoutRedemptionPaymentTerminal.sol';
import '../interfaces/IJBSingleTokenPaymentTerminalStore.sol';
import '../interfaces/IJBToken.sol';
import '../libraries/JBConstants.sol';
import '../libraries/JBCurrencies.sol';
import '../libraries/JBFundingCycleMetadataResolver.sol';
import '../libraries/JBOperations.sol';
import '../libraries/JBTokens.sol';
import '../JBTokenStore.sol';
import '../structs/JBFundingCycle.sol';

import '../extensions/DaiTreasuryDelegate.sol';

import '@paulrberg/contracts/math/PRBMath.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import 'hardhat/console.sol';

contract TestDaiTreasury is TestBaseWorkflow {
  JBController controller;
  JBTokenStore tokenStore;
  IJBPayoutRedemptionPaymentTerminal treasuryTerminal;
  DaiTreasuryDelegate daiTreasury;
  uint256 projectId;
  IJBToken treasuryToken;
  address contributorAccount = address(0x9cec118945e3430047aCbCCaAd717545d93C0DE8);

  JBProjectMetadata _projectMetadata;
  JBFundingCycleData _data;
  JBFundingCycleMetadata _metadata;
  IJBPaymentTerminal[] _terminals;
  JBGroupedSplits[] _groupedSplits;
  JBFundAccessConstraints[] _fundAccessConstraints;

  function setUp() public override {
    super.setUp();

    controller = jbController();
    treasuryTerminal = jbETHPaymentTerminal();
    tokenStore = jbTokenStore();

    daiTreasury = new DaiTreasuryDelegate(controller);

    _projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    _data = JBFundingCycleData({
      duration: 6 days,
      weight: 10000 * 10**18,
      discountRate: 0,
      ballot: IJBReconfigurationBufferBallot(address(0))
    });

    _metadata = JBFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false}),
      reservedRate: 10000,
      redemptionRate: 5000,
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: true,
      allowChangeToken: false,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForPay: true,
      useDataSourceForRedeem: true,
      dataSource: address(daiTreasury)
    });

    _fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: jbETHPaymentTerminal(),
        token: jbLibraries().ETHToken(),
        distributionLimit: 0,
        overflowAllowance: type(uint232).max,
        distributionLimitCurrency: 1, // Currency = ETH
        overflowAllowanceCurrency: 1
      })
    );

    uint256[] memory permissionIndex = new uint256[](1);
    permissionIndex[0] = JBOperations.USE_ALLOWANCE;

    evm.prank(multisig());
    jbOperatorStore().setOperator(
      JBOperatorData({
        operator: address(daiTreasury),
        domain: 1,
        permissionIndexes: permissionIndex
      })
    );

    evm.prank(multisig());
    jbETHPaymentTerminal().setFeelessAddress(address(daiTreasury), true);

    _terminals = [treasuryTerminal];

    evm.prank(multisig());
    projectId = controller.launchProjectFor(
      multisig(),
      _projectMetadata,
      _data,
      _metadata,
      0, // Start asap
      _groupedSplits,
      _fundAccessConstraints,
      _terminals,
      ''
    );

    evm.prank(multisig());
    treasuryToken = controller.issueTokenFor(projectId, 'DAI Share', 'DST');
  }

  function testTerminalContributionCycle() public {
    evm.prank(contributorAccount);
    treasuryTerminal.pay{value: 1 ether}(
      projectId,
      1 ether,
      address(0),
      contributorAccount,
      0,
      false,
      'hedge my money!',
      new bytes(0)
    );

    uint256 minted = tokenStore.balanceOf(contributorAccount, projectId);
    console.log('minted', minted);

    evm.prank(contributorAccount);
    treasuryTerminal.redeemTokensOf(
      contributorAccount,
      projectId,
      minted,
      address(treasuryToken),
      0,
      payable(address(this)),
      'return my money!',
      new bytes(0)
    );

    minted = tokenStore.balanceOf(contributorAccount, projectId);
    console.log('remaining', minted);
  }
}

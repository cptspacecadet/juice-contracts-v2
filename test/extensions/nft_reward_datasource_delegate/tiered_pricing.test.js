import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';

describe('NFTRewardDataSourceDelegate::didPay(...)', function () {
  const PROJECT_ID = 2;
  const NFT_NAME = 'Reward NFT';
  const NFT_SYMBOL = 'RN';
  const NFT_URI = 'ipfs://content_base';
  const NFT_METADATA = 'ipfs://metadata';
  const CURRENCY_ETH = '0x000000000000000000000000000000000000EEEe'; // JBCurrencies.ETH
  const halfEth = ethers.utils.parseEther('0.5');
  const tier1Floor = ethers.utils.parseEther('1');
  const tier2Floor = ethers.utils.parseEther('2');
  const tier3Floor = ethers.utils.parseEther('3');
  const fourEth = ethers.utils.parseEther('4');
  const ethToken = '0x000000000000000000000000000000000000EEEe'; // JBTokens.ETH

  async function setup() {
    let [deployer, projectTerminal, beneficiary, ...accounts] = await ethers.getSigners();

    let [
      mockJbDirectory,
    ] = await Promise.all([
      deployMockContract(deployer, jbDirectory.abi),
    ]);

    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, projectTerminal.address).returns(true);
    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, beneficiary.address).returns(false);

    const rewardTiers = [
      { contributionFloor: tier1Floor, idCeiling: 1001, remainingAllowance: 1000 },
      { contributionFloor: tier2Floor, idCeiling: 1501, remainingAllowance: 500 },
      { contributionFloor: tier3Floor, idCeiling: 1511, remainingAllowance: 10 }
    ];

    const nftRewardTieredPriceResolverFactory = await ethers.getContractFactory('NFTRewardTieredPriceResolver', deployer);
    const nftRewardTieredPriceResolver = await nftRewardTieredPriceResolverFactory
      .connect(deployer)
      .deploy(ethToken, '100000000000', 2, rewardTiers);

    const jbNFTRewardDataSourceFactory = await ethers.getContractFactory('NFTRewardDataSourceDelegate', deployer);
    const jbNFTRewardDataSource = await jbNFTRewardDataSourceFactory
      .connect(deployer)
      .deploy(
        PROJECT_ID,
        mockJbDirectory.address,
        1,
        { token: ethToken, value: 0, decimals: 18, currency: CURRENCY_ETH },
        NFT_NAME,
        NFT_SYMBOL,
        NFT_URI,
        ethers.constants.AddressZero,
        NFT_METADATA,
        ethers.constants.AddressZero,
        nftRewardTieredPriceResolver.address
      );

    return {
      projectTerminal,
      beneficiary,
      accounts,
      jbNFTRewardDataSource,
    };
  }

  it('Should mint token if meeting tier 1 contribution parameters', async () => {
    const { jbNFTRewardDataSource, projectTerminal, beneficiary } = await setup();

    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: tier1Floor, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).to.emit(jbNFTRewardDataSource, 'Transfer').withArgs(ethers.constants.AddressZero, beneficiary.address, 1);
  });

  it('Should mint token if exceeding tier 3 contribution parameters', async () => {
    const { jbNFTRewardDataSource, projectTerminal, beneficiary } = await setup();

    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: fourEth, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).to.emit(jbNFTRewardDataSource, 'Transfer').withArgs(ethers.constants.AddressZero, beneficiary.address, 1501);
  });

  it('Should mint token if meeting tier 3 contribution parameters', async () => {
    const { jbNFTRewardDataSource, projectTerminal, beneficiary } = await setup();

    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: tier3Floor, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).to.emit(jbNFTRewardDataSource, 'Transfer').withArgs(ethers.constants.AddressZero, beneficiary.address, 1501);
  });

  it('Should not mint token if below min contribution', async () => {
    const { jbNFTRewardDataSource, projectTerminal, beneficiary } = await setup();

    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: halfEth, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).not.to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it('fail to deploy: INVALID_PRICE_SORT_ORDER', async () => {
    const { deployer } = await setup();
    const unsortedRewardTiers = [
      { contributionFloor: tier1Floor, idCeiling: 1001, remainingAllowance: 1000 },
      { contributionFloor: tier3Floor, idCeiling: 1511, remainingAllowance: 10 },
      { contributionFloor: tier2Floor, idCeiling: 1501, remainingAllowance: 500 }
    ];

    const nftRewardTieredPriceResolverFactory = await ethers.getContractFactory('NFTRewardTieredPriceResolver', deployer);

    await expect(nftRewardTieredPriceResolverFactory.deploy(ethToken, '100000000000', 2, unsortedRewardTiers))
      .to.be.revertedWith('INVALID_PRICE_SORT_ORDER()');
  });

  it('test non-mint results', async () => {
    const { beneficiary, deployer } = await setup();
    const rewardTiers = [
      { contributionFloor: tier1Floor, idCeiling: 1001, remainingAllowance: 1000 },
      { contributionFloor: tier2Floor, idCeiling: 1501, remainingAllowance: 500 },
      { contributionFloor: tier3Floor, idCeiling: 1511, remainingAllowance: 10 }
    ];

    const nftRewardTieredPriceResolverFactory = await ethers.getContractFactory('NFTRewardTieredPriceResolver', deployer);
    const nftRewardTieredPriceResolver = await nftRewardTieredPriceResolverFactory.deploy(ethToken, 0, 0, rewardTiers);

    const invalidTokenContribution = { token: ethers.constants.AddressZero, value: 0, decimals: 18, currency: ethers.constants.AddressZero };
    let tokenId = await nftRewardTieredPriceResolver.callStatic.validateContribution(beneficiary.address, invalidTokenContribution, ethers.constants.AddressZero);

    await expect(tokenId).to.eq(0);

    const validContribution = { token: ethToken, value: 0, decimals: 18, currency: CURRENCY_ETH };
    tokenId = await nftRewardTieredPriceResolver.callStatic.validateContribution(beneficiary.address, validContribution, ethers.constants.AddressZero);

    await expect(tokenId).to.eq(0);
  });
});

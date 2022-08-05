import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';

describe('NFTRewardDataSourceDelegate::didPay(...): open tier', () => {
  const PROJECT_ID = 2;
  const CURRENCY_ETH = '0x000000000000000000000000000000000000EEEe'; // JBCurrencies.ETH
  const halfEth = ethers.utils.parseEther('0.5');
  const tier1Floor = ethers.utils.parseEther('1');
  const tier2Floor = ethers.utils.parseEther('2');
  const tier3Floor = ethers.utils.parseEther('3');
  const fourEth = ethers.utils.parseEther('4');
  const ethToken = '0x000000000000000000000000000000000000EEEe'; // JBTokens.ETH

  let deployer;
  let projectTerminal;
  let beneficiary;
  let accounts;
  let jbNFTRewardDataSource;

  beforeEach(async () => {
    const NFT_NAME = 'Reward NFT';
    const NFT_SYMBOL = 'RN';
    const NFT_URI = 'ipfs://content_base';
    const NFT_METADATA = 'ipfs://metadata';

    [deployer, projectTerminal, beneficiary, ...accounts] = await ethers.getSigners();

    const mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi);

    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, projectTerminal.address).returns(true);
    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, beneficiary.address).returns(false);

    const rewardTiers = [
      { contributionFloor: tier1Floor },
      { contributionFloor: tier2Floor },
      { contributionFloor: tier3Floor }
    ];

    const priceResolverFactory = await ethers.getContractFactory('OpenTieredPriceResolver', deployer);
    const priceResolver = await priceResolverFactory
      .connect(deployer)
      .deploy(ethToken, rewardTiers);

    const uriResolverFactory = await ethers.getContractFactory('OpenTieredTokenUriResolver', deployer);
    const uriResolver = await uriResolverFactory
      .connect(deployer)
      .deploy('ipfs://token_uri/');

    const jbNFTRewardDataSourceFactory = await ethers.getContractFactory('NFTRewardDataSourceDelegate', deployer);
    jbNFTRewardDataSource = await jbNFTRewardDataSourceFactory
      .connect(deployer)
      .deploy(
        PROJECT_ID,
        mockJbDirectory.address,
        1,
        { token: ethToken, value: 0, decimals: 18, currency: CURRENCY_ETH },
        NFT_NAME,
        NFT_SYMBOL,
        NFT_URI,
        uriResolver.address,
        NFT_METADATA,
        ethers.constants.AddressZero,
        priceResolver.address
      );
  });

  it('Should mint token if meeting tier 1 contribution parameters', async () => {
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
    })).to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it('Should mint token if exceeding tier 3 contribution parameters', async () => {
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
    })).to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it('Should mint token if meeting tier 3 contribution parameters', async () => {
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
    })).to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it('Should not mint token if below min contribution', async () => {
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
    const unsortedRewardTiers = [
      { contributionFloor: tier1Floor },
      { contributionFloor: tier3Floor },
      { contributionFloor: tier2Floor }
    ];

    const priceResolverFactory = await ethers.getContractFactory('OpenTieredPriceResolver', deployer);

    await expect(priceResolverFactory.deploy(ethToken, unsortedRewardTiers))
      .to.be.revertedWith('INVALID_PRICE_SORT_ORDER(2)');
  });

  it('test non-mint results', async () => {
    const rewardTiers = [
      { contributionFloor: tier1Floor },
      { contributionFloor: tier2Floor },
      { contributionFloor: tier3Floor }
    ];

    const priceResolverFactory = await ethers.getContractFactory('OpenTieredPriceResolver', deployer);
    const priceResolver = await priceResolverFactory.deploy(ethToken, rewardTiers);

    const invalidTokenContribution = { token: ethers.constants.AddressZero, value: 0, decimals: 18, currency: ethers.constants.AddressZero };
    let tokenId = await priceResolver.callStatic.validateContribution(beneficiary.address, invalidTokenContribution, ethers.constants.AddressZero);

    await expect(tokenId).to.eq(0);

    const validContribution = { token: ethToken, value: 0, decimals: 18, currency: CURRENCY_ETH };
    tokenId = await priceResolver.callStatic.validateContribution(beneficiary.address, validContribution, ethers.constants.AddressZero);

    await expect(tokenId).to.eq(0);
  });
});

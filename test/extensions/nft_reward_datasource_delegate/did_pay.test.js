import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';

describe('NFTRewardDataSourceDelegate::didPay(...)', function () {
  const PROJECT_ID = 2;
  const CURRENCY_ETH = 1;
  const ETH_TO_PAY = ethers.utils.parseEther('1');
  const ethToken = ethers.constants.AddressZero;

  let projectTerminal;
  let beneficiary;
  let jbNFTRewardDataSource;

  beforeEach(async () => {
    const NFT_NAME = 'Reward NFT';
    const NFT_SYMBOL = 'RN';
    const NFT_URI = 'ipfs://content_base';
    const NFT_METADATA = 'ipfs://metadata';
    let deployer;
    let accounts;

    [deployer, projectTerminal, beneficiary, ...accounts] = await ethers.getSigners();

    const mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi)

    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, projectTerminal.address).returns(true);
    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, beneficiary.address).returns(false);

    const jbNFTRewardDataSourceFactory = await ethers.getContractFactory('NFTRewardDataSourceDelegate', deployer);
    jbNFTRewardDataSource = await jbNFTRewardDataSourceFactory
      .connect(deployer)
      .deploy(
        PROJECT_ID,
        mockJbDirectory.address,
        1,
        { token: ethToken, value: 1000000, decimals: 18, currency: CURRENCY_ETH },
        NFT_NAME,
        NFT_SYMBOL,
        NFT_URI,
        ethers.constants.AddressZero,
        NFT_METADATA,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero
      );
  });

  it(`Should mint token if meeting contribution parameters`, async () => {
    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: ETH_TO_PAY, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).to.emit(jbNFTRewardDataSource, 'Transfer').withArgs(ethers.constants.AddressZero, beneficiary.address, 0);
  });

  it(`Should not mint token if exceeding max supply`, async () => {
    await jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: ETH_TO_PAY, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    });

    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: ETH_TO_PAY, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).not.to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it(`Should not mint token if contribution below limit`, async () => {
    await expect(jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: 0, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).not.to.emit(jbNFTRewardDataSource, 'Transfer');
  });

  it(`Should not mint token if not called from terminal`, async () => {
    await expect(jbNFTRewardDataSource.connect(beneficiary).didPay({
      payer: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: 2000, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: beneficiary.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    })).to.be.revertedWith('INVALID_PAYMENT_EVENT()');

  });

  it(`Should not mint project tokens on payment`, async () => {
    await jbNFTRewardDataSource.payParams({
      terminal: projectTerminal.address,
      payer: beneficiary.address,
      amount: { token: ethToken, value: 1, decimals: 18, currency: CURRENCY_ETH },
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      beneficiary: beneficiary.address,
      weight: 0,
      reservedRate: 0,
      memo: '',
      metadata: ethers.utils.toUtf8Bytes('')
    });
  });

  it(`Should not redeem NFTs for ether balance`, async () => {
    await jbNFTRewardDataSource.didRedeem({
      holder: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      projectTokenCount: 0,
      reclaimedAmount: { token: ethToken, value: 1, decimals: 18, currency: CURRENCY_ETH },
      beneficiary: beneficiary.address,
      memo: '',
      metadata: ethers.utils.toUtf8Bytes('')
    });

    await jbNFTRewardDataSource.redeemParams({
      terminal: projectTerminal.address,
      holder: beneficiary.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      tokenCount: 0,
      totalSupply: 0,
      overflow: 0,
      reclaimAmount: { token: ethToken, value: 1, decimals: 18, currency: CURRENCY_ETH },
      useTotalOverflow: false,
      redemptionRate: 0,
      ballotRedemptionRate: 0,
      memo: '',
      metadata: ethers.utils.toUtf8Bytes('')
    });
  });

  it(`Test supportsInterface()`, async () => {
    let match = await jbNFTRewardDataSource.supportsInterface(0x599064e9); // IJBFundingCycleDataSource
    expect(match).to.equal(true);

    match = await jbNFTRewardDataSource.supportsInterface(0x304b1eea); // IJBPayDelegate
    expect(match).to.equal(true);

    match = await jbNFTRewardDataSource.supportsInterface(0x2400e8f7); // IJBRedemptionDelegate
    expect(match).to.equal(true);
  });
});

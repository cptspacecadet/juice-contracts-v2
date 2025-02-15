import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';

describe('NFTRewardDataSourceDelegate::transfer(...)', function () {
  const PROJECT_ID = 2;
  const NFT_NAME = 'Reward NFT';
  const NFT_SYMBOL = 'RN';
  const NFT_URI = 'ipfs://content_base';
  const NFT_METADATA = 'ipfs://metadata';
  const CURRENCY_ETH = 1;
  const ETH_TO_PAY = ethers.utils.parseEther('1');
  const ethToken = ethers.constants.AddressZero;

  async function setup() {
    let [deployer, projectTerminal, owner, differentOwner, notOwner, ...accounts] = await ethers.getSigners();

    let [
      mockJbDirectory,
    ] = await Promise.all([
      deployMockContract(deployer, jbDirectory.abi),
    ]);

    await mockJbDirectory.mock.isTerminalOf.withArgs(PROJECT_ID, projectTerminal.address).returns(true);

    const jbNFTRewardDataSourceFactory = await ethers.getContractFactory('NFTRewardDataSourceDelegate', deployer);
    const jbNFTRewardDataSource = await jbNFTRewardDataSourceFactory
      .connect(deployer)
      .deploy(
        PROJECT_ID,
        mockJbDirectory.address,
        2,
        { token: ethToken, value: 1000000, decimals: 18, currency: CURRENCY_ETH },
        NFT_NAME,
        NFT_SYMBOL,
        NFT_URI,
        ethers.constants.AddressZero,
        NFT_METADATA,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero
      );

    await jbNFTRewardDataSource.connect(deployer).setTransferrable(false);

    await jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: owner.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: ETH_TO_PAY, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: owner.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    });

    await jbNFTRewardDataSource.connect(projectTerminal).didPay({
      payer: differentOwner.address,
      projectId: PROJECT_ID,
      currentFundingCycleConfiguration: 0,
      amount: { token: ethToken, value: ETH_TO_PAY, decimals: 18, currency: CURRENCY_ETH },
      projectTokenCount: 0,
      beneficiary: differentOwner.address,
      preferClaimedTokens: true,
      memo: '',
      metadata: '0x42'
    });

    return {
      projectTerminal,
      owner,
      differentOwner,
      notOwner,
      accounts,
      jbNFTRewardDataSource
    };
  }

  it('Cannot transfer non-transferrable token', async () => {
    const { jbNFTRewardDataSource, owner, notOwner } = await setup();
    const tokenId = 0;

    await expect(jbNFTRewardDataSource.connect(owner).transfer(notOwner.address, tokenId))
      .to.be.revertedWith('NON_TRANSFERRABLE()');

  });

  it('Cannot approve then transfer on behalf', async () => {
    const { jbNFTRewardDataSource, owner, notOwner } = await setup();
    const tokenId = 0;

    await jbNFTRewardDataSource.connect(owner).approve(notOwner.address, tokenId);
    await expect(jbNFTRewardDataSource.connect(notOwner).transferFrom(owner.address, notOwner.address, tokenId))
      .to.be.revertedWith('NON_TRANSFERRABLE()');
  });
});

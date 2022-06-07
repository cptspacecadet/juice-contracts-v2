import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('DutchAuctionHouse tests', () => {
  const projectId = 1;
  const startPrice = ethers.utils.parseEther('2');
  const endPrice = ethers.utils.parseEther('1');
  const tokenId = 1;
  const auctionDuration = 60 * 60;
  const feeRate = 5_000_000; // 0.5%
  const pricingPeriodDuration = 5 * 60; // seconds

  async function setup() {
    let [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

    const directory = await deployMockContract(deployer, jbDirectory.abi);
    const feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);

    await feeReceiverTerminal.mock.addToBalanceOf.returns();
    await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);

    const jbSplitPayerUtilFactory = await ethers.getContractFactory('JBSplitPayerUtil', deployer);
    const jbSplitPayerUtil = await jbSplitPayerUtilFactory.connect(deployer).deploy();

    const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', {
      libraries: { JBSplitPayerUtil: jbSplitPayerUtil.address },
      signer: deployer
    });
    const dutchAuctionHouse = await dutchAuctionHouseFactory
      .connect(deployer)
      .deploy(projectId, feeReceiverTerminal.address, feeRate, pricingPeriodDuration, deployer.address, directory.address);

    const tokenFactory = await ethers.getContractFactory('MockERC721', deployer);
    const token = await tokenFactory.connect(deployer).deploy();
    await token.connect(deployer).mint(tokenOwner.address, tokenId);

    return {
      deployer,
      accounts,
      tokenOwner,
      dutchAuctionHouse,
      token
    };
  }

  async function create(token, dutchAuctionHouse, tokenOwner) {
    await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);
    await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '');
  }

  it(`create() success`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);

    await expect(
      dutchAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
    ).to.emit(dutchAuctionHouse, 'CreateDutchAuction').withArgs(tokenOwner.address, token.address, tokenId, startPrice, '');
  });

  it(`create() fail: not token owner`, async () => {
    const { accounts, dutchAuctionHouse, token } = await setup();

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
    ).to.be.revertedWith('ERC721: transfer caller is not owner nor approved');
  });

  it(`create() fail: auction already exists`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);
    await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '');

    await expect(
      dutchAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
    ).to.be.revertedWith('AUCTION_EXISTS()');
  });

  it(`create() fail: invalid price`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);

    await expect(
      dutchAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', endPrice, auctionDuration, [], '')
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`create() fail: invalid price`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);

    await expect(
      dutchAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, startPrice, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', auctionDuration, [], '')
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`bid() success: initial`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: startPrice })
    ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');
  });

  it(`bid() success: increase bid`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);
    await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: startPrice })
    ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');
  });

  it(`bid() fail: invalid price`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: '10000' })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, below current bid`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);
    await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

    await expect(
      dutchAuctionHouse
        .connect(accounts[1])
        .bid(token.address, tokenId, '', { value: endPrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, at current`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);
    await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: endPrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid auction`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId + 1, '', { value: '10000' })
    ).to.be.revertedWith('INVALID_AUCTION()');
  });

  it(`bid() fail: auction ended`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    await create(token, dutchAuctionHouse, tokenOwner);

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 120]);
    await network.provider.send("evm_mine");

    await expect(
      dutchAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: startPrice })
    ).to.be.revertedWith('AUCTION_ENDED()');
  });

  it(`settle() success: sale`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    await create(token, dutchAuctionHouse, tokenOwner);
    await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration * 2 + 120]);
    await network.provider.send("evm_mine");

    await expect(
      dutchAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId, '')
    ).to.emit(dutchAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');
  });

  it(`settle() success: return`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    await create(token, dutchAuctionHouse, tokenOwner);

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 120]);
    await network.provider.send("evm_mine");

    await expect(
      dutchAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId, '')
    ).to.emit(dutchAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
  });

  it(`settle() fail: invalid auction`, async () => {
    const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

    await create(token, dutchAuctionHouse, tokenOwner);

    await expect(
      dutchAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId + 1, '')
    ).to.be.revertedWith('INVALID_AUCTION()');
  });

  it(`currentPrice()`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
    await network.provider.send("evm_mine");

    await create(token, dutchAuctionHouse, tokenOwner);

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
    await network.provider.send("evm_mine");
    expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.eq(startPrice);

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration + 65]);
    await network.provider.send("evm_mine");
    expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.lt(startPrice);
  });

  it(`currentPrice() fail: invalid auction`, async () => {
    const { dutchAuctionHouse, token, tokenOwner } = await setup();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
    await network.provider.send("evm_mine");

    await create(token, dutchAuctionHouse, tokenOwner);

    await network.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
    await network.provider.send("evm_mine");
    await expect(dutchAuctionHouse.currentPrice(token.address, tokenId + 1)).to.be.revertedWith('INVALID_AUCTION()');
  });
});

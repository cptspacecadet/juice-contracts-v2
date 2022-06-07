import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('EnglishAuctionHouse tests', () => {
  const projectId = 1;
  const basePrice = ethers.utils.parseEther('1');
  const reservePrice = ethers.utils.parseEther('2');
  const tokenId = 1;
  const auctionDuration = 60 * 60;
  const feeRate = 5_000_000; // 0.5%
  const feeDenominator = 1_000_000_000;
  const allowPublicAuctions = false;

  async function setup() {
    let [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

    const directory = await deployMockContract(deployer, jbDirectory.abi);
    const feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);

    await feeReceiverTerminal.mock.addToBalanceOf.returns();
    await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);

    const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });

    const englishAuctionHouse = await englishAuctionHouseFactory
      .connect(deployer)
      .deploy(
        projectId,
        feeReceiverTerminal.address,
        feeRate,
        allowPublicAuctions,
        deployer.address,
        directory.address
      );

    const tokenFactory = await ethers.getContractFactory('MockERC721', deployer);
    const token = await tokenFactory.connect(deployer).deploy();
    await token.connect(deployer).mint(tokenOwner.address, tokenId);

    return {
      deployer,
      accounts,
      tokenOwner,
      englishAuctionHouse,
      token,
      feeReceiverTerminal
    };
  }

  async function create(token, englishAuctionHouse, tokenOwner) {
    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
    await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, reservePrice, auctionDuration, [], '');
  }

  it(`create() success`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
    ).to.emit(englishAuctionHouse, 'CreateEnglishAuction').withArgs(tokenOwner.address, token.address, tokenId, basePrice, '');
  });

  it(`create() fail: not token owner`, async () => {
    const { accounts, englishAuctionHouse, token } = await setup();

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
    ).to.be.revertedWith('ERC721: transfer caller is not owner nor approved');
  });

  it(`create() fail: auction already exists`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
    await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, 0, auctionDuration, [], '');

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
    ).to.be.revertedWith('AUCTION_EXISTS()');
  });

  it(`create() fail: invalid price`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, tokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 0, auctionDuration, [], '')
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`create() fail: invalid price`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, 1, ethers.utils.parseEther('1'), '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', auctionDuration, [], '')
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`bid() success: initial`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: basePrice })
    ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, basePrice, '');
  });

  it(`bid() success: increase bid`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: basePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: reservePrice })
    ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, reservePrice, '');
  });

  it(`bid() fail: invalid price`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: '10000' })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, below current`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .bid(token.address, tokenId, '', { value: basePrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, at current`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: reservePrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid auction`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId + 1, '', { value: '10000' })
    ).to.be.revertedWith('INVALID_AUCTION()');
  });

  it(`bid() fail: auction ended`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await network.provider.send("evm_increaseTime", [auctionDuration + 1]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, tokenId, '', { value: '10000' })
    ).to.be.revertedWith('AUCTION_ENDED()');
  });

  it(`settle() success: sale`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner, feeReceiverTerminal } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

    await network.provider.send("evm_increaseTime", [auctionDuration + 1]);
    await network.provider.send("evm_mine");

    const expectedFee = reservePrice.mul(feeRate).div(feeDenominator);
    const expectedProceeds = reservePrice.sub(expectedFee);

    const tx = englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
    await expect(tx)
      .to.emit(englishAuctionHouse, 'ConcludeAuction')
      .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, reservePrice, '');
    await expect(await tx)
      .to.changeEtherBalances([tokenOwner, feeReceiverTerminal], [expectedProceeds, expectedFee]);
  });

  it(`settle() success: return`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: basePrice });

    await network.provider.send("evm_increaseTime", [auctionDuration + 1]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId, '')
    ).to.emit(englishAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
  });

  it(`settle() fail: auction in progress`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await network.provider.send("evm_increaseTime", [auctionDuration - 10000]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId, '')
    ).to.be.revertedWith('AUCTION_IN_PROGRESS()');
  });

  it(`settle() fail: invalid auction`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, tokenId + 1, '')
    ).to.be.revertedWith('INVALID_AUCTION()');
  });
});

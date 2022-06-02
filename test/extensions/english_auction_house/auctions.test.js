import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('EnglishAuctionHouse tests', () => {
  const testBasePrice = ethers.utils.parseEther('1');
  const testReservePrice = ethers.utils.parseEther('2');
  const testTokenId = 1;
  const testAuctionDuration = 60 * 60;
  const testActionFee = 5_000_000; // 0.5%

  async function setup() {
    let [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

    const jbSplitPayerUtilFactory = await ethers.getContractFactory('JBSplitPayerUtil', deployer);
    const jbSplitPayerUtil = await jbSplitPayerUtilFactory.connect(deployer).deploy();

    const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', {
      libraries: { JBSplitPayerUtil: jbSplitPayerUtil.address },
      signer: deployer
    });
    const englishAuctionHouse = await englishAuctionHouseFactory.connect(deployer).deploy([], ethers.constants.AddressZero, deployer.address, testActionFee);

    const tokenFactory = await ethers.getContractFactory('MockERC721', deployer);
    const token = await tokenFactory.connect(deployer).deploy();
    await token.connect(deployer).mint(tokenOwner.address, testTokenId);

    return {
      deployer,
      accounts,
      tokenOwner,
      englishAuctionHouse,
      token
    };
  }

  async function create(token, englishAuctionHouse, tokenOwner) {
    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
    await englishAuctionHouse.connect(tokenOwner).create(token.address, testTokenId, testBasePrice, testReservePrice, testAuctionDuration, []);
  }

  it(`create() success`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, testTokenId, testBasePrice, 0, testAuctionDuration, [])
    ).to.emit(englishAuctionHouse, 'CreateEnglishAuction').withArgs(tokenOwner.address, token.address, testTokenId, testBasePrice);
  });

  it(`create() fail: not token owner`, async () => {
    const { accounts, englishAuctionHouse, token } = await setup();

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .create(token.address, testTokenId, testBasePrice, 0, testAuctionDuration, [])
    ).to.be.revertedWith('ERC721: transfer caller is not owner nor approved');
  });

  it(`create() fail: auction already exists`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
    await englishAuctionHouse.connect(tokenOwner).create(token.address, testTokenId, testBasePrice, 0, testAuctionDuration, []);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, testTokenId, testBasePrice, 0, testAuctionDuration, [])
    ).to.be.revertedWith('AUCTION_EXISTS()');
  });

  it(`create() fail: invalid price`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, testTokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 0, testAuctionDuration, [])
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`create() fail: invalid price`, async () => {
    const { englishAuctionHouse, token, tokenOwner } = await setup();

    await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

    await expect(
      englishAuctionHouse
        .connect(tokenOwner)
        .create(token.address, 1, ethers.utils.parseEther('1'), '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', testAuctionDuration, [])
    ).to.be.revertedWith('INVALID_PRICE()');
  });

  it(`bid() success: initial`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId, { value: testBasePrice })
    ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, testTokenId, testBasePrice);
  });

  it(`bid() success: increase bid`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, testTokenId, { value: testBasePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId, { value: testReservePrice })
    ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, testTokenId, testReservePrice);
  });

  it(`bid() fail: invalid price`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId, { value: '10000' })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, below current`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, testTokenId, { value: testReservePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .bid(token.address, testTokenId, { value: testBasePrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid price, at current`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, testTokenId, { value: testReservePrice });

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId, { value: testReservePrice })
    ).to.be.revertedWith('INVALID_BID()');
  });

  it(`bid() fail: invalid auction`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId + 1, { value: '10000' })
    ).to.be.revertedWith('INVALID_AUCTION()');
  });

  it(`bid() fail: auction ended`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await network.provider.send("evm_increaseTime", [testAuctionDuration + 1]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[0])
        .bid(token.address, testTokenId, { value: '10000' })
    ).to.be.revertedWith('AUCTION_ENDED()');
  });

  it(`settle() success: sale`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, testTokenId, { value: testReservePrice });

    await network.provider.send("evm_increaseTime", [testAuctionDuration + 1]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, testTokenId)
    ).to.emit(englishAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, accounts[0].address, token.address, testTokenId, testReservePrice);
  });

  it(`settle() success: return`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);
    await englishAuctionHouse.connect(accounts[0]).bid(token.address, testTokenId, { value: testBasePrice });

    await network.provider.send("evm_increaseTime", [testAuctionDuration + 1]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, testTokenId)
    ).to.emit(englishAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, testTokenId, 0);
  });

  it(`settle() fail: auction in progress`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await network.provider.send("evm_increaseTime", [testAuctionDuration - 10000]);
    await network.provider.send("evm_mine");

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, testTokenId)
    ).to.be.revertedWith('AUCTION_IN_PROGRESS()');
  });

  it(`settle() fail: auction in progress`, async () => {
    const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

    await create(token, englishAuctionHouse, tokenOwner);

    await expect(
      englishAuctionHouse
        .connect(accounts[1])
        .settle(token.address, testTokenId + 1)
    ).to.be.revertedWith('INVALID_AUCTION()');
  });
});

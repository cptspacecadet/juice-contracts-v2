import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Vesting Tests', () => {
  let deployer;
  let accounts;
  let token;
  let vesting;

  before(async () => {
    [deployer, ...accounts] = await ethers.getSigners();

    const vestingFactory = await ethers.getContractFactory('VestTokens');
    vesting = await vestingFactory.connect(deployer).deploy();
    await vesting.deployed();

    const tokenFactory = await ethers.getContractFactory('PlayToken');
    token = await tokenFactory.connect(deployer).deploy('PlayToken', 'PT');
    await token.deployed();

    token.connect(deployer).mint(deployer.address, '1000000000')
  });

  it('Fail to fund', async () => {
    const vestingPeriodSeconds = 60 * 60 * 1;
    const periodicGrant = 100;
    const periods = 10;

    await expect(vesting.connect(deployer).create(
      accounts[0].address,
      token.address,
      periodicGrant,
      0,
      vestingPeriodSeconds,
      periods,
      'Simple Vest'
    )).to.reverted;
  });

  it('Simple Path', async () => {
    token.connect(deployer).approve(vesting.address, '1000');

    const headLevel = await ethers.provider.getBlockNumber();
    const headBlock = await ethers.provider.getBlock(headLevel);

    const vestingPeriodSeconds = 60 * 60 * 1;
    const periodicGrant = 100;
    const periods = 10;
    const totalGrant = periodicGrant * periods;
    const cliffSeconds = headBlock.timestamp + vestingPeriodSeconds;

    const planId = getPlanId(accounts[0].address, deployer.address, token.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods);

    const initialSponsorBalance = await token.balanceOf(deployer.address);

    await expect(vesting.connect(deployer).create(
      accounts[0].address,
      token.address,
      periodicGrant,
      cliffSeconds,
      vestingPeriodSeconds,
      periods,
      'Simple Vest'
    )).to.emit(vesting, 'CreatePlan')
      .withArgs(accounts[0].address, deployer.address, token.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, 10, 'Simple Vest', planId);

    await expect(vesting.connect(deployer).create(
      accounts[0].address,
      token.address,
      periodicGrant,
      cliffSeconds,
      vestingPeriodSeconds,
      periods,
      'Simple Vest'
    )).to.be.revertedWith('DUPLICATE_CONFIGURATION()')

    const updatedSponsorBalance = await token.balanceOf(deployer.address);

    expect(initialSponsorBalance - updatedSponsorBalance).to.equal(totalGrant);

    await ethers.provider.send('evm_increaseTime', [60 * 10]);
    await ethers.provider.send('evm_mine', []);

    await expect(vesting.connect(accounts[1]).distribute(planId)).to.be.revertedWith('CLIFF_NOT_REACHED()');

    await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds]);
    await ethers.provider.send('evm_mine', []);

    await expect(vesting.connect(accounts[1]).distribute(planId)).to.emit(vesting, 'DistributeAward')
      .withArgs(planId, accounts[0].address, token.address, periodicGrant, periodicGrant, 0);

    expect(await token.balanceOf(accounts[0].address)).to.equal(periodicGrant);

    await ethers.provider.send('evm_increaseTime', [Math.floor(vestingPeriodSeconds / 2)]);
    await ethers.provider.send('evm_mine', []);

    await expect(vesting.connect(accounts[1]).distribute(planId)).to.be.revertedWith('INCOMPLETE_PERIOD()');

    await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds * 3]);
    await ethers.provider.send('evm_mine', []);

    await expect(vesting.connect(accounts[1]).distribute(planId)).to.emit(vesting, 'DistributeAward')
      .withArgs(planId, accounts[0].address, token.address, periodicGrant, periodicGrant * 3, 0);

    expect(await token.balanceOf(accounts[0].address)).to.equal(periodicGrant * 4);

    const details = await vesting.planDetails(planId);
    expect(details[0]['amount']).to.equal(periodicGrant);
  });

});

function getPlanId(recipient, sponsor, token, amount, cliff, periodDuration, periods) {
  const a = ethers.utils.solidityPack(
    ['address', 'address', 'address', 'uint256', 'uint256', 'uint256', 'uint256'],
    [recipient, sponsor, token, amount, cliff, periodDuration, periods]
  );
  const b = ethers.utils.keccak256(a);
  const c = ethers.BigNumber.from(b);

  return c.toString();
}

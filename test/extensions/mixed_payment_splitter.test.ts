import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('MixedPaymentSplitter tests', () => {
    const name = 'example-splitter';
    const projects = [2, 3, 4];
    const payees: string[] = [];
    const shares = [2000, 1000, 2000, 2000, 1000, 2000];

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];
    let mixedPaymentSplitter: any;

    before(async () => {
        [deployer, ...accounts] = await ethers.getSigners();
        payees.push(accounts[0].address);
        payees.push(accounts[1].address);
        payees.push(accounts[2].address);

        const directory = await deployMockContract(deployer, jbDirectory.abi);
        const terminalTwo = await deployMockContract(deployer, jbTerminal.abi);
        const terminalThree = await deployMockContract(deployer, jbTerminal.abi);
        const terminalFour = await deployMockContract(deployer, jbTerminal.abi);

        const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

        await terminalTwo.mock.addToBalanceOf.returns();
        await terminalThree.mock.addToBalanceOf.returns();
        await terminalFour.mock.addToBalanceOf.returns();
        await directory.mock.primaryTerminalOf.withArgs(projects[0], jbxJbTokensEth).returns(terminalTwo.address);
        await directory.mock.isTerminalOf.withArgs(projects[0], terminalTwo.address).returns(true);
        await directory.mock.primaryTerminalOf.withArgs(projects[1], jbxJbTokensEth).returns(terminalThree.address);
        await directory.mock.isTerminalOf.withArgs(projects[1], terminalThree.address).returns(true);
        await directory.mock.primaryTerminalOf.withArgs(projects[2], jbxJbTokensEth).returns(terminalFour.address);
        await directory.mock.isTerminalOf.withArgs(projects[2], terminalFour.address).returns(true);

        const mixedPaymentSplitterFactory = await ethers.getContractFactory('MixedPaymentSplitter', {
            signer: deployer
        });
        mixedPaymentSplitter = await mixedPaymentSplitterFactory
            .connect(deployer)
            .deploy(name, payees, projects, shares, directory.address);

        await accounts[0].sendTransaction({ to: mixedPaymentSplitter.address, value: ethers.utils.parseEther('1.0') });
    });

    it(`releasable() test`, async () => {
        const largeShare = ethers.utils.parseEther('1.0').mul(2000).div(10000);

        expect(await mixedPaymentSplitter['releasable(address)'](accounts[0].address)).to.equal(largeShare.toString());
        expect(await mixedPaymentSplitter['releasable(uint256)'](projects[0])).to.equal(largeShare.toString());
    });

    it(`release() test`, async () => {
        const largeShare = ethers.utils.parseEther('1.0').mul(2000).div(10000);

        await expect(mixedPaymentSplitter['release(address)'](accounts[0].address))
            .to.emit(mixedPaymentSplitter, 'PaymentReleased').withArgs(accounts[0].address, largeShare);
        await expect(mixedPaymentSplitter['release(uint256)'](projects[0]))
            .to.emit(mixedPaymentSplitter, 'ProjectPaymentReleased').withArgs(projects[0], largeShare);
    });
});

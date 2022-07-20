import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbOperatorStore from '../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../artifacts/contracts/JBProjects.sol/JBProjects.json';

describe('JBRoleManager Tests', () => {
  let roleManager;
  let deployer;
  let accounts;

  const projectId = 1;
  const anotherProjectId = 2;
  const activeRoleName = 'ROLE-1';
  const anotherRoleName = 'ROLE-2';
  const invalidRoleName = 'ROLE-3';

  const jbManageRolesPermission = 101; // JBOperations.MANAGE_ROLES

  before(async () => {
    [deployer, ...accounts] = await ethers.getSigners();

    const directory = await deployMockContract(deployer, jbDirectory.abi);
    await directory.mock.controllerOf.withArgs(projectId).returns(deployer.address);
    await directory.mock.controllerOf.withArgs(anotherProjectId).returns(deployer.address);

    const operatorStore = await deployMockContract(deployer, jbOperatorStore.abi);
    await operatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, projectId, jbManageRolesPermission).returns(true);

    const projects = await deployMockContract(deployer, jbProjects.abi);
    await projects.mock.ownerOf.withArgs(projectId).returns(deployer.address);
    await projects.mock.ownerOf.withArgs(anotherProjectId).returns(deployer.address);

    const roleManagerFactory = await ethers.getContractFactory('JBRoleManager');
    roleManager = await roleManagerFactory.connect(deployer)
      .deploy(directory.address, operatorStore.address, projects.address, deployer.address);
    await roleManager.deployed();
  });

  it('Role workflows', async () => {
    await expect(roleManager.connect(deployer).addProjectRole(projectId, activeRoleName))
      .to.emit(roleManager, 'AddRole')
      .withArgs(projectId, activeRoleName);

    await expect(roleManager.connect(deployer).addProjectRole(projectId, anotherRoleName))
      .to.emit(roleManager, 'AddRole')
      .withArgs(projectId, anotherRoleName);

    await expect(roleManager.connect(deployer).addProjectRole(projectId, activeRoleName))
      .to.be.revertedWith('DUPLICATE_ROLE()');

    let projectRoles = await roleManager.connect(deployer).listProjectRoles(projectId);
    expect(projectRoles.length).to.equal(2);
    expect(projectRoles[0]).to.equal(activeRoleName);

    projectRoles = await roleManager.connect(deployer).listProjectRoles(anotherProjectId);
    expect(projectRoles.length).to.equal(0);

    await expect(roleManager.connect(deployer).addProjectRole(anotherProjectId, activeRoleName))
      .to.emit(roleManager, 'AddRole')
      .withArgs(anotherProjectId, activeRoleName);

    await expect(roleManager.connect(deployer).addProjectRole(anotherProjectId, anotherRoleName))
      .to.emit(roleManager, 'AddRole')
      .withArgs(anotherProjectId, anotherRoleName);

    await expect(roleManager.connect(deployer).removeProjectRole(anotherProjectId, anotherRoleName))
      .to.emit(roleManager, 'RemoveRole')
      .withArgs(anotherProjectId, anotherRoleName);

    await expect(roleManager.connect(deployer).removeProjectRole(anotherProjectId, invalidRoleName))
      .to.be.revertedWith('INVALID_ROLE');
  });

  it('User workflows', async () => {
    await expect(roleManager.connect(deployer).grantProjectRole(projectId, accounts[0].address, activeRoleName))
      .to.emit(roleManager, 'GrantRole')
      .withArgs(projectId, activeRoleName, accounts[0].address);

    await expect(roleManager.connect(deployer).grantProjectRole(projectId, accounts[0].address, activeRoleName))
      .not.to.emit(roleManager, 'GrantRole')

    await expect(roleManager.connect(deployer).grantProjectRole(projectId, accounts[1].address, activeRoleName))
      .to.emit(roleManager, 'GrantRole')
      .withArgs(projectId, activeRoleName, accounts[1].address);

    await expect(roleManager.connect(deployer).grantProjectRole(projectId, accounts[0].address, anotherRoleName))
      .to.emit(roleManager, 'GrantRole')
      .withArgs(projectId, anotherRoleName, accounts[0].address);

    let projectUsers = await roleManager.connect(deployer).getProjectUsers(projectId, activeRoleName);
    expect(projectUsers.length).to.equal(2);

    await expect(roleManager.connect(deployer).grantProjectRole(projectId, accounts[0].address, invalidRoleName))
      .to.be.revertedWith('INVALID_ROLE()');

    expect(await roleManager.connect(deployer).confirmUserRole(projectId, accounts[0].address, anotherRoleName))
      .to.equal(true);

    let userRoles = await roleManager.connect(deployer).getUserRoles(projectId, accounts[0].address);
    expect(userRoles.length).to.equal(2);

    await expect(roleManager.confirmUserRole(projectId, accounts[0].address, invalidRoleName))
      .to.be.revertedWith('INVALID_ROLE()');

    await roleManager.connect(deployer).revokeProjectRole(projectId, accounts[0].address, activeRoleName);

    await roleManager.connect(deployer).revokeProjectRole(projectId, accounts[1].address, activeRoleName);

    await expect(roleManager.revokeProjectRole(projectId, accounts[0].address, invalidRoleName))
      .to.be.revertedWith('INVALID_ROLE()');

    userRoles = await roleManager.connect(deployer).getUserRoles(projectId, accounts[0].address);
    expect(userRoles.length).to.equal(1);

    projectUsers = await roleManager.connect(deployer).getProjectUsers(projectId, activeRoleName);
    expect(projectUsers.length).to.equal(0);

    projectUsers = await roleManager.connect(deployer).getProjectUsers(projectId, anotherRoleName);
    expect(projectUsers.length).to.equal(1);

    await expect(roleManager.connect(deployer).getProjectUsers(projectId, invalidRoleName))
      .to.be.revertedWith('INVALID_ROLE()');

    projectUsers = await roleManager.connect(deployer).getProjectUsers(anotherProjectId, activeRoleName);
    expect(projectUsers.length).to.equal(0);
  });
});

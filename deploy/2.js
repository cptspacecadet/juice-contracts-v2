const { ethers } = require('hardhat');

/**
 * Deploys a second version of many contracts for projects to migrate onto.
 *
 * Example usage:
 *
 * npx hardhat deploy --network rinkeby
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log("Deploying 2");

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let multisigAddress;
  let chainId = await getChainId();
  let baseDeployArgs = {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  };

  console.log({ deployer: deployer.address, chain: chainId });

  switch (chainId) {
    // mainnet
    case '1':
      multisigAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      break;
    // rinkeby
    case '4':
      multisigAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      break;
    // hardhat / localhost
    case '31337':
      multisigAddress = deployer.address;
      break;
  }

  console.log({ multisigAddress });

  // Reuse the JBOperatorStore contract.
  const JBOperatorStore = await deploy('JBOperatorStore', {
    ...baseDeployArgs,
    args: [],
  });

  // Reuse the JBPrices contract.
  const JBPrices = await deploy('JBPrices', {
    ...baseDeployArgs,
    args: [deployer.address],
  });

  // Reuse the JBProjects contract.
  const JBProjects = await deploy('JBProjects', {
    ...baseDeployArgs,
    args: [JBOperatorStore.address],
  });

  // Deploy a new JBETHERC20SplitsPayerDeployer contract.
  await deploy('JBETHERC20SplitsPayerDeployer_2', {
    ...baseDeployArgs,
    contract: "contracts/JBETHERC20SplitsPayerDeployer/2.sol:JBETHERC20SplitsPayerDeployer",
    args: [],
  });

  // Get the future address of JBFundingCycleStore
  const transactionCount = await deployer.getTransactionCount();

  const FundingCycleStoreFutureAddress = ethers.utils.getContractAddress({
    from: deployer.address,
    nonce: transactionCount + 1,
  });

  // Deploy a JBDirectory.
  const JBDirectory = await deploy('JBDirectory_2', {
    ...baseDeployArgs,
    contract: "contracts/JBDirectory.sol:JBDirectory",
    args: [
      JBOperatorStore.address,
      JBProjects.address,
      FundingCycleStoreFutureAddress,
      deployer.address,
    ],
  });

  // Deploy a JBFundingCycleStore.
  const JBFundingCycleStore = await deploy('JBFundingCycleStore_2', {
    ...baseDeployArgs,
    contract: "contracts/JBFundingCycleStore/2.sol:JBFundingCycleStore",
    args: [JBDirectory.address],
  });

  // Deploy a JB3DayReconfigurationBufferBallot.
  await deploy('JB3DayReconfigurationBufferBallot', {
    ...baseDeployArgs,
    contract: "contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot",
    args: [259200, JBFundingCycleStore.address],
  });

  // Deploy a JB7DayReconfigurationBufferBallot.
  await deploy('JB7DayReconfigurationBufferBallot', {
    ...baseDeployArgs,
    contract: "contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot",
    args: [604800, JBFundingCycleStore.address],
  });

  // Deploy a JBTokenStore.
  const JBTokenStore = await deploy('JBTokenStore_2', {
    ...baseDeployArgs,
    contract: "contracts/JBTokenStore.sol:JBTokenStore",
    args: [JBOperatorStore.address, JBProjects.address, JBDirectory.address],
  });

  // Deploy a JBSplitStore.
  const JBSplitStore = await deploy('JBSplitsStore_2', {
    ...baseDeployArgs,
    contract: "contracts/JBSplitsStore/2.sol:JBSplitsStore",
    args: [JBOperatorStore.address, JBProjects.address, JBDirectory.address],
  });

  // Deploy a JBController contract.
  const JBController = await deploy('JBController_2', {
    ...baseDeployArgs,
    contract: "contracts/JBController/2.sol:JBController",
    args: [
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBFundingCycleStore.address,
      JBTokenStore.address,
      JBSplitStore.address,
    ],
  });

  // Deploy a JBSingleTokenPaymentTerminalStore contract.
  const JBSingleTokenPaymentTerminalStore = await deploy('JBSingleTokenPaymentTerminalStore_2', {
    ...baseDeployArgs,
    contract: "contracts/JBSingleTokenPaymentTerminalStore/2.sol:JBSingleTokenPaymentTerminalStore",
    args: [JBDirectory.address, JBFundingCycleStore.address, JBPrices.address],
  });

  // Reuse the currencies library.
  const JBCurrencies = await deploy('JBCurrencies', {
    ...baseDeployArgs,
    args: [],
  });

  // Get references to contract that will have transactions triggered.
  const jbDirectoryContract = new ethers.Contract(JBDirectory.address, JBDirectory.abi);
  const jbCurrenciesLibrary = new ethers.Contract(JBCurrencies.address, JBCurrencies.abi);

  // Get a reference to USD and ETH currency indexes.
  const ETH = await jbCurrenciesLibrary.connect(deployer).ETH();

  // Deploy a JBETHPaymentTerminal contract.
  await deploy('JBETHPaymentTerminal_2', {
    ...baseDeployArgs,
    contract: "contracts/JBETHPaymentTerminal/2.sol:JBETHPaymentTerminal",
    args: [
      ETH,
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBSplitStore.address,
      JBPrices.address,
      JBSingleTokenPaymentTerminalStore.address,
      multisigAddress,
    ],
  });

  let isAllowedToSetFirstController = await jbDirectoryContract
    .connect(deployer)
    .isAllowedToSetFirstController(JBController.address);

  console.log({ isAllowedToSetFirstController });

  // If needed, allow the controller to set projects' first controller, then transfer the ownership of the JBDirectory to the multisig.
  if (!isAllowedToSetFirstController) {
    let tx = await jbDirectoryContract
      .connect(deployer)
      .setIsAllowedToSetFirstController(JBController.address, true);
    await tx.wait();
  }

  // If needed, transfer the ownership of the JBDirectory contract to the multisig.
  if ((await jbDirectoryContract.connect(deployer).owner()) != multisigAddress)
    await jbDirectoryContract.connect(deployer).transferOwnership(multisigAddress);

  console.log('Done');
};

module.exports.tags = ['2'];
module.exports.dependencies = ['1']; 
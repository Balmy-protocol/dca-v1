import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer, governor, feeRecipient } = await hre.getNamedAccounts();

  const uniswapOracle = await hre.deployments.get('UniswapOracle');
  const nftDescriptor = await hre.deployments.get('TokenDescriptor');

  await hre.deployments.deploy('GlobalParameters', {
    contract: 'contracts/DCAGlobalParameters/DCAGlobalParameters.sol:DCAGlobalParameters',
    from: deployer,
    args: [governor, feeRecipient, uniswapOracle.address, nftDescriptor.address],
    log: true,
  });
};
export default deployFunction;
deployFunction.tags = ['GlobalParameters'];
deployFunction.dependencies = ['TokenDescriptor', 'UniswapOracle'];

import { ethers } from 'hardhat';
import { abi as IERC20_ABI } from '@openzeppelin/contracts/build/contracts/IERC20Metadata.json';
import { BigNumber, utils } from 'ethers';
import zrx from './libraries/zrx';

const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
const YFI_ADDRESS = '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e';
const YFI_WETH_DCA_PAIR = '0xa649c9306896f90d6f8a3366f29be10557461144';

async function main() {
  const [deployer, governor] = await ethers.getSigners();
  console.log('governor', governor.address);
  const DCAZRXSwapper = await ethers.getContract('DCAZRXSwapper', governor);
  const DCAPair = await ethers.getContractAt('contracts/DCAPair/DCAPair.sol:DCAPair', YFI_WETH_DCA_PAIR, governor);
  const secondsUntilNextSwap = await DCAPair.secondsUntilNextSwap();
  console.log('Seconds until next swap', secondsUntilNextSwap);
  if (secondsUntilNextSwap == 0) {
    const { amountToBeProvidedBySwapper, amountToRewardSwapperWith, tokenToRewardSwapperWith, tokenToBeProvidedBySwapper } =
      await DCAPair.getNextSwapInfo();
    const tokenToBeRewardedWith = await ethers.getContractAt(IERC20_ABI, tokenToRewardSwapperWith);
    const tokenToBeRewardedWithDecimals = await tokenToBeRewardedWith.decimals();
    const tokenToBeRewardedWithSymbol = await tokenToBeRewardedWith.symbol();
    const tokenToProvide = await ethers.getContractAt(IERC20_ABI, tokenToBeProvidedBySwapper);
    const tokenToProvideDecimals = await tokenToProvide.decimals();
    const tokenToProvideSymbol = await tokenToProvide.symbol();
    console.log('*** sc needs ***');
    console.log('Provide', utils.formatUnits(amountToBeProvidedBySwapper, tokenToProvideDecimals), tokenToProvideSymbol);
    console.log('Reward', utils.formatUnits(amountToRewardSwapperWith, tokenToBeRewardedWithDecimals), tokenToBeRewardedWithSymbol);
    const quote = await zrx.quote({
      chainId: 1,
      sellToken: tokenToRewardSwapperWith,
      buyToken: tokenToBeProvidedBySwapper,
      sellAmount: amountToRewardSwapperWith,
      sippagePercentage: 0.001, // 0.1%
    });
    console.log('*** zrx ***');
    console.log('bought amount would be', utils.formatUnits(quote.buyAmount, tokenToProvideDecimals), tokenToProvideSymbol);
    console.log('*** ***');
    if (amountToBeProvidedBySwapper.gt(quote.buyAmount)) {
      const secondQuote = await zrx.quote({
        chainId: 1,
        sellToken: tokenToRewardSwapperWith,
        buyToken: tokenToBeProvidedBySwapper,
        buyAmount: amountToBeProvidedBySwapper,
        sippagePercentage: 0.01, // 0.1%
      });
      const missing = BigNumber.from(secondQuote.sellAmount).sub(amountToRewardSwapperWith);
      console.log('missing', utils.formatUnits(missing, tokenToBeRewardedWithDecimals), tokenToBeRewardedWithSymbol);
    } else {
      console.log('executing pair');
      const swapTx = await DCAZRXSwapper.swapPairs([[DCAPair.address, quote.data]], { gasPrice: utils.parseUnits('70', 'gwei') });
      console.log('tx hash:', swapTx.hash);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

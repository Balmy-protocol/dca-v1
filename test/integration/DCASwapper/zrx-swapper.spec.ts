import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { TransactionResponse, TransactionReceipt } from '@ethersproject/abstract-provider';
import { JsonRpcSigner } from '@ethersproject/providers';
import { BigNumber, Contract, utils } from 'ethers';
import { deployments, ethers, getNamedAccounts } from 'hardhat';
import { abi as IERC20_ABI } from '@openzeppelin/contracts/build/contracts/IERC20.json';
import { abi as SWAP_ROUTER_ABI } from '@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json';
import { getNodeUrl } from '../../../utils/network';
import { bn, constants, evm, wallet } from '../../utils';
import { contract, given, then, when } from '../../utils/bdd';
import globalParametersDeployFunction from '../../../deploy/004_global_parameters';
import { expect } from 'chai';
import zrx, { QuoteResponse } from '../../../scripts/libraries/zrx';

const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
const WETH_WHALE_ADDRESS = '0xf04a5cc80b1e94c69b48f5ee68a08cd2f09a7c3e';
const USDC_ADDRESS = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
const USDC_WHALE_ADDRESS = '0x0a59649758aa4d66e25f08dd01271e891fe52199';

const UNISWAP_SWAP_ROUTER_ADDRESS = '0xE592427A0AEce92De3Edee1F18E0157C05861564';

const CALCULATE_FEE = (bn: BigNumber) => bn.mul(6).div(1000);
const APPLY_FEE = (bn: BigNumber) => bn.sub(CALCULATE_FEE(bn));

contract('DCAZRXSwapper', () => {
  let DCAZRXSwapper: Contract;
  let DCAFactory: Contract;
  let DCAPair: Contract;
  let WETH: Contract;
  let USDC: Contract;
  let oracle: Contract;

  let uniswapSwapRouter: Contract;

  let governor: JsonRpcSigner;
  let wethWhale: JsonRpcSigner;
  let usdcWhale: JsonRpcSigner;
  let cindy: SignerWithAddress;
  let alice: SignerWithAddress;
  let feeRecipient: string;

  let snapshotId: string;

  const RATE = utils.parseEther('0.1');
  const AMOUNT_OF_SWAPS = 10;
  const INTERVAL = globalParametersDeployFunction.intervals[0];

  before(async () => {
    [cindy, alice] = await ethers.getSigners();

    await evm.reset({
      jsonRpcUrl: getNodeUrl('mainnet'),
    });

    uniswapSwapRouter = await ethers.getContractAt(SWAP_ROUTER_ABI, UNISWAP_SWAP_ROUTER_ADDRESS);

    await deployments.fixture(['Factory', 'DCAZRXSwapper'], { keepExistingDeployments: false });

    const namedAccounts = await getNamedAccounts();
    feeRecipient = namedAccounts.feeRecipient;
    const governorAddress = namedAccounts.governor;
    governor = await wallet.impersonate(governorAddress);

    DCAZRXSwapper = await ethers.getContract('DCAZRXSwapper', governor);
    DCAFactory = await ethers.getContract('Factory');
    oracle = await ethers.getContract('UniswapOracle');

    const pairAddress = await DCAFactory.callStatic.createPair(WETH_ADDRESS, USDC_ADDRESS);
    await DCAFactory.createPair(WETH_ADDRESS, USDC_ADDRESS);
    DCAPair = await ethers.getContractAt('contracts/DCAPair/DCAPair.sol:DCAPair', pairAddress);

    WETH = await ethers.getContractAt(IERC20_ABI, WETH_ADDRESS);
    USDC = await ethers.getContractAt(IERC20_ABI, USDC_ADDRESS);
    wethWhale = await wallet.impersonate(WETH_WHALE_ADDRESS);
    usdcWhale = await wallet.impersonate(USDC_WHALE_ADDRESS);

    await WETH.connect(wethWhale).transfer(cindy.address, utils.parseEther('100000'), { gasPrice: 0 });
    await USDC.connect(usdcWhale).transfer(alice.address, utils.parseUnits('100000', 6), { gasPrice: 0 });

    await WETH.connect(cindy).approve(DCAPair.address, RATE.mul(AMOUNT_OF_SWAPS));
    await DCAPair.connect(cindy).deposit(WETH.address, RATE, AMOUNT_OF_SWAPS, INTERVAL);

    snapshotId = await evm.snapshot.take();
  });

  beforeEach(async () => {
    await evm.snapshot.revert(snapshotId);
  });

  describe('swap', () => {
    when('twap price < uni price => allows for profitable swap', () => {
      let twapPrice: BigNumber;
      let amountToRewardSwapperWith: BigNumber;
      let zrxQuote: QuoteResponse;
      let initialFeeRecipientBalance: BigNumber;
      let swapTx: TransactionResponse;

      given(async () => {
        initialFeeRecipientBalance = await USDC.balanceOf(feeRecipient);
        await evm.advanceTimeAndBlock(await DCAPair.secondsUntilNextSwap());
        ({ amountToRewardSwapperWith } = await DCAPair.getNextSwapInfo());
        zrxQuote = await zrx.quote({
          chainId: 1,
          sellToken: WETH_ADDRESS,
          buyToken: USDC_ADDRESS,
          sellAmount: amountToRewardSwapperWith,
          sippagePercentage: 0.001, // 0.1%
        });
        twapPrice = await oracle.quote(WETH.address, RATE, USDC.address);
        await WETH.connect(wethWhale).approve(uniswapSwapRouter.address, constants.MAX_UINT_256, { gasPrice: 0 });
        swapTx = await DCAZRXSwapper.connect(governor).swapPairs([[DCAPair.address, zrxQuote.data]], { gasPrice: 0 });
      });
      then('swap is executed', async () => {
        expect(await DCAPair.performedSwaps(INTERVAL)).to.equal(1);
      });
      then('pair balance is correct', async () => {
        expect(await WETH.balanceOf(DCAPair.address)).to.equal(RATE.mul(AMOUNT_OF_SWAPS - 1));
        bn.expectToEqualWithThreshold({
          value: await USDC.balanceOf(DCAPair.address),
          to: APPLY_FEE(twapPrice),
          threshold: 1,
        });
      });
      then('all usdc surpluss is sent to fee recipient', async () => {
        const txReceipt = await swapTx.wait(0);
        const boughtAmount = await boughtAmountFromZRXTrade(txReceipt);
        const swappedEvent = await getSwappedEvent(txReceipt);
        const amountToBeProvidedBySwapper = swappedEvent.args._nextSwapInformation.amountToBeProvidedBySwapper;
        const surpluss = boughtAmount.sub(amountToBeProvidedBySwapper);
        const delta = (await USDC.balanceOf(feeRecipient)).sub(initialFeeRecipientBalance);
        bn.expectToEqualWithThreshold({
          value: delta,
          to: surpluss,
          threshold: surpluss.div(100), // 1%
        });
        expect(await WETH.balanceOf(feeRecipient)).to.equal(0);
      });
    });
  });

  async function boughtAmountFromZRXTrade(txReceipt: TransactionReceipt): Promise<BigNumber> {
    const logs = txReceipt.logs;
    for (let i = 0; i < logs.length; i++) {
      for (let x = 0; x < logs[i].topics.length; x++) {
        if (logs[i].topics[x] === USDC.interface.getEventTopic('Transfer')) {
          const parsedLog = USDC.interface.parseLog(logs[i]);
          if (parsedLog.args.from == DCAZRXSwapper.address && parsedLog.args.to == DCAPair.address) {
            return BigNumber.from(parsedLog.args.value);
          }
        }
      }
    }
    return Promise.reject();
  }

  async function getSwappedEvent(txReceipt: TransactionReceipt): Promise<utils.LogDescription> {
    const logs = txReceipt.logs;
    for (let i = 0; i < logs.length; i++) {
      for (let x = 0; x < logs[i].topics.length; x++) {
        if (logs[i].topics[x] === DCAPair.interface.getEventTopic('Swapped')) {
          const parsedLog = DCAPair.interface.parseLog(logs[i]);
          return parsedLog;
        }
      }
    }
    return Promise.reject();
  }
});

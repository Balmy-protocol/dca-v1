import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { TransactionResponse, TransactionReceipt } from '@ethersproject/abstract-provider';
import { JsonRpcSigner } from '@ethersproject/providers';
import { BigNumber, BytesLike, Contract, utils } from 'ethers';
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
const YFI_ADDRESS = '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e';

const YFI_WETH_DCA_PAIR = '0xa649c9306896f90d6f8a3366f29be10557461144';

const CALCULATE_FEE = (bn: BigNumber) => bn.mul(6).div(1000);
const APPLY_FEE = (bn: BigNumber) => bn.sub(CALCULATE_FEE(bn));

contract('DCAZRXSwapper', () => {
  let DCAZRXSwapper: Contract;
  let DCAPair: Contract;
  let WETH: Contract;
  let YFI: Contract;

  let governor: JsonRpcSigner;

  let feeRecipient: string;
  let snapshotId: string;

  before(async () => {
    await evm.reset({
      jsonRpcUrl: getNodeUrl('mainnet'),
    });

    await deployments.fixture(['DCAZRXSwapper']);

    const namedAccounts = await getNamedAccounts();
    feeRecipient = namedAccounts.feeRecipient;
    const governorAddress = namedAccounts.governor;
    governor = await wallet.impersonate(governorAddress);

    DCAZRXSwapper = await ethers.getContract('DCAZRXSwapper', governor);

    DCAPair = await ethers.getContractAt('contracts/DCAPair/DCAPair.sol:DCAPair', YFI_WETH_DCA_PAIR);

    WETH = await ethers.getContractAt(IERC20_ABI, WETH_ADDRESS);
    YFI = await ethers.getContractAt(IERC20_ABI, YFI_ADDRESS);

    snapshotId = await evm.snapshot.take();
  });

  beforeEach(async () => {
    await evm.snapshot.revert(snapshotId);
  });

  describe('swap', () => {
    when.skip('yfi/weth didnt execute', () => {
      let tokenToRewardSwapperWith: string;
      let tokenToBeProvidedBySwapper: string;
      let amountToRewardSwapperWith: BigNumber;
      let toBeProvidedToken: Contract;
      let zrxQuote: QuoteResponse;
      let initialFeeRecipientBalance: BigNumber;
      let swapTx: TransactionResponse;

      given(async () => {
        await evm.advanceTimeAndBlock(await DCAPair.secondsUntilNextSwap());
        ({ amountToRewardSwapperWith, tokenToRewardSwapperWith, tokenToBeProvidedBySwapper } = await DCAPair.getNextSwapInfo());
        toBeProvidedToken = tokenToBeProvidedBySwapper == YFI_ADDRESS ? YFI : WETH;
        initialFeeRecipientBalance = await toBeProvidedToken.balanceOf(feeRecipient);
        zrxQuote = await zrx.quote({
          chainId: 1,
          sellToken: tokenToRewardSwapperWith,
          buyToken: tokenToBeProvidedBySwapper,
          sellAmount: amountToRewardSwapperWith,
          sippagePercentage: 0.001, // 0.1%
        });
        swapTx = await DCAZRXSwapper.connect(governor).swapPairs([[DCAPair.address, zrxQuote.data]], { gasPrice: 0 });
      });
      then('all surpluss is sent to fee recipient', async () => {
        const txReceipt = await swapTx.wait(0);
        const boughtAmount = await boughtAmountFromZRXTrade(txReceipt);
        const swappedEvent = await getSwappedEvent(txReceipt);
        const amountToBeProvidedBySwapper = swappedEvent.args._nextSwapInformation.amountToBeProvidedBySwapper;
        const surpluss = boughtAmount.sub(amountToBeProvidedBySwapper);
        const delta = (await toBeProvidedToken.balanceOf(feeRecipient)).sub(initialFeeRecipientBalance);
        bn.expectToEqualWithThreshold({
          value: delta,
          to: surpluss,
          threshold: surpluss.div(100), // 1%
        });
      });
    });
  });

  async function boughtAmountFromZRXTrade(txReceipt: TransactionReceipt): Promise<BigNumber> {
    const logs = txReceipt.logs;
    for (let i = 0; i < logs.length; i++) {
      for (let x = 0; x < logs[i].topics.length; x++) {
        if (logs[i].topics[x] === YFI.interface.getEventTopic('Transfer')) {
          const parsedLog = YFI.interface.parseLog(logs[i]);
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

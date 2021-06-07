import moment from 'moment';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory, utils } from 'ethers';
import { ethers } from 'hardhat';
import { TransactionResponse } from '@ethersproject/abstract-provider';
import { constants, erc20, behaviours, evm, bn } from '../../utils';
import { given, then, when } from '../../utils/bdd';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TokenContract } from '../../utils/erc20';
import { readArgFromEventOrFail } from '../../utils/event-utils';

describe.only('DCAPair', () => {
  let governor: SignerWithAddress;
  let dude: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let tokenA: TokenContract, tokenB: TokenContract;
  let DCAPairFactory: ContractFactory;
  let DCAPair: Contract;
  let DCAGlobalParametersFactory: ContractFactory;
  let DCAGlobalParameters: Contract;
  let reentrantDCAPairLoanCalleeFactory: ContractFactory;
  const swapInterval = moment.duration(10, 'minutes').as('seconds');

  before('Setup accounts and contracts', async () => {
    [governor, dude, feeRecipient] = await ethers.getSigners();
    DCAGlobalParametersFactory = await ethers.getContractFactory(
      'contracts/mocks/DCAGlobalParameters/DCAGlobalParameters.sol:DCAGlobalParametersMock'
    );
    DCAPairFactory = await ethers.getContractFactory('contracts/DCAPair/DCAPair.sol:DCAPair');
    reentrantDCAPairLoanCalleeFactory = await ethers.getContractFactory('contracts/mocks/DCAPairLoanCallee.sol:ReentrantDCAPairLoanCalleeMock');
  });

  beforeEach('Deploy and configure', async () => {
    await evm.reset();
    tokenA = await erc20.deploy({
      name: 'tokenA',
      symbol: 'TKNA',
    });
    tokenB = await erc20.deploy({
      name: 'tokenB',
      symbol: 'TKNB',
    });
    DCAGlobalParameters = await DCAGlobalParametersFactory.deploy(governor.address, feeRecipient.address, constants.NOT_ZERO_ADDRESS);
    DCAPair = await DCAPairFactory.deploy(DCAGlobalParameters.address, tokenA.address, tokenB.address, swapInterval);
  });

  describe.only('loan', () => {
    const rateTokenA = 50;
    const swapsTokenA = 13;
    let totalTokenA: BigNumber;

    given(async () => {
      totalTokenA = tokenA.asUnits(rateTokenA).mul(swapsTokenA);
      await deposit({
        token: () => tokenA,
        depositor: dude,
        rate: rateTokenA,
        swaps: swapsTokenA,
      });
    });

    when('trying to do a reentrancy attack through a deposit', () => {
      let reentrantDCAPairLoanCallee: Contract;
      let loanTx: Promise<TransactionResponse>;
      given(async () => {
        reentrantDCAPairLoanCallee = await reentrantDCAPairLoanCalleeFactory.deploy('deposit');
        loanTx = DCAPair.loan(totalTokenA.sub(1), 0, reentrantDCAPairLoanCallee.address, '0x');
      });
      then('tx is reverted', async () => {
        await expect(loanTx).to.be.revertedWith('ReentrancyGuard: reentrant call');
      });
    });

    when('trying to do a reentrancy attack through withdrawing swapped', () => {
      let reentrantDCAPairLoanCallee: Contract;
      let loanTx: Promise<TransactionResponse>;
      given(async () => {
        reentrantDCAPairLoanCallee = await reentrantDCAPairLoanCalleeFactory.deploy('withdrawSwapped');
        loanTx = DCAPair.loan(totalTokenA.sub(1), 0, reentrantDCAPairLoanCallee.address, '0x');
      });
      then('tx is reverted', async () => {
        await expect(loanTx).to.be.revertedWith('ReentrancyGuard: reentrant call');
      });
    });

    when('trying to do a reentrancy attack through withdrawing swapped many', () => {
      then('non reentrant');
    });

    when('trying to do a reentrancy attack through modifying rate', () => {
      then('non reentrant');
    });

    when('trying to do a reentrancy attack through modifying swaps', () => {
      then('non reentrant');
    });

    when('trying to do a reentrancy attack through modifying rate and swaps', () => {
      then('non reentrant');
    });

    when('trying to do a reentrancy attack through addFundsToPosition', () => {
      then('non reentrant');
    });

    when('trying to do a reentrancy attack through terminate', () => {
      then('non reentrant');
    });
  });

  async function deposit({
    token,
    depositor,
    rate,
    swaps,
  }: {
    token: () => TokenContract;
    depositor: SignerWithAddress;
    rate: number;
    swaps: number;
  }) {
    await token().mint(depositor.address, token().asUnits(rate).mul(swaps));
    await token().connect(depositor).approve(DCAPair.address, token().asUnits(rate).mul(swaps));
    const response: TransactionResponse = await DCAPair.connect(depositor).deposit(token().address, token().asUnits(rate), swaps);
    const dcaId = await readArgFromEventOrFail<BigNumber>(response, 'Deposited', '_dcaId');
    return { response, dcaId };
  }
});

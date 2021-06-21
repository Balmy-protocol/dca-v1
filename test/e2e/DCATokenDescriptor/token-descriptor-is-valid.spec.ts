import moment from 'moment';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory, utils } from 'ethers';
import { ethers } from 'hardhat';
import { TransactionResponse } from '@ethersproject/abstract-provider';
import { constants, erc20, behaviours, evm, bn } from '../../utils';
import { given, then, when, contract } from '../../utils/bdd';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TokenContract } from '../../utils/erc20';
import { readArgFromEventOrFail } from '../../utils/event-utils';

contract('DCATokenDescriptor', () => {
  describe('TBD', () => {
    let governor: SignerWithAddress;
    let dude: SignerWithAddress;
    let feeRecipient: SignerWithAddress;
    let tokenA: TokenContract, tokenB: TokenContract;
    let DCAPairContract: ContractFactory;
    let DCAPair: Contract;
    let DCAGlobalParametersContract: ContractFactory;
    let DCAGlobalParameters: Contract;
    let DCATokenDescriptorContract: ContractFactory;
    let DCATokenDescriptor: Contract;
    let staticSlidingOracleContract: ContractFactory;
    let staticSlidingOracle: Contract;
    const swapInterval = moment.duration(10, 'minutes').as('seconds');

    before('Setup accounts and contracts', async () => {
      [dude, governor, feeRecipient] = await ethers.getSigners();
      DCAGlobalParametersContract = await ethers.getContractFactory('contracts/DCAGlobalParameters/DCAGlobalParameters.sol:DCAGlobalParameters');
      DCAPairContract = await ethers.getContractFactory('contracts/DCAPair/DCAPair.sol:DCAPair');
      DCATokenDescriptorContract = await ethers.getContractFactory('contracts/DCATokenDescriptor/DCATokenDescriptor.sol:DCATokenDescriptor');

      staticSlidingOracleContract = await ethers.getContractFactory('contracts/mocks/StaticSlidingOracle.sol:StaticSlidingOracle');
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
      staticSlidingOracle = await staticSlidingOracleContract.deploy(tokenA.asUnits(1), tokenA.amountOfDecimals); // Rate is 1 token A = 1 token B
      DCATokenDescriptor = await DCATokenDescriptorContract.deploy();
      DCAGlobalParameters = await DCAGlobalParametersContract.deploy(governor.address, feeRecipient.address, DCATokenDescriptor.address);
      DCAPair = await DCAPairContract.deploy(DCAGlobalParameters.address, staticSlidingOracle.address, tokenA.address, tokenB.address);
      await DCAGlobalParameters.addSwapIntervalsToAllowedList([swapInterval], ['NULL']);
    });

    describe.only('TBD', () => {
      it('TBD', async () => {
        // Deposit
        const tokenId = await DCAPair.deposit(tokenA.address, tokenA.asUnits(10), 20, swapInterval);

        // Move forward

        // tokenUri
        const result = await DCAPair.tokenUri(tokenId);
        console.log(result);
      });
    });
  });
});

import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { TransactionResponse } from '@ethersproject/abstract-provider';
import { ethers } from 'hardhat';
import { constants, behaviours, bn, contracts } from '../../utils';
import { given, then, when } from '../../utils/bdd';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';

describe('DCASwapper', () => {
  let owner: SignerWithAddress;
  let DCASwapperContract: ContractFactory;
  let DCASwapper: Contract;

  before('Setup accounts and contracts', async () => {
    [owner] = await ethers.getSigners();
    DCASwapperContract = await ethers.getContractFactory('contracts/mocks/DCASwapper/DCASwapper.sol:DCASwapperMock');
  });

  beforeEach('Deploy and configure', async () => {
    DCASwapper = await DCASwapperContract.deploy(owner.address);
  });

  describe('startWatchingPairs', () => {
    when('one of the pairs is zero address', () => {
      then('tx is reverted with reason', async () => {
        await behaviours.txShouldRevertWithMessage({
          contract: DCASwapper,
          func: 'startWatchingPairs',
          args: [[constants.NOT_ZERO_ADDRESS, constants.ZERO_ADDRESS]],
          message: 'ZeroAddress',
        });
        await behaviours.txShouldRevertWithMessage({
          contract: DCASwapper,
          func: 'startWatchingPairs',
          args: [[constants.ZERO_ADDRESS, constants.NOT_ZERO_ADDRESS]],
          message: 'ZeroAddress',
        });
      });
    });
    when('pairs are not zero', () => {
      const ADDRESSES = ['0x0000000000000000000000000000000000000001', '0x0000000000000000000000000000000000000002'];
      let tx: TransactionResponse;

      given(async () => {
        tx = await DCASwapper.startWatchingPairs(ADDRESSES);
      });

      then('pairs are added', async () => {
        expect(await DCASwapper.watchedPairs()).to.eql(ADDRESSES);
      });

      then('event is emmitted', async () => {
        await expect(tx).to.emit(DCASwapper, 'WatchingNewPairs').withArgs(ADDRESSES);
      });
    });
    behaviours.shouldBeExecutableOnlyByGovernor({
      contract: () => DCASwapper,
      funcAndSignature: 'startWatchingPairs(address[])',
      params: [[constants.NOT_ZERO_ADDRESS]],
      governor: () => owner,
    });
  });
  describe('stopWatchingPairs', () => {
    given(async () => {
      await DCASwapper.startWatchingPairs([constants.NOT_ZERO_ADDRESS]);
    });
    when('address being watch is removed', () => {
      let tx: TransactionResponse;

      given(async () => {
        tx = await DCASwapper.stopWatchingPairs([constants.NOT_ZERO_ADDRESS]);
      });

      then('event is emitted', async () => {
        await expect(tx).to.emit(DCASwapper, 'StoppedWatchingPairs').withArgs([constants.NOT_ZERO_ADDRESS]);
      });
      then('pair is no longer watched', async () => {
        expect(await DCASwapper.watchedPairs()).to.be.empty;
      });
    });
    behaviours.shouldBeExecutableOnlyByGovernor({
      contract: () => DCASwapper,
      funcAndSignature: 'stopWatchingPairs(address[])',
      params: [[constants.NOT_ZERO_ADDRESS]],
      governor: () => owner,
    });
  });
});

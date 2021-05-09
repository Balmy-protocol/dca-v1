import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';
import { TransactionResponse } from '@ethersproject/abstract-provider';
import { constants, behaviours, wallet, contracts } from '../../utils';
import { given, then, when } from '../../utils/bdd';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

describe('Governable', function () {
  let governor: SignerWithAddress;
  let governableContract: ContractFactory;
  let governable: Contract;

  before('Setup accounts and contracts', async () => {
    [governor] = await ethers.getSigners();
    governableContract = await ethers.getContractFactory('contracts/mocks/utils/Governable.sol:GovernableMock');
  });

  beforeEach('Deploy and configure', async () => {
    governable = await governableContract.deploy(governor.address);
  });

  describe('constructor', () => {
    when('initializing with governor as zero address', () => {
      then('deployment is reverted with reason', async () => {
        await behaviours.deployShouldRevertWithZeroAddress({
          contract: governableContract,
          args: [constants.ZERO_ADDRESS],
        });
      });
    });
    when('initialized with a governor thats not zero address', () => {
      let deploymentTx: TransactionResponse;
      let deployedContract: Contract;
      given(async () => {
        const deployment = await contracts.deploy(governableContract, [governor.address]);
        deploymentTx = deployment.tx;
        deployedContract = deployment.contract;
      });
      then('deployment is succesful', async () => {
        await expect(deploymentTx.wait()).to.not.be.reverted;
      });
      then('governor is set correctly', async () => {
        expect(await deployedContract.governor()).to.equal(governor.address);
      });
    });
  });

  describe('setPendingGovernor', () => {
    when('pending governor is zero address', () => {
      let setPendingGovernorTx: Promise<TransactionResponse>;
      given(async () => {
        setPendingGovernorTx = governable.setPendingGovernor(constants.ZERO_ADDRESS);
      });
      then('tx is reverted with reason', async () => {
        await expect(setPendingGovernorTx).to.be.revertedWith('Governable: zero address');
      });
    });
    when('pending governor is not zero address', () => {
      let setPendingGovernorTx: TransactionResponse;
      let pendingGovernor: string;
      given(async () => {
        pendingGovernor = await wallet.generateRandomAddress();
        setPendingGovernorTx = await governable.setPendingGovernor(pendingGovernor);
      });
      then('sets pending governor', async () => {
        expect(await governable.pendingGovernor()).to.be.equal(pendingGovernor);
      });
      then('emits event with correct argument', async () => {
        await expect(setPendingGovernorTx).to.emit(governable, 'PendingGovernorSet').withArgs(pendingGovernor);
      });
    });
  });
  describe('acceptPendingGovernor', () => {
    when('there is no pending governor', () => {
      let acceptPendingGovernorTx: Promise<TransactionResponse>;
      given(async () => {
        acceptPendingGovernorTx = governable.acceptPendingGovernor();
      });
      then('tx is reverted with reason', async () => {
        await expect(acceptPendingGovernorTx).to.be.revertedWith('Governable: no pending governor');
      });
    });
    when('there is a pending governor', () => {
      let acceptPendingGovernorTx: TransactionResponse;
      let pendingGovernor: string;
      given(async () => {
        pendingGovernor = await wallet.generateRandomAddress();
        await governable.setPendingGovernor(pendingGovernor);
        acceptPendingGovernorTx = await governable.acceptPendingGovernor();
      });
      then('pending governor becomes governor', async () => {
        expect(await governable.governor()).to.equal(pendingGovernor);
      });
      then('pending governor is set to zero', async () => {
        expect(await governable.pendingGovernor()).to.equal(constants.ZERO_ADDRESS);
      });
      then('emits event', async () => {
        await expect(acceptPendingGovernorTx).to.emit(governable, 'PendingGovernorAccepted');
      });
    });
  });
  describe('isGovernor', () => {
    when('not querying for governor address', () => {
      then('returns false', async () => {
        expect(await governable.isGovernor(await wallet.generateRandomAddress())).to.be.false;
      });
    });
    when('querying for governor address', () => {
      then('returns true', async () => {
        expect(await governable.isGovernor(governor.address)).to.be.true;
      });
    });
  });
  describe('isPendingGovernor', () => {
    when('not querying for pending governor address', () => {
      then('returns false', async () => {
        expect(await governable.isPendingGovernor(await wallet.generateRandomAddress())).to.be.false;
      });
    });
    when('querying for pending governor address', () => {
      let pendingGovernor: string;
      given(async () => {
        pendingGovernor = await wallet.generateRandomAddress();
        await governable.setPendingGovernor(pendingGovernor);
      });
      then('returns true', async () => {
        expect(await governable.isPendingGovernor(pendingGovernor)).to.be.true;
      });
    });
  });
  describe('onlyGovernor', () => {
    when('not called from governor', () => {
      let onlyGovernorAllowedTx: Promise<TransactionResponse>;
      given(async () => {
        const notGovernor = await wallet.generateRandom();
        onlyGovernorAllowedTx = governable.connect(notGovernor).onlyGovernorAllowed({ gasPrice: 0 });
      });
      then('tx is reverted with reason', async () => {
        await expect(onlyGovernorAllowedTx).to.be.revertedWith('Governable: only governor');
      });
    });
    when('called from governor', () => {
      let onlyGovernorAllowedTx: Promise<TransactionResponse>;
      given(async () => {
        onlyGovernorAllowedTx = governable.connect(governor).onlyGovernorAllowed({ gasPrice: 0 });
      });
      then('tx is not reverted', async () => {
        await expect(onlyGovernorAllowedTx).to.not.be.reverted;
      });
    });
  });
  describe('onlyPendingGovernor', () => {
    when('not called from pending governor', () => {
      let onlyPendingGovernorAllowedTx: Promise<TransactionResponse>;
      given(async () => {
        onlyPendingGovernorAllowedTx = governable.connect(governor).onlyPendingGovernorAllowed({ gasPrice: 0 });
      });
      then('tx is reverted with reason', async () => {
        await expect(onlyPendingGovernorAllowedTx).to.be.revertedWith('Governable: only pending governor');
      });
    });
    when('called from pending governor', () => {
      let onlyPendingGovernorAllowedTx: Promise<TransactionResponse>;
      given(async () => {
        const pendingGovernor = await wallet.generateRandom();
        await governable.setPendingGovernor(pendingGovernor.address);
        onlyPendingGovernorAllowedTx = governable.connect(pendingGovernor).onlyPendingGovernorAllowed({ gasPrice: 0 });
      });
      then('tx is not reverted', async () => {
        await expect(onlyPendingGovernorAllowedTx).to.not.be.reverted;
      });
    });
  });
});

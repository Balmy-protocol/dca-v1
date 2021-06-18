// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.4;
pragma abicoder v2;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interfaces/ISlidingOracle.sol';
import '../interfaces/IDCAPairSwapCallee.sol';
import './utils/CommonErrors.sol';
import './DCAPairParameters.sol';

abstract contract DCAPairSwapHandler is ReentrancyGuard, DCAPairParameters, IDCAPairSwapHandler {
  using SafeERC20 for IERC20Detailed;

  mapping(uint32 => mapping(address => uint256)) public override swapAmountAccumulator; // swap interval => from token => swap amount accum

  mapping(uint32 => uint32) public override lastSwapPerformed;
  ISlidingOracle public override oracle;

  error WithinInterval();

  constructor(ISlidingOracle _oracle) {
    if (address(_oracle) == address(0)) revert CommonErrors.ZeroAddress();
    oracle = _oracle;
  }

  function _addNewRatePerUnit(
    uint32 _swapInterval,
    address _address,
    uint32 _performedSwap,
    uint256 _ratePerUnit
  ) internal {
    uint256 _accumRatesPerUnitPreviousSwap = _accumRatesPerUnit[_swapInterval][_address][_performedSwap - 1];
    _accumRatesPerUnit[_swapInterval][_address][_performedSwap] = _accumRatesPerUnitPreviousSwap + _ratePerUnit;
  }

  function _registerSwap(
    uint32 _swapInterval,
    address _token,
    uint256 _internalAmountUsedToSwap,
    uint256 _ratePerUnit,
    uint32 _swapToRegister
  ) internal {
    swapAmountAccumulator[_swapInterval][_token] = _internalAmountUsedToSwap;
    _addNewRatePerUnit(_swapInterval, _token, _swapToRegister, _ratePerUnit);
    delete swapAmountDelta[_swapInterval][_token][_swapToRegister];
  }

  function _getAmountToSwap(
    uint32 _swapInterval,
    address _address,
    uint32 _swapToPerform
  ) internal view returns (uint256 _swapAmountAccumulator) {
    unchecked {
      _swapAmountAccumulator =
        swapAmountAccumulator[_swapInterval][_address] +
        uint256(swapAmountDelta[_swapInterval][_address][_swapToPerform]);
    }
  }

  function _convertTo(
    uint256 _fromTokenMagnitude,
    uint256 _amountFrom,
    uint256 _rateFromTo
  ) internal pure returns (uint256 _amountTo) {
    _amountTo = (_amountFrom * _rateFromTo) / _fromTokenMagnitude;
  }

  function getNextSwapInfo(uint32 _swapInterval) public view override returns (NextSwapInformation memory _nextSwapInformation) {
    uint32 _swapFee = globalParameters.swapFee();
    _nextSwapInformation = _getNextSwapInfo(_swapInterval, _swapFee);
  }

  function _getNextSwapInfo(uint32 _swapInterval, uint32 _swapFee) internal view returns (NextSwapInformation memory _nextSwapInformation) {
    _nextSwapInformation.swapToPerform = performedSwaps[_swapInterval] + 1;
    _nextSwapInformation.amountToSwapTokenA = _getAmountToSwap(_swapInterval, address(tokenA), _nextSwapInformation.swapToPerform);
    _nextSwapInformation.amountToSwapTokenB = _getAmountToSwap(_swapInterval, address(tokenB), _nextSwapInformation.swapToPerform);
    // TODO: Instead of using current, it should use quote to get a moving average and not current?
    _nextSwapInformation.ratePerUnitBToA = oracle.current(address(tokenB), _magnitudeB, address(tokenA));
    _nextSwapInformation.ratePerUnitAToB = (_magnitudeB * _magnitudeA) / _nextSwapInformation.ratePerUnitBToA;

    uint256 _amountOfTokenAIfTokenBSwapped = _convertTo(
      _magnitudeB,
      _nextSwapInformation.amountToSwapTokenB,
      _nextSwapInformation.ratePerUnitBToA
    );

    if (_amountOfTokenAIfTokenBSwapped < _nextSwapInformation.amountToSwapTokenA) {
      _nextSwapInformation.tokenToBeProvidedBySwapper = tokenB;
      _nextSwapInformation.tokenToRewardSwapperWith = tokenA;
      uint256 _tokenASurplus = _nextSwapInformation.amountToSwapTokenA - _amountOfTokenAIfTokenBSwapped;
      _nextSwapInformation.amountToBeProvidedBySwapper = _convertTo(_magnitudeA, _tokenASurplus, _nextSwapInformation.ratePerUnitAToB);
      _nextSwapInformation.amountToRewardSwapperWith = _tokenASurplus + _getFeeFromAmount(_swapFee, _tokenASurplus);
      _nextSwapInformation.platformFeeTokenA = _getFeeFromAmount(_swapFee, _amountOfTokenAIfTokenBSwapped);
      _nextSwapInformation.platformFeeTokenB = _getFeeFromAmount(_swapFee, _nextSwapInformation.amountToSwapTokenB);
      _nextSwapInformation.availableToBorrowTokenA = _balances[address(tokenA)] - _nextSwapInformation.amountToRewardSwapperWith;
      _nextSwapInformation.availableToBorrowTokenB = _balances[address(tokenB)];
    } else if (_amountOfTokenAIfTokenBSwapped > _nextSwapInformation.amountToSwapTokenA) {
      _nextSwapInformation.tokenToBeProvidedBySwapper = tokenA;
      _nextSwapInformation.tokenToRewardSwapperWith = tokenB;
      _nextSwapInformation.amountToBeProvidedBySwapper = _amountOfTokenAIfTokenBSwapped - _nextSwapInformation.amountToSwapTokenA;
      uint256 _amountToBeProvidedConvertedToB = _convertTo(
        _magnitudeA,
        _nextSwapInformation.amountToBeProvidedBySwapper,
        _nextSwapInformation.ratePerUnitAToB
      );
      _nextSwapInformation.amountToRewardSwapperWith =
        _amountToBeProvidedConvertedToB +
        _getFeeFromAmount(_swapFee, _amountToBeProvidedConvertedToB);
      _nextSwapInformation.platformFeeTokenA = _getFeeFromAmount(_swapFee, _nextSwapInformation.amountToSwapTokenA);
      _nextSwapInformation.platformFeeTokenB = _getFeeFromAmount(
        _swapFee,
        _nextSwapInformation.amountToSwapTokenB - _amountToBeProvidedConvertedToB
      );
      _nextSwapInformation.availableToBorrowTokenA = _balances[address(tokenA)];
      _nextSwapInformation.availableToBorrowTokenB = _balances[address(tokenB)] - _nextSwapInformation.amountToRewardSwapperWith;
    } else {
      _nextSwapInformation.platformFeeTokenA = _getFeeFromAmount(_swapFee, _nextSwapInformation.amountToSwapTokenA);
      _nextSwapInformation.platformFeeTokenB = _getFeeFromAmount(_swapFee, _nextSwapInformation.amountToSwapTokenB);
      _nextSwapInformation.availableToBorrowTokenA = _balances[address(tokenA)];
      _nextSwapInformation.availableToBorrowTokenB = _balances[address(tokenB)];
    }
  }

  function swap(uint32 _swapInterval) public override {
    swap(_swapInterval, 0, 0, msg.sender, '');
  }

  function swap(
    uint32 _swapInterval,
    uint256 _amountToBorrowTokenA,
    uint256 _amountToBorrowTokenB,
    address _to,
    bytes memory _data
  ) public override nonReentrant {
    IDCAGlobalParameters.SwapParameters memory _swapParameters = globalParameters.swapParameters();
    if (_swapParameters.isPaused) revert CommonErrors.Paused();
    if (lastSwapPerformed[_swapInterval] / _swapInterval >= _getTimestamp() / _swapInterval) revert WithinInterval();
    NextSwapInformation memory _nextSwapInformation = _getNextSwapInfo(_swapInterval, _swapParameters.swapFee);
    _registerSwap(
      _swapInterval,
      address(tokenA),
      _nextSwapInformation.amountToSwapTokenA,
      _nextSwapInformation.ratePerUnitAToB,
      _nextSwapInformation.swapToPerform
    );
    _registerSwap(
      _swapInterval,
      address(tokenB),
      _nextSwapInformation.amountToSwapTokenB,
      _nextSwapInformation.ratePerUnitBToA,
      _nextSwapInformation.swapToPerform
    );
    performedSwaps[_swapInterval] = _nextSwapInformation.swapToPerform;
    lastSwapPerformed[_swapInterval] = _getTimestamp();

    if (
      _amountToBorrowTokenA > _nextSwapInformation.availableToBorrowTokenA ||
      _amountToBorrowTokenB > _nextSwapInformation.availableToBorrowTokenB
    ) revert CommonErrors.InsufficientLiquidity();

    uint256 _amountToHaveTokenA = _nextSwapInformation.availableToBorrowTokenA;
    uint256 _amountToHaveTokenB = _nextSwapInformation.availableToBorrowTokenB;

    {
      // scope for _amountToSendToken{A,B}, avoids stack too deep errors
      uint256 _amountToSendTokenA = _amountToBorrowTokenA;
      uint256 _amountToSendTokenB = _amountToBorrowTokenB;

      if (_nextSwapInformation.tokenToRewardSwapperWith == tokenA) {
        _amountToSendTokenA += _nextSwapInformation.amountToRewardSwapperWith;
        _amountToHaveTokenB += _nextSwapInformation.amountToBeProvidedBySwapper;
      } else {
        _amountToSendTokenB += _nextSwapInformation.amountToRewardSwapperWith;
        _amountToHaveTokenA += _nextSwapInformation.amountToBeProvidedBySwapper;
      }

      // Optimistically transfer tokens
      if (_amountToSendTokenA > 0) tokenA.safeTransfer(_to, _amountToSendTokenA);
      if (_amountToSendTokenB > 0) tokenB.safeTransfer(_to, _amountToSendTokenB);
    }

    if (_data.length > 0) {
      // Make call
      IDCAPairSwapCallee(_to).DCAPairSwapCall(
        msg.sender,
        tokenA,
        tokenB,
        _amountToBorrowTokenA,
        _amountToBorrowTokenB,
        _nextSwapInformation.tokenToRewardSwapperWith == tokenA,
        _nextSwapInformation.amountToRewardSwapperWith,
        _nextSwapInformation.amountToBeProvidedBySwapper,
        _data
      );
    }

    uint256 _balanceTokenA = tokenA.balanceOf(address(this));
    uint256 _balanceTokenB = tokenB.balanceOf(address(this));

    // Make sure that they sent the tokens back
    if (_balanceTokenA < _amountToHaveTokenA || _balanceTokenB < _amountToHaveTokenB) revert CommonErrors.LiquidityNotReturned();

    // Update balances
    _balances[address(tokenA)] = _balanceTokenA - _nextSwapInformation.platformFeeTokenA;
    _balances[address(tokenB)] = _balanceTokenB - _nextSwapInformation.platformFeeTokenB;

    // Send fees
    tokenA.safeTransfer(_swapParameters.feeRecipient, _nextSwapInformation.platformFeeTokenA);
    tokenB.safeTransfer(_swapParameters.feeRecipient, _nextSwapInformation.platformFeeTokenB);

    // Emit event
    emit Swapped(msg.sender, _to, _amountToBorrowTokenA, _amountToBorrowTokenB, _nextSwapInformation);
  }

  function _getTimestamp() internal view virtual returns (uint32 _blockTimestamp) {
    _blockTimestamp = uint32(block.timestamp);
  }
}

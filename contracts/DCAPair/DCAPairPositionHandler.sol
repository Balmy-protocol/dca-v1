//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.0;

import './DCAPairParameters.sol';
import './ERC721/ERC721.sol';
import './utils/Math.sol';

interface IDCAPairPositionHandler {
  event Terminated(address indexed _user, uint256 _dcaId, uint256 _returnedUnswapped, uint256 _returnedSwapped);
  event Deposited(address indexed _user, uint256 _dcaId, address _fromToken, uint256 _rate, uint256 _startingSwap, uint256 _lastSwap);
  event Withdrew(address indexed _user, uint256 _dcaId, address _token, uint256 _amount);
  event WithdrewMany(address indexed _user, uint256[] _dcaIds, uint256 _swappedTokenA, uint256 _swappedTokenB);
  event Modified(address indexed _user, uint256 _dcaId, uint256 _rate, uint256 _startingSwap, uint256 _lastSwap);

  function deposit(
    address _tokenAddress,
    uint256 _rate,
    uint256 _amountOfSwaps
  ) external;

  function withdrawSwapped(uint256 _dcaId) external returns (uint256 _swapped);

  function withdrawSwappedMany(uint256[] calldata _dcaIds) external returns (uint256 _swappedTokenA, uint256 _swappedTokenB);

  function modifyRate(uint256 _dcaId, uint256 _newRate) external;

  function modifySwaps(uint256 _dcaId, uint256 _newSwaps) external;

  function modifyRateAndSwaps(
    uint256 _dcaId,
    uint256 _newRate,
    uint256 _newSwaps
  ) external;

  function addFundsToPosition(
    uint256 _dcaId,
    uint256 _amount,
    uint256 _newSwaps
  ) external;

  function terminate(uint256 _dcaId) external;
}

abstract contract DCAPairPositionHandler is DCAPairParameters, IDCAPairPositionHandler, ERC721 {
  using SafeERC20 for IERC20Detailed;

  uint256 internal _idCounter = 0;

  constructor(IERC20Detailed _tokenA, IERC20Detailed _tokenB)
    ERC721(string(abi.encodePacked('DCA: ', _tokenA.symbol(), ' - ', _tokenB.symbol())), 'DCA')
  {}

  function _deposit(
    address _tokenAddress,
    uint256 _rate,
    uint256 _amountOfSwaps
  ) internal returns (uint256) {
    require(_tokenAddress == address(tokenA) || _tokenAddress == address(tokenB), 'DCAPair: Invalid deposit address');
    IERC20Detailed _from = _tokenAddress == address(tokenA) ? tokenA : tokenB;
    _from.safeTransferFrom(msg.sender, address(this), _rate * _amountOfSwaps);
    _idCounter += 1;
    _safeMint(msg.sender, _idCounter);
    (uint256 _startingSwap, uint256 _finalSwap) = _addPosition(_idCounter, _tokenAddress, _rate, _amountOfSwaps);
    emit Deposited(msg.sender, _idCounter, _tokenAddress, _rate, _startingSwap, _finalSwap);
    return _idCounter;
  }

  function _withdrawSwapped(uint256 _dcaId) internal returns (uint256 _swapped) {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);

    _swapped = _calculateSwapped(_dcaId);

    if (_swapped > 0) {
      userPositions[_dcaId].lastWithdrawSwap = performedSwaps;

      IERC20Detailed _to = _getTo(_dcaId);
      _to.safeTransfer(msg.sender, _swapped);

      emit Withdrew(msg.sender, _dcaId, address(_to), _swapped);
    }
  }

  function _withdrawSwappedMany(uint256[] calldata _dcaIds) internal returns (uint256 _swappedTokenA, uint256 _swappedTokenB) {
    for (uint256 i = 0; i < _dcaIds.length; i++) {
      uint256 _dcaId = _dcaIds[i];
      _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);
      uint256 _swappedDCA = _calculateSwapped(_dcaId);
      if (userPositions[_dcaId].from == address(tokenA)) {
        _swappedTokenB += _swappedDCA;
      } else {
        _swappedTokenA += _swappedDCA;
      }
      userPositions[_dcaId].lastWithdrawSwap = performedSwaps;
    }

    if (_swappedTokenA > 0 || _swappedTokenB > 0) {
      if (_swappedTokenA > 0) {
        tokenA.safeTransfer(msg.sender, _swappedTokenA);
      }

      if (_swappedTokenB > 0) {
        tokenB.safeTransfer(msg.sender, _swappedTokenB);
      }
      emit WithdrewMany(msg.sender, _dcaIds, _swappedTokenA, _swappedTokenB);
    }
  }

  function _terminate(uint256 _dcaId) internal {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);

    uint256 _swapped = _calculateSwapped(_dcaId);
    uint256 _unswapped = _calculateUnswapped(_dcaId);

    IERC20Detailed _from = _getFrom(_dcaId);
    IERC20Detailed _to = _getTo(_dcaId);
    _removePosition(_dcaId);
    _burn(_dcaId);

    if (_swapped > 0) {
      _to.safeTransfer(msg.sender, _swapped);
    }

    if (_unswapped > 0) {
      _from.safeTransfer(msg.sender, _unswapped);
    }

    emit Terminated(msg.sender, _dcaId, _unswapped, _swapped);
  }

  function _modifyRate(uint256 _dcaId, uint256 _newRate) internal {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);

    DCA memory _userDCA = userPositions[_dcaId];

    uint256 _swapsLeft = _userDCA.lastSwap - performedSwaps;
    require(_swapsLeft > 0, 'DCAPair: You cannot modify only the rate of a position that has already been completed');

    _modifyRateAndSwaps(_dcaId, _newRate, _swapsLeft);
  }

  function _modifySwaps(uint256 _dcaId, uint256 _newSwaps) internal {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);

    DCA memory _userDCA = userPositions[_dcaId];

    _modifyRateAndSwaps(_dcaId, _userDCA.rate, _newSwaps);
  }

  function _modifyRateAndSwaps(
    uint256 _dcaId,
    uint256 _newRate,
    uint256 _newAmountOfSwaps
  ) internal {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);

    uint256 _unswapped = _calculateUnswapped(_dcaId);
    uint256 _totalNecessary = _newRate * _newAmountOfSwaps;

    _modifyPosition(_dcaId, _totalNecessary, _unswapped, _newRate, _newAmountOfSwaps);
  }

  function _addFundsToPosition(
    uint256 _dcaId,
    uint256 _amount,
    uint256 _newSwaps
  ) internal {
    _assertPositionExistsAndCanBeOperatedByCaller(_dcaId);
    require(_amount > 0, 'DCAPair: The amount to add must be positive');

    uint256 _unswapped = _calculateUnswapped(_dcaId);
    uint256 _total = _unswapped + _amount;
    uint256 _newRate = _total / _newSwaps;

    _modifyPosition(_dcaId, _total, _unswapped, _newRate, _newSwaps);
  }

  /** Helper function to modify a position */
  function _modifyPosition(
    uint256 _dcaId,
    uint256 _totalNecessary,
    uint256 _unswapped,
    uint256 _newRate,
    uint256 _newAmountOfSwaps
  ) internal {
    IERC20Detailed _from = _getFrom(_dcaId);

    _removePosition(_dcaId);
    (uint256 _startingSwap, uint256 _finalSwap) = _addPosition(_dcaId, address(_from), _newRate, _newAmountOfSwaps);

    if (_totalNecessary > _unswapped) {
      // We need to ask for more funds
      _from.safeTransferFrom(msg.sender, address(this), _totalNecessary - _unswapped);
    } else if (_totalNecessary < _unswapped) {
      // We need to return to the owner the amount that won't be used anymore
      _from.safeTransfer(msg.sender, _unswapped - _totalNecessary);
    }

    emit Modified(msg.sender, _dcaId, _newRate, _startingSwap, _finalSwap);
  }

  function _assertPositionExistsAndCanBeOperatedByCaller(uint256 _dcaId) internal view {
    require(userPositions[_dcaId].rate > 0, 'DCAPair: Invalid position id');
    require(_isApprovedOrOwner(msg.sender, _dcaId), 'DCAPair: Called must be owner, or approved by owner');
  }

  function _addPosition(
    uint256 _dcaId,
    address _from,
    uint256 _rate,
    uint256 _amountOfSwaps
  ) internal returns (uint256 _startingSwap, uint256 _finalSwap) {
    require(_rate > 0, 'DCAPair: Invalid rate. It must be positive');
    require(_amountOfSwaps > 0, 'DCAPair: Invalid amount of swaps. It must be positive');
    _startingSwap = performedSwaps + 1;
    _finalSwap = performedSwaps + _amountOfSwaps;
    swapAmountDelta[_from][_startingSwap] += int256(_rate);
    swapAmountDelta[_from][_finalSwap] -= int256(_rate);
    userPositions[_dcaId] = DCA(_from, _rate, performedSwaps, _finalSwap);
  }

  function _removePosition(uint256 _dcaId) internal {
    DCA memory _userDCA = userPositions[_dcaId];
    if (_userDCA.lastSwap > performedSwaps) {
      swapAmountDelta[_userDCA.from][performedSwaps + 1] -= int256(_userDCA.rate);
      swapAmountDelta[_userDCA.from][_userDCA.lastSwap] += int256(_userDCA.rate);
    }
    delete userPositions[_dcaId];
  }

  /** Return the amount of tokens swapped in TO */
  function _calculateSwapped(uint256 _dcaId) internal view returns (uint256 _swapped) {
    DCA memory _userDCA = userPositions[_dcaId];
    uint256[2] memory _accumRatesLastWidthraw = accumRatesPerUnit[_userDCA.from][_userDCA.lastWithdrawSwap];
    uint256[2] memory _accumRatesLastSwap = accumRatesPerUnit[_userDCA.from][Math.min(performedSwaps, _userDCA.lastSwap)];

    /*
      LS = last swap = min(performed swaps, position.finalSwap)
      LW = last widthraw
      RATE_PER_UNIT(swap) = TO tokens for one unit of FROM = amount TO tokens * magnitude(TO)
      RATE(position) = amount FROM tokens * magnitude(FROM)
      accumPerUnit(swap) = RATE_PER_UNIT(swap) + RATE_PER_UNIT(swap - 1) + ... + RATE_PER_UNIT(1)

      swapped = (accumPerUnit(LS) - accumPerUnit(LW)) * RATE / magnitude(FROM)
      swapped = ((multiplier(LS) - multiplier(LW)) * MAX_UINT + accum(LS) - accum(LW)) * RATE / magnitude(FROM)
    */

    uint256 _multiplierDifference = _accumRatesLastSwap[1] - _accumRatesLastWidthraw[1];
    uint256 _accumPerUnit;
    if (_multiplierDifference == 2) {
      // If multiplier difference is 2, then the only way it won't overflow is if accum(LS) - accum(LW) == -max(uint256).
      // This line will revert for all other scenarios
      _accumPerUnit = type(uint256).max - (_accumRatesLastWidthraw[0] - _accumRatesLastSwap[0]) + type(uint256).max;
    } else {
      uint256 _multiplierTerm = _multiplierDifference * type(uint256).max;
      if (_accumRatesLastSwap[0] >= _accumRatesLastWidthraw[0]) {
        _accumPerUnit = _multiplierTerm + (_accumRatesLastSwap[0] - _accumRatesLastWidthraw[0]);
      } else {
        _accumPerUnit = _multiplierTerm - (_accumRatesLastWidthraw[0] - _accumRatesLastSwap[0]);
      }
    }

    uint256 _magnitude = (_userDCA.from == address(tokenA)) ? _magnitudeA : _magnitudeB;
    (bool _ok, uint256 _mult) = Math.tryMul(_accumPerUnit, _userDCA.rate);
    uint256 _actuallySwapped;
    if (_ok) {
      _actuallySwapped = _mult / _magnitude;
    } else {
      // Since we can't multiply accum and rate because of overflows, we need to figure out which to divide
      // We don't want to divide a term that is smaller than magnitude, because it would go to 0.
      // And if neither are smaller than magnitude, then we will choose the one that loses less information, and that would be the one with smallest reminder
      bool _divideAccumFirst =
        _userDCA.rate < _magnitude || (_accumPerUnit > _magnitude && _accumPerUnit % _magnitude < _userDCA.rate % _magnitude);
      _actuallySwapped = _divideAccumFirst ? (_accumPerUnit / _magnitude) * _userDCA.rate : (_userDCA.rate / _magnitude) * _accumPerUnit;
    }

    uint256 _fee = _getFeeFromAmount(_actuallySwapped);
    _swapped = _actuallySwapped - _fee;
  }

  /** Returns how many FROM remains unswapped  */
  function _calculateUnswapped(uint256 _dcaId) internal view returns (uint256 _unswapped) {
    DCA memory _userDCA = userPositions[_dcaId];
    if (_userDCA.lastSwap <= performedSwaps) {
      return 0;
    }
    uint256 _remainingSwaps = _userDCA.lastSwap - performedSwaps;
    _unswapped = _remainingSwaps * _userDCA.rate;
  }

  function _getFrom(uint256 _dcaId) internal view returns (IERC20Detailed _from) {
    DCA memory _userDCA = userPositions[_dcaId];
    _from = _userDCA.from == address(tokenA) ? tokenA : tokenB;
  }

  function _getTo(uint256 _dcaId) internal view returns (IERC20Detailed _to) {
    DCA memory _userDCA = userPositions[_dcaId];
    _to = _userDCA.from == address(tokenA) ? tokenB : tokenA;
  }
}

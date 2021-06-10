// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interfaces/IDCAGlobalParameters.sol';
import '../interfaces/IERC20Detailed.sol';
import '../interfaces/IDCAPair.sol';
import './utils/Math.sol';

abstract contract DCAPairParameters is IDCAPairParameters {
  // Internal constants
  uint256 internal immutable _magnitudeA;
  uint256 internal immutable _magnitudeB;
  uint24 internal immutable _feePrecision;

  // Basic setup
  IDCAGlobalParameters public override globalParameters;
  IERC20Detailed public override tokenA;
  IERC20Detailed public override tokenB;
  uint32 public override swapInterval;

  // Tracking
  mapping(uint32 => mapping(address => mapping(uint32 => int256))) public override swapAmountDelta; // swap interval => from token => swap number => delta
  mapping(uint32 => uint32) public override performedSwaps; // swap interval => performed swaps
  mapping(uint32 => mapping(address => mapping(uint32 => uint256[2]))) internal _accumRatesPerUnit; // swap interval => from token => swap number => accum
  mapping(address => uint256) internal _balances;

  constructor(
    IDCAGlobalParameters _globalParameters,
    IERC20Detailed _tokenA,
    IERC20Detailed _tokenB,
    uint32 _swapInterval
  ) {
    require(address(_globalParameters) != address(0), 'DCAPair: zero address');
    require(address(_tokenA) != address(0), 'DCAPair: zero address');
    require(address(_tokenB) != address(0), 'DCAPair: zero address');
    globalParameters = _globalParameters;
    _feePrecision = globalParameters.FEE_PRECISION();
    tokenA = _tokenA;
    tokenB = _tokenB;
    _magnitudeA = 10**_tokenA.decimals();
    _magnitudeB = 10**_tokenB.decimals();
    swapInterval = _swapInterval;
  }

  function _getFeeFromAmount(uint32 _feeAmount, uint256 _amount) internal view returns (uint256) {
    (bool _ok, uint256 _fee) = Math.tryMul(_amount, _feeAmount);
    if (_ok) {
      _fee = _fee / _feePrecision / 100;
    } else {
      _fee = (_feeAmount < _feePrecision) ? ((_amount / _feePrecision) * _feeAmount) / 100 : (_amount / _feePrecision / 100) * _feeAmount;
    }
    return _fee;
  }
}

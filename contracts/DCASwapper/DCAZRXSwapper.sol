// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../utils/Governable.sol';
import '../utils/CollectableDust.sol';
import '../interfaces/IDCAPair.sol';
import '../interfaces/IDCAPairSwapCallee.sol';
import '../libraries/CommonErrors.sol';

contract DCAZRXSwapper is Governable, IDCAPairSwapCallee, CollectableDust {
  using SafeERC20 for IERC20;

  struct PairToSwap {
    IDCAPair pair;
    bytes data;
  }

  error ZeroPairsToSwap();

  // solhint-disable-next-line var-name-mixedcase
  address public ZRX;

  // solhint-disable-next-line var-name-mixedcase
  constructor(address _governor, address _ZRX) Governable(_governor) {
    if (address(_ZRX) == address(0)) revert CommonErrors.ZeroAddress();
    ZRX = _ZRX;
  }

  function swapPairs(PairToSwap[] calldata _pairsToSwap) external {
    if (_pairsToSwap.length == 0) revert ZeroPairsToSwap();
    for (uint256 i; i < _pairsToSwap.length; i++) {
      _swap(_pairsToSwap[i]);
    }
  }

  function _swap(PairToSwap memory _pair) internal {
    // Execute the swap, making myself the callee so that the `DCAPairSwapCall` function is called
    _pair.pair.swap(0, 0, address(this), _pair.data);
  }

  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external override onlyGovernor {
    _sendDust(_to, _token, _amount);
  }

  // solhint-disable-next-line func-name-mixedcase
  function DCAPairSwapCall(
    address,
    IERC20Metadata _tokenA,
    IERC20Metadata _tokenB,
    uint256,
    uint256,
    bool _isRewardTokenA,
    uint256 _rewardAmount,
    uint256 _amountToProvide,
    bytes calldata _bytes
  ) external override {
    if (_amountToProvide > 0) {
      address _tokenIn = _isRewardTokenA ? address(_tokenA) : address(_tokenB);
      address _tokenOut = _isRewardTokenA ? address(_tokenB) : address(_tokenA);
      IERC20(_tokenIn).approve(ZRX, _rewardAmount);
      // solhint-disable-next-line avoid-low-level-calls
      (bool success, ) = ZRX.call{value: 0}(_bytes);
      require(success, 'Swapper: ZRX trade reverted');
      IERC20(_tokenOut).safeTransfer(msg.sender, IERC20(_tokenOut).balanceOf(address(this)));
    }
  }
}

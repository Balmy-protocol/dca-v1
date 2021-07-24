// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol';
import '../interfaces/IDCAFactory.sol';

interface ICustomQuoter is IPeripheryImmutableState {
  /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
  /// @param tokenIn The token being swapped in
  /// @param tokenOut The token being swapped out
  /// @param fee The fee of the token pool to consider for the pair
  /// @param amountOut The desired output amount
  /// @param sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
  /// @return amountIn The amount required as the input for the swap in order to receive `amountOut`
  function quoteExactOutputSingle(
    address tokenIn,
    address tokenOut,
    uint24 fee,
    uint256 amountOut,
    uint160 sqrtPriceLimitX96
  ) external view returns (uint256 amountIn);
}

interface IDCASwapper {
  event WatchingNewPairs(address[] _pairs);
  event StoppedWatchingPairs(address[] _pairs);
  event Swapped(IDCAPair[] _pairsToSwap, uint256 _amountSwapped);

  error InvalidPairAddress();
  error ZeroPairsToSwap();

  /* Public getters */
  function watchedPairs() external view returns (address[] memory);

  function factory() external view returns (IDCAFactory);

  function swapRouter() external view returns (ISwapRouter);

  function quoter() external view returns (ICustomQuoter);

  /**
   * This method isn't really a view and it is extremelly expensive and inefficient.
   * DO NOT call this method on-chain, it is for off-chain purposes only.
   */
  function getPairsToSwap() external view returns (IDCAPair[] memory _pairs, uint24[] memory _bestFeeTiers);

  /* Public setters */
  function startWatchingPairs(address[] calldata) external;

  function stopWatchingPairs(address[] calldata) external;

  /**
   * Takes an array of swaps, and executes as many as possible, returning the amount that was swapped
   */
  function swapPairs(IDCAPair[] calldata _pairsToSwap, uint24[] calldata _bestFeeTiers) external returns (uint256 _amountSwapped);
}

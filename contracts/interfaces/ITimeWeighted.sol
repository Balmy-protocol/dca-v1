// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

interface ITimeWeightedOracle {
  /** Returns whether this oracle supports this pair of tokens */
  function supportsPair(address _tokenA, address _tokenB) external view returns (bool);

  /** Returns a quote, based on the given tokens and amount */
  function quote(
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) external view returns (uint256 _amountOut);

  /** Let the oracle take some actions to prepare for this new pair of tokens */
  function initializePair(address _tokenA, address _tokenB) external;
}

interface IUniswapV3OracleAggregator is ITimeWeightedOracle {
  function factory() external view returns (IFactory);

  function supportedFeeTiers() external view returns (uint24[] memory);

  function addFeeTier(uint24) external;
}

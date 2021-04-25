//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IERC20Detailed is IERC20 {
  function decimals() external view returns (uint8);

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);
}

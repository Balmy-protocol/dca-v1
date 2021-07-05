// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

interface IDCASwapper {
  event WatchingNewPairs(address[] _pairs);
  event StoppedWatchingPairs(address[] _pairs);

  /* Public getters */
  function watchedPairs() external view returns (address[] memory);

  /* Public setters */
  function startWatchingPairs(address[] calldata) external;

  function stopWatchingPairs(address[] calldata) external;
}

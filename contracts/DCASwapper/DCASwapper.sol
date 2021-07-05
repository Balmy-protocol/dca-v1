// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../utils/Governable.sol';
import '../interfaces/IDCASwapper.sol';
import '../libraries/CommonErrors.sol';

contract DCASwapper is IDCASwapper, Governable {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _watchedPairs;

  constructor(address _governor) Governable(_governor) {}

  function startWatchingPairs(address[] calldata _pairs) public override onlyGovernor {
    for (uint256 i; i < _pairs.length; i++) {
      if (_pairs[i] == address(0)) revert CommonErrors.ZeroAddress();
      _watchedPairs.add(_pairs[i]);
    }
    emit WatchingNewPairs(_pairs);
  }

  function stopWatchingPairs(address[] calldata _pairs) public override onlyGovernor {
    for (uint256 i; i < _pairs.length; i++) {
      _watchedPairs.remove(_pairs[i]);
    }
    emit StoppedWatchingPairs(_pairs);
  }

  function watchedPairs() external view override returns (address[] memory _pairs) {
    uint256 _length = _watchedPairs.length();
    _pairs = new address[](_length);
    for (uint256 i; i < _length; i++) {
      _pairs[i] = _watchedPairs.at(i);
    }
  }
}

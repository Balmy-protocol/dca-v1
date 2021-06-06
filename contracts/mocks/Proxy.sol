// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

contract Proxy {
  function executeTansactions(
    address[] memory _targets,
    string[] memory _signatures,
    bytes[] memory _datas
  ) external {
    for (uint256 i = 0; i < _targets.length; i++) {
      _executeTransaction(_targets[i], _signatures[i], _datas[i]);
    }
  }

  function executeDoubleTransaction(
    address target,
    string memory signature,
    bytes memory data
  ) external {
    _executeTransaction(target, signature, data);
    require(_executeTransaction(target, signature, data), 'reentrant attack stopped');
  }

  function executeSingleTransaction(
    address target,
    string memory signature,
    bytes memory data
  ) external {
    require(_executeTransaction(target, signature, data), 'reverted tx');
  }

  function _executeTransaction(
    address target,
    string memory signature,
    bytes memory data
  ) internal returns (bool) {
    bytes memory callData;

    if (bytes(signature).length == 0) {
      callData = data;
    } else {
      callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
    }

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, ) = target.call{value: 0}(callData);

    return success;
  }
}

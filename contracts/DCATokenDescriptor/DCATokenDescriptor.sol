// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;
pragma abicoder v2;

import '../interfaces/IDCAGlobalParameters.sol';
import '../interfaces/IDCAPair.sol';
import '../interfaces/IERC20Detailed.sol';
import '../libraries/NFTDescriptor.sol';

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract DCATokenDescriptor is IDCATokenDescriptor {
  function tokenURI(IDCAPair _pair, uint256 _tokenId) external view override returns (string memory) {
    IERC20Detailed _tokenA = _pair.tokenA();
    IERC20Detailed _tokenB = _pair.tokenB();

    (
      IERC20Detailed _from,
      ,
      uint32 _swapInterval,
      uint32 _swapsExecuted,
      uint256 _swapped,
      uint32 _swapsLeft,
      uint256 _remaining,
      uint192 _rate
    ) = _pair.userPosition(_tokenId);

    string memory _intervalDescription;
    {
      // Context used to avoid stack to deep errors

      IDCAGlobalParameters _globalParameters = _pair.globalParameters();
      _intervalDescription = _globalParameters.intervalDescription(_swapInterval);
    }

    return
      NFTDescriptor.constructTokenURI(
        NFTDescriptor.ConstructTokenURIParams({
          tokenId: _tokenId,
          pair: address(_pair), // WTF
          tokenA: address(_tokenA),
          tokenB: address(_tokenB),
          tokenADecimals: _tokenA.decimals(),
          tokenBDecimals: _tokenB.decimals(),
          tokenASymbol: _tokenA.symbol(),
          tokenBSymbol: _tokenB.symbol(),
          swapInterval: _intervalDescription,
          swapsExecuted: _swapsExecuted,
          swapped: _swapped,
          swapsLeft: _swapsLeft,
          remaining: _remaining,
          rate: _rate,
          fromA: _from == _tokenA
        })
      );
  }
}

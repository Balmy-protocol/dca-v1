// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.6;

import './IDCAGlobalParameters.sol';
import './IERC20Detailed.sol';

/// @title The interface for all state related queries
/// @notice These methods allow users to read the pair's current values
interface IDCAPairParameters {
  /// @notice Returns the global parameters contract
  /// @dev Global parameters has information about swaps and pairs, like swap intervals, fees charged, etc.
  /// @return The Global Parameters contract
  function globalParameters() external view returns (IDCAGlobalParameters);

  /// @notice Returns the token A contract
  /// @return The contract for token A
  function tokenA() external view returns (IERC20Detailed);

  /// @notice Returns the token B contract
  /// @return The contract for token B
  function tokenB() external view returns (IERC20Detailed);

  /// @notice Returns how much will the amount to swap differ from the previous swap
  /// @dev f.e. if the returned value is -100, then the amount to swap will be 100 less than the swap just before it
  /// @param _swapInterval The swap interval to check
  /// @param _from The 'from' token of the deposits
  /// @param _swap The swap number to check
  /// @return _delta How much will the amount to swap differ, when compared to the swap just before this one
  function swapAmountDelta(
    uint32 _swapInterval,
    address _from,
    uint32 _swap
  ) external view returns (int256 _delta);

  /// @notice Returns if a certain swap interval is active or not
  /// @dev We consider a swap interval to be active if there is at least one active position on that interval
  /// @param _swapInterval The swap interval to check
  /// @return _isActive Whether the given swap interval is currently active
  function isSwapIntervalActive(uint32 _swapInterval) external view returns (bool _isActive);

  /// @notice Returns the amount of swaps executed for a certain interval
  /// @param _swapInterval The swap interval to check
  /// @return _swaps The amount of swaps performed on the given interval
  function performedSwaps(uint32 _swapInterval) external view returns (uint32 _swaps);
}

/// @title The interface for all position related matters in a DCA pair
/// @notice These methods allow users to create, modify and terminate their positions
interface IDCAPairPositionHandler is IDCAPairParameters {
  /// @notice The position of a certain user
  struct UserPosition {
    // The token that the user deposited and will be swapped in exchange for "to"
    IERC20Detailed from;
    // The token that the user will get in exchange for their "from" tokens in each swap
    IERC20Detailed to;
    // How frequently the position's swaps should be executed
    uint32 swapInterval;
    // How many swaps were executed since deposit, last modification, or last withdraw
    uint32 swapsExecuted;
    // How many "to" tokens can currently be withdrawn
    uint256 swapped;
    // How many swaps left the position has to execute
    uint32 swapsLeft;
    // How many "from" tokens there are left to swap
    uint256 remaining;
    // How many "from" tokens need to be traded in each swap
    uint160 rate;
  }

  /// @notice Emitted when a position is terminated
  /// @param _user The address of the user that terminated the position
  /// @param _dcaId The id of the position that was terminated
  /// @param _returnedUnswapped How many "from" tokens were returned to the caller
  /// @param _returnedSwapped How many "to" tokens were returned to the caller
  event Terminated(address indexed _user, uint256 _dcaId, uint256 _returnedUnswapped, uint256 _returnedSwapped);

  /// @notice Emitted when a position is created
  /// @param _user The address of the user that created the position
  /// @param _dcaId The id of the position that was created
  /// @param _fromToken The address of the "from" token
  /// @param _rate How many "from" tokens need to be traded in each swap
  /// @param _startingSwap The number of the swap when the position will be executed for the first time
  /// @param _swapInterval How frequently the position's swaps should be executed
  /// @param _lastSwap The number of the swap when the position will be executed for the last time
  event Deposited(
    address indexed _user,
    uint256 _dcaId,
    address _fromToken,
    uint160 _rate,
    uint32 _startingSwap,
    uint32 _swapInterval,
    uint32 _lastSwap
  );

  /// @notice Emitted when a user withdraws all swapped tokens from a position
  /// @param _user The address of the user that executed the withdraw
  /// @param _dcaId The id of the position that was affected
  /// @param _token The address of the withdrawn tokens. It's the same as the position's "to" token
  /// @param _amount The amount that was withdrawn
  event Withdrew(address indexed _user, uint256 _dcaId, address _token, uint256 _amount);

  /// @notice Emitted when a user withdraws all swapped tokens from many positions
  /// @param _user The address of the user that executed the withdraw
  /// @param _dcaIds The ids of the positions that were affected
  /// @param _swappedTokenA The total amount that was withdrawn in token A
  /// @param _swappedTokenB The total amount that was withdrawn in token B
  event WithdrewMany(address indexed _user, uint256[] _dcaIds, uint256 _swappedTokenA, uint256 _swappedTokenB);

  /// @notice Emitted when a position is modified
  /// @param _user The address of the user that modified the position
  /// @param _dcaId The id of the position that was modified
  /// @param _rate How many "from" tokens need to be traded in each swap
  /// @param _startingSwap The number of the swap when the position will be executed for the first time
  /// @param _lastSwap The number of the swap when the position will be executed for the last time
  event Modified(address indexed _user, uint256 _dcaId, uint160 _rate, uint32 _startingSwap, uint32 _lastSwap);

  /// @notice Thrown when a user tries to create a position with a token that is neither token A nor token B
  error InvalidToken();

  /// @notice Thrown when a user tries to create that a position with an unsupported swap interval
  error InvalidInterval();

  /// @notice Thrown when a user tries operate on a position that doesn't exist (it might have been already terminated)
  error InvalidPosition();

  /// @notice Thrown when a user tries operate on a position that they don't have access to
  error UnauthorizedCaller();

  /// @notice Thrown when a user tries to create or modify a position by setting the rate to be zero
  error ZeroRate();

  /// @notice Thrown when a user tries to create a position with zero swaps
  error ZeroSwaps();

  /// @notice Thrown when a user tries to add zero funds to their position
  error ZeroAmount();

  /// @notice Thrown when a user tries to modify the rate of a position that has already been completed
  error PositionCompleted();

  /// @notice Thrown when a user tries to modify a position that has too much swapped balance. This error
  /// is thrown so that the user doesn't lose any funds. The error indicates that the user must perform a withdraw
  /// before modifying their position
  error MandatoryWithdraw();

  /// @notice Returns a DCA position
  /// @param _dcaId The id of the position
  /// @return _position The position itself
  function userPosition(uint256 _dcaId) external view returns (UserPosition memory _position);

  /// @notice Creates a new position
  /// @dev Will revert:
  /// With InvalidToken if _tokenAddress is neither token A nor token B
  /// With ZeroRate if _rate is zero
  /// With ZeroSwaps if _amountOfSwaps is zero
  /// With InvalidInterval if _swapInterval is not a valid swap interval
  /// @param _tokenAddress The address of the token that will be deposited
  /// @param _rate How many "from" tokens need to be traded in each swap
  /// @param _amountOfSwaps How many swaps to execute for this position
  /// @param _swapInterval How frequently the position's swaps should be executed
  /// @return _dcaId The id of the created position
  function deposit(
    address _tokenAddress,
    uint160 _rate,
    uint32 _amountOfSwaps,
    uint32 _swapInterval
  ) external returns (uint256 _dcaId);

  /// @notice Withdraws all swapped tokens from a position
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// @param _dcaId The position's id
  /// @return _swapped How much was withdrawn
  function withdrawSwapped(uint256 _dcaId) external returns (uint256 _swapped);

  /// @notice Withdraws all swapped tokens from many positions
  /// @dev Will revert:
  /// With InvalidPosition if any of the ids in _dcaIds is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to any of the positions in _dcaIds
  /// @param _dcaIds The positions' ids
  /// @return _swappedTokenA How much was withdrawn in token A
  /// @return _swappedTokenB How much was withdrawn in token B
  function withdrawSwappedMany(uint256[] calldata _dcaIds) external returns (uint256 _swappedTokenA, uint256 _swappedTokenB);

  /// @notice Modifies the rate of a position. Could request more funds or return deposited funds
  /// depending on whether the new rate is greater than the previous one.
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// With PositionCompleted if position has already been completed
  /// With ZeroRate if _newRate is zero
  /// With MandatoryWithdraw if the user must execute a withdraw before modifying their position
  /// @param _dcaId The position's id
  /// @param _newRate The new rate to set
  function modifyRate(uint256 _dcaId, uint160 _newRate) external;

  /// @notice Modifies the amount of swaps of a position. Could request more funds or return
  /// deposited funds depending on whether the new amount of swaps is greater than the swaps left.
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// With MandatoryWithdraw if the user must execute a withdraw before modifying their position
  /// @param _dcaId The position's id
  /// @param _newSwaps The new amount of swaps
  function modifySwaps(uint256 _dcaId, uint32 _newSwaps) external;

  /// @notice Modifies the both the rate and amount of swaps of a position. Could request more funds or return
  /// deposited funds depending on whether the new parameters require more or less than the the unswapped funds.
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// With ZeroRate if _newRate is zero
  /// With MandatoryWithdraw if the user must execute a withdraw before modifying their position
  /// @param _dcaId The position's id
  /// @param _newRate The new rate to set
  /// @param _newSwaps The new amount of swaps
  function modifyRateAndSwaps(
    uint256 _dcaId,
    uint160 _newRate,
    uint32 _newSwaps
  ) external;

  /// @notice Takes the unswapped balance, adds the new deposited funds and modifies the position so that
  /// it is executed in _newSwaps swaps
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// With ZeroAmount if _amount is zero
  /// With ZeroSwaps if _newSwaps is zero
  /// With MandatoryWithdraw if the user must execute a withdraw before modifying their position
  /// @param _dcaId The position's id
  /// @param _amount Amounts of funds to add to the position
  /// @param _newSwaps The new amount of swaps
  function addFundsToPosition(
    uint256 _dcaId,
    uint256 _amount,
    uint32 _newSwaps
  ) external;

  /// @notice Terminates the position and sends all unswapped and swapped balance to the caller
  /// @dev Will revert:
  /// With InvalidPosition if _dcaId is invalid
  /// With UnauthorizedCaller if the caller doesn't have access to the position
  /// @param _dcaId The position's id
  function terminate(uint256 _dcaId) external;
}

interface IDCAPairSwapHandler {
  struct SwapInformation {
    uint32 interval;
    uint32 swapToPerform;
    uint256 amountToSwapTokenA;
    uint256 amountToSwapTokenB;
  }

  struct NextSwapInformation {
    SwapInformation[] swapsToPerform;
    uint8 amountOfSwaps;
    uint256 availableToBorrowTokenA;
    uint256 availableToBorrowTokenB;
    uint256 ratePerUnitBToA;
    uint256 ratePerUnitAToB;
    uint256 platformFeeTokenA;
    uint256 platformFeeTokenB;
    uint256 amountToBeProvidedBySwapper;
    uint256 amountToRewardSwapperWith;
    IERC20Detailed tokenToBeProvidedBySwapper;
    IERC20Detailed tokenToRewardSwapperWith;
  }

  event Swapped(
    address indexed _sender,
    address indexed _to,
    uint256 _amountBorrowedTokenA,
    uint256 _amountBorrowedTokenB,
    uint32 _fee,
    NextSwapInformation _nextSwapInformation
  );

  error NoSwapsToExecute();

  function nextSwapAvailable(uint32) external view returns (uint32);

  function swapAmountAccumulator(uint32, address) external view returns (uint256);

  function getNextSwapInfo() external view returns (NextSwapInformation memory _nextSwapInformation);

  function swap() external;

  function swap(
    uint256 _amountToBorrowTokenA,
    uint256 _amountToBorrowTokenB,
    address _to,
    bytes calldata _data
  ) external;

  function secondsUntilNextSwap() external view returns (uint32);
}

/// @title The interface for all loan related matters in a DCA pair
/// @notice These methods allow users to ask how much is available for loans, and also to execute them
interface IDCAPairLoanHandler {
  /// @notice Emitted when a flash loan is executed
  /// @param _sender The address of the user that initiated the loan
  /// @param _to The address that received the loan
  /// @param _amountBorrowedTokenA How much was borrowed in token A
  /// @param _amountBorrowedTokenB How much was borrowed in token B
  /// @param _loanFee How much was charged as a fee
  event Loaned(address indexed _sender, address indexed _to, uint256 _amountBorrowedTokenA, uint256 _amountBorrowedTokenB, uint32 _loanFee);

  // @notice Thrown when trying to execute a flash loan but without actually asking for tokens
  error ZeroLoan();

  /// @notice Returns the amount of tokens that can be asked for during a flash loan
  /// @return _amountToBorrowTokenA The amount of token A that is available for borrowing
  /// @return _amountToBorrowTokenB The amount of token B that is available for borrowing
  function availableToBorrow() external view returns (uint256 _amountToBorrowTokenA, uint256 _amountToBorrowTokenB);

  /// @notice Executes a flash loan, sending the required amounts to the specified loan recipient
  /// @dev Will revert:
  /// With ZeroLoan if both _amountToBorrowTokenA & _amountToBorrowTokenB are 0
  /// With Paused if loans are paused by protocol
  /// With InsufficientLiquidity if asked for more that reserves
  /// @param _amountToBorrowTokenA The amount to borrow in token A
  /// @param _amountToBorrowTokenB The amount to borrow in token B
  /// @param _to Address that will receive the loan. This address should be a contract that implements IDCAPairLoanCallee
  /// @param _data Any data that should be passed through to the callback
  function loan(
    uint256 _amountToBorrowTokenA,
    uint256 _amountToBorrowTokenB,
    address _to,
    bytes calldata _data
  ) external;
}

interface IDCAPair is IDCAPairParameters, IDCAPairSwapHandler, IDCAPairPositionHandler, IDCAPairLoanHandler {}

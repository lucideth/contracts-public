// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EsLTOKENStorage {
    event Vested(address indexed recipient, uint256 amount, uint256 vestedAt);
    event Released(address indexed recipient, uint256 amount);
    event Escrowed(address indexed recipient, uint256 amount);

    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice vesting duration in seconds
    uint256 public immutable vestDuration;

    /// @notice the underlying token to be vested
    ERC20 public LTOKEN;

    /// @notice Guard variable for re-entrancy checks
    uint8 internal _notEntered = 1; // 1 represents not entered, 2 represents entered

    struct VestingRecord {
        address recipient;
        uint256 startTime;
        uint256 amount;
        uint256 withdrawnAmount;
    }

    /// @notice mapping of VestingRecord(s) for user(s)
    mapping(address => VestingRecord[]) public vestings;

    /// @notice total amount of vested tokens per user
    mapping(address => uint256) public totalVested;

    /// @notice Minter contract that looks over the multirewards system for esLTOKEN
    address public esLTOKENMinter;

    address public fund; // Fund contract to distribute DSD reward to esLTOKEN holders

    modifier nonReentrant() {
        require(_notEntered == 1, "Reentrant call");
        _notEntered = 2;
        _;
        _notEntered = 1;
    }

    constructor(uint256 _vestDuration) {
        vestDuration = _vestDuration;
    }
}

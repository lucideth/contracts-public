// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../Interfaces/Convex/IBooster.sol";
import "hardhat/console.sol";

interface ILLToken {
    function mint(uint mintAmount) external returns (uint);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/**
 * @title Migrator is a contract that lets unstake and transfer LP from Convex to LsLend vaults.
 */

contract Migrator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    IBooster immutable booster; // Convex booster contract
    address public owner;

    // LP token => pool id of Convex
    mapping(address => uint256) public lpTokenToPoolId;
    // LP token => LsLend Vault
    mapping(address => address) public lpTokenToVault;
    // whitelisted LP tokens
    mapping(address => bool) public whitelistedLPs;
    // Whitelisted LP array
    address[] public whitelistedLPTokensArray;

    event Migrated(address indexed account, address _lpToken, uint256 migratedAmount);

    constructor(
        address[] memory _lpTokens,
        uint256[] memory _poolIds,
        address[] memory _vaults,
        address _convexBooster
    ) {
        require(_lpTokens.length == _poolIds.length, "length mismatch");
        require(_lpTokens.length == _vaults.length, "length mismatch");
        for (uint256 i = 0; i < _lpTokens.length; i++) {
            lpTokenToPoolId[_lpTokens[i]] = _poolIds[i];
            whitelistedLPs[_lpTokens[i]] = true;
            lpTokenToVault[_lpTokens[i]] = _vaults[i];
            whitelistedLPTokensArray.push(_lpTokens[i]);
        }
        owner = msg.sender;
        booster = IBooster(_convexBooster);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    ////////////// ADMIN FUNCTIONS /////////////////////

    /*
     * Add new LP token to whitelist
     */
    function addWhitelistedLP(address _lpToken, uint256 _poolId) external onlyOwner {
        require(!whitelistedLPs[_lpToken], "already whitelisted");
        whitelistedLPs[_lpToken] = true;
        whitelistedLPTokensArray.push(_lpToken);
        lpTokenToPoolId[_lpToken] = _poolId;
    }

    //////////////// EXTERNAL FUNCTIONS////////////////////////
    /* Migrate LP tokens from wallet and pools to LsLend Protocol
     */
    function migrate(address _lpToken) external returns (bool) {
        require(whitelistedLPs[_lpToken], "Invaid LP token");
        console.log("migrating");

        // Check balance of pool token on convex and transfer to this contract
        address token;
        (, token, , , , ) = booster.poolInfo(lpTokenToPoolId[_lpToken]);
        console.log("@pooltoken", token);
        uint256 userBal = IERC20(token).balanceOf(msg.sender);
        console.log("@userBal", userBal);
        IERC20(token).safeTransferFrom(msg.sender, address(this), userBal);
        console.log("@safeTransferFrom");

        // Unstake and transfer LP from Convex
        booster.withdraw(lpTokenToPoolId[_lpToken], userBal);
        uint256 lpBalance = IERC20(_lpToken).balanceOf(address(this));
        console.log("@booster.withdraw", lpBalance);
        // transfer to vault
        IERC20(_lpToken).approve(lpTokenToVault[_lpToken], lpBalance);
        ILLToken(lpTokenToVault[_lpToken]).mint(lpBalance);
        console.log("@lltoken.mint", lpBalance);
        // transfer lltokens to user
        uint256 llTokenBalance = ILLToken(lpTokenToVault[_lpToken]).balanceOf(address(this));
        ILLToken(lpTokenToVault[_lpToken]).transfer(msg.sender, llTokenBalance);
        console.log("@lltoken.transfer");
        emit Migrated(msg.sender, _lpToken, lpBalance);

        return true;
    }

    //////// PUBLIC FUNCTIONS////////////////////////
    /*
     * Returns list of all whitelisted LP tokens
     */
    function getWhitelistedLPs() public view returns (address[] memory) {
        return whitelistedLPTokensArray;
    }

    function getWhitelistedPoolToken(address _lpToken) public view returns (address) {
        require(whitelistedLPs[_lpToken], "Invaid LP token");
        address token;
        (, token, , , , ) = booster.poolInfo(lpTokenToPoolId[_lpToken]);
        return token;
    }

    /*
     * Returns balance of LP tokens in Convex
     */
    function getConvexBalance(address _lpToken, address _user) public view returns (uint256) {
        address token;
        (, token, , , , ) = booster.poolInfo(lpTokenToPoolId[_lpToken]);
        return IERC20(token).balanceOf(_user);
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { OFTCore } from "../../layerZero/OFTCore.sol";

interface IesLTOKENMinter {
    function refreshReward(address account) external;
}

contract DSD is ERC20, OFTCore {
    using SafeERC20 for IERC20;
    using Address for address;
    // --- Auth ---
    mapping(address => uint) public wards;
    mapping(address => uint) public rebaseManagers;

    IesLTOKENMinter public esltokenMinter;
    address public gov; // governance address

    /**
     * Grant address `guy` the authority to modify ward and rebaseManager mappings
     * @param guy  Address of holder
     * @param kind Kind of authority (0: ward, 1: rebaseManager)
     */

    function rely(address guy, uint8 kind) external auth {
        if (kind == 0) {
            wards[guy] = 1;
        } else if (kind == 1) {
            rebaseManagers[guy] = 1;
        } else {
            revert("DSD/invalid-kind");
        }
    }

    /**
     * Grant address `guy` the removal of authority to modify ward and rebaseManager mappings
     * @param guy Address of holder
     * @param kind Kind of authority (0: ward, 1: rebaseManager)
     */
    function deny(address guy, uint8 kind) external auth {
        if (kind == 0) {
            wards[guy] = 0;
        } else if (kind == 1) {
            rebaseManagers[guy] = 0;
        } else {
            revert("DSD/invalid-kind");
        }
    }

    /**
     * @notice Only the rebase manager can call functions with this modifier
     */
    modifier auth() {
        require(wards[msg.sender] == 1, "DSD/not-authorized");
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    /**
     * @dev States at which an account may exist in the protocol
     * Note: Contracts are by default non-rebasing
     */
    enum RebaseOption {
        UNKNOWN,
        REBASING,
        NON_REBASING
    }

    /**
     * @dev internally stored without any multiplier
     */
    mapping(address => uint256) private _balances;

    /**
     * @dev this mapping is valid only for addresses that have already changed their options.
     * To query an account's rebase option, call `isRebasingAccount()` externally
     * or `_isRebasingAccount()` internally.
     */
    mapping(address => RebaseOption) private _rebaseOptions;

    /**
     * @dev Supply of DSD which is open for rebasing
     */
    uint256 private _rebasingTotalSupply;

    /**
     * @dev Supply of DSD which is closed for rebasing
     */
    uint256 private _nonRebasingTotalSupply;

    /**
     * @dev Resolution of the multiplier used in internal calculations
     */
    uint256 private constant ONE = 1e36;

    /**
     * @dev Multiplier used to convert between internal and user-facing values
     */
    uint256 private multiplier;

    /**
     * @notice Multiplier last updated at
     */
    uint256 public lastUpdateTime;

    /**
     * @notice Status of DSD
     */
    bool public paused;

    /**
     * Version of DSD
     */
    string public constant version = "1";

    event DSDTokenSupplyChanged(uint, uint, uint);
    event TokenSupplyChanged(uint, uint, uint);
    event MultiplierChange(uint, uint);
    event SetRebasingOption(address, RebaseOption);

    event ESLTOKENMinterChanged(address pool, uint256 timestamp);
    event GovernanceAuthorityTransfer(address newGov);

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;

    /**
     * Intialize the DSD token
     * @param _name name of the token
     * @param _symbol symbol of the token
     * @param chainId_ chainId of the network
     * @param lzEndpoint_ layerZero endpoint for the network
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 chainId_,
        address lzEndpoint_
    ) OFTCore(lzEndpoint_) ERC20(_name, _symbol) {
        gov = msg.sender;
        wards[msg.sender] = 1;
        _setMultiplier(ONE);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes(version)),
                chainId_,
                address(this)
            )
        );
    }

    function setESLTOKENMinter(address addr) external onlyGov {
        esltokenMinter = IesLTOKENMinter(addr);
        emit ESLTOKENMinterChanged(addr, block.timestamp);
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
        emit GovernanceAuthorityTransfer(_gov);
    }

    function totalSupply() public view override returns (uint256) {
        return _timesMultiplier(_rebasingTotalSupply) + _nonRebasingTotalSupply;
    }

    function adjustedRebasingSupply() external view returns (uint256) {
        return _timesMultiplier(_rebasingTotalSupply);
    }

    function unadjustedRebasingSupply() external view returns (uint256) {
        return _rebasingTotalSupply;
    }

    function nonRebasingSupply() public view returns (uint256) {
        return _nonRebasingTotalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (isRebasingAccount(account)) {
            return _timesMultiplier(_balances[account]);
        }
        return _balances[account];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override setDefaultRebasingOption(from) setDefaultRebasingOption(to) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override whenNotPaused {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        _beforeTokenTransfer(sender, recipient, amount);

        // deducting from sender
        uint256 amountToDeduct = amount;
        if (_isRebasingAccount(sender)) {
            amountToDeduct = _dividedByMultiplier(amount);
            require(_balances[sender] >= amountToDeduct, "ERC20: transfer amount exceeds balance");
            _rebasingTotalSupply -= amountToDeduct;
        } else {
            require(_balances[sender] >= amountToDeduct, "ERC20: transfer amount exceeds balance");
            _nonRebasingTotalSupply -= amountToDeduct;
        }
        _balances[sender] -= amountToDeduct;
        // adding to recipient
        uint256 amountToAdd = amount;
        if (_isRebasingAccount(recipient)) {
            amountToAdd = _dividedByMultiplier(amount);
            _rebasingTotalSupply += amountToAdd;
        } else {
            _nonRebasingTotalSupply += amountToAdd;
        }
        _balances[recipient] += amountToAdd;
        emit Transfer(sender, recipient, amount);
    }

    /**
     * Mint DSD tokens
     * @param account User's wallet
     * @param amount Amount of DSD to mint
     */
    function mint(address account, uint256 amount) external auth {
        __mint(account, amount);
    }

    function rbmMint(address account, uint256 amount) external returns (uint) {
        require(rebaseManagers[msg.sender] == 1, "!RBM");
        return __mint(account, amount);
    }

    function __mint(address account, uint256 amount) internal returns (uint) {
        require(account != address(0) && amount > 0, "ZERO_ARG");
        _beforeTokenTransfer(address(0), account, amount);

        uint256 amountToAdd = amount;
        if (_isRebasingAccount(account)) {
            amountToAdd = _dividedByMultiplier(amount);
            _rebasingTotalSupply += amountToAdd;
        } else {
            _nonRebasingTotalSupply += amountToAdd;
        }
        _balances[account] += amountToAdd;
        esltokenMinter.refreshReward(account);
        emit Transfer(address(0), account, amount);
        return amountToAdd;
    }

    /**
     * Burn DSD tokens
     * @param account User's wallet
     * @param amount Amount of DSD to mint
     */
    function burn(address account, uint256 amount) public returns (uint256) {
        require(account != address(0), "ERC20: burn from the zero address");
        _beforeTokenTransfer(account, address(0), amount);

        uint256 amountToDeduct = amount;
        if (_isRebasingAccount(account)) {
            amountToDeduct = _dividedByMultiplier(amount);
            require(_balances[account] >= amountToDeduct, "ERC20: burn amount exceeds balance");
            _rebasingTotalSupply -= amountToDeduct;
        } else {
            require(_balances[account] >= amountToDeduct, "ERC20: burn amount exceeds balance");
            _nonRebasingTotalSupply -= amountToDeduct;
        }
        _balances[account] -= amountToDeduct;
        esltokenMinter.refreshReward(account);
        emit Transfer(account, address(0), amount);

        return amountToDeduct;
    }

    /**
     * @notice Set the multiplier for rebasing
     * Only available to rebase managers
     */
    function setMultiplier(uint256 multiplier_) external {
        require(rebaseManagers[msg.sender] == 1, "!RBM");
        _setMultiplier(multiplier_);
        emit TokenSupplyChanged(totalSupply(), _timesMultiplier(_rebasingTotalSupply), _nonRebasingTotalSupply);
    }

    function _setMultiplier(uint256 multiplier_) internal {
        uint256 oldMultiplier = multiplier;
        multiplier = multiplier_;
        lastUpdateTime = block.timestamp;
        emit MultiplierChange(oldMultiplier, multiplier);
    }

    /**
     * State of the rebase multiplier
     * @return _multiplier Rebase multiplier
     * @return _lastUpdateTime Rebase multiplier last updated at
     */
    function getMultiplier() external view returns (uint256 _multiplier, uint256 _lastUpdateTime) {
        _multiplier = multiplier;
        _lastUpdateTime = lastUpdateTime;
    }

    /* utils */
    function _timesMultiplier(uint256 input) internal view returns (uint256) {
        return (input * multiplier) / ONE;
    }

    function _dividedByMultiplier(uint256 input) internal view returns (uint256) {
        return (input * ONE) / multiplier;
    }

    function setRebasingOption(bool isRebasing) external {
        uint256 userBalance = _balances[_msgSender()];

        if (isRebasing && _rebaseOptions[_msgSender()] != RebaseOption.REBASING) {
            _rebaseOptions[_msgSender()] = RebaseOption.REBASING;
            _nonRebasingTotalSupply -= userBalance;
            _rebasingTotalSupply += _dividedByMultiplier(userBalance);
            _balances[_msgSender()] = _dividedByMultiplier(userBalance);
        } else if (!isRebasing && _rebaseOptions[_msgSender()] != RebaseOption.NON_REBASING) {
            _rebaseOptions[_msgSender()] = RebaseOption.NON_REBASING;
            _rebasingTotalSupply -= userBalance;
            _nonRebasingTotalSupply += _timesMultiplier(userBalance);
            _balances[_msgSender()] = _timesMultiplier(userBalance);
        }
        emit TokenSupplyChanged(totalSupply(), _timesMultiplier(_rebasingTotalSupply), _nonRebasingTotalSupply);
        emit SetRebasingOption(_msgSender(), _rebaseOptions[_msgSender()]);
    }

    function _isRebasingAccount(address account) internal view returns (bool) {
        require(_rebaseOptions[account] != RebaseOption.UNKNOWN, "rebasing option not set");
        return (_rebaseOptions[account] == RebaseOption.REBASING);
    }

    function isRebasingAccount(address account) public view returns (bool) {
        return
            (_rebaseOptions[account] == RebaseOption.REBASING) ||
            (_rebaseOptions[account] == RebaseOption.UNKNOWN && !account.isContract());
    }

    // withdraw random token transfer into this contract
    function sweepERC20Token(address _token, address to) external auth {
        require(_token != address(this), "!safe");
        IERC20 tokenToSweep = IERC20(_token);
        tokenToSweep.safeTransfer(to, tokenToSweep.balanceOf(address(this)));
    }

    function _pause() internal whenNotPaused {
        paused = true;
        // emit Paused(_msgSender());
    }

    function _unpause() internal whenPaused {
        paused = false;
        // emit Unpaused(_msgSender());
    }

    function pause() external auth {
        _pause();
    }

    function unpause() external auth {
        _unpause();
    }

    modifier setDefaultRebasingOption(address account) {
        // defaults to either REBASING or NON_REBASING, depending on whether account is a contract
        //  the isContract() could be volatile, i.e. an EOA can turn into a contract in the future
        // hence we set it to a value 1st time the account address is used in a transfer
        // account owner still has the ability to change this option via setRebasingOption() at any moment
        if (_rebaseOptions[account] == RebaseOption.UNKNOWN)
            _rebaseOptions[account] = account.isContract() ? RebaseOption.NON_REBASING : RebaseOption.REBASING;
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    /************************** LayerZero required functions below **************************/

    function token() external view override returns (address) {
        return address(this);
    }

    function circulatingSupply() external view virtual override returns (uint256) {
        return totalSupply() - nonRebasingSupply();
    }

    function _creditTo(uint16 /* _srcChainId */, address _toAddress, uint _amount) internal override returns (uint256) {
        return __mint(_toAddress, _amount);
    }

    function _debitFrom(
        address _from,
        uint16 /* _dstChainId */,
        bytes memory /* _toAddress */,
        uint _amount
    ) internal override returns (uint256) {
        return burn(_from, _amount);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

interface IesLTOKEN {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function mint(address user, uint256 amount) external returns (bool);

    function burn(address user, uint256 amount) external returns (bool);
}

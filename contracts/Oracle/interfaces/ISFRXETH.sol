pragma solidity ^0.5.16;

interface ISFRXETH {
     function pricePerShare() external view returns (uint256);
}
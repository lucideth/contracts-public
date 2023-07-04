// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.5.16;
import "../../Utils/SafeMath.sol";

contract ISubOracle {
    using SafeMath for uint256;
    function latestAnswer() external view  returns (uint256 rate);
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }
    function scaleBy(
        uint256 x,
        uint256 to,
        uint256 from
    ) internal pure returns (uint256) {
        if (to > from) {
            x = x.mul(10**(to - from));
        } else if (to < from) {
            x = x.div(10**(from - to));
        }
        return x;
    }
    function validate() external {
    }
}
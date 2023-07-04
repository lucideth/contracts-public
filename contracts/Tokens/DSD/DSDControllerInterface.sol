pragma solidity ^0.5.16;

import "../LLTokens/LLToken.sol";

contract DSDControllerInterface {
    function getDSDAddress() public view returns (address);

    function getMintableDSD(address minter) public view returns (uint, uint);

    function mintDSD(address minter, uint mintDSDAmount) external returns (uint);

    function repayDSD(address repayer, uint repayDSDAmount) external returns (uint);

    function liquidateDSD(
        address borrower,
        uint repayAmount,
        LLTokenInterface llTokenCollateral
    ) external returns (uint, uint);

    function _initializeLsDSDState(uint blockNumber) external returns (uint);

    function updateLsDSDMintIndex() external returns (uint);

    function calcDistributeDSDMinterLs(address dsdMinter) external returns (uint, uint, uint, uint);

    function getDSDRepayAmount(address account) public view returns (uint);
}

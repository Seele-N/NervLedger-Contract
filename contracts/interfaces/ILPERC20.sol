// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ILPERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAction {
    function onSend(address from, address to, address matchId, uint256 quantity, bytes calldata data) external;
}

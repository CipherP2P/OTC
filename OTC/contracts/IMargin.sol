// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)
pragma solidity ^0.8.14;


interface IMargin {
    function tokenSend(
        address _token,
        address _recipient,
        uint _amount
    ) external;
}

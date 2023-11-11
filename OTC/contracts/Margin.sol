// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./TransferHelper.sol";
contract Margin is Ownable {

    address public caller;

    modifier onlyCall() {
        require(caller == msg.sender, "Margin:: No casting permission, illegal operation");
        _;
    }

    receive() external payable {}
    fallback() external payable {}

    function _tokenSend(
        address _token,
        address _recipient,
        uint _amount
    ) private returns (bool result) {
        if(_token == address(0)){
            Address.sendValue(payable(_recipient),_amount);
            result = true;
        }else{
            IERC20 token = IERC20(_token);
            result = token.transfer(_recipient,_amount);
        }
    }

    function tokenSend(
        address _token,
        address _recipient,
        uint _amount
    ) external onlyCall {
        require(_tokenSend(_token,_recipient,_amount),"Margin::transfer fail");
    }

    function updateCall(
		address _caller
	) public onlyOwner {
		_updateCall(_caller);
	}

	function _updateCall(
		address _caller
	) private {
		require(_caller != address(0),"Margin::invalid signing address");
		caller = _caller;
	}
}

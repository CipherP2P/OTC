// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SafeMath.sol";
import "./TransferHelper.sol";
import "./ECDSA.sol";
import "./IMargin.sol";
contract OTC is Ownable {

    using SafeMath for uint256;

    struct Advert {
        address issuer;
        address token;
        uint amount;
        uint surplus;
        uint min;
        uint max;
        uint side;
    }

    struct Account {
        address fee;
        address margin;
    }

    struct MarginAmount {
        uint total;
        uint surplus;
    }

    // signType 1:完成订单 2:撤销订单 3:下架广告
    struct AllowSign {
        bytes32 aid;
        address sender;
        uint signType;
        uint amount;
        uint fee;
        uint buyFee;
        uint sellFee;
        bytes signature;
        uint time;
    }

    // 资金账户
    Account public fundAccount;

    // 保证金
    mapping(address => mapping(address => MarginAmount)) public marginBook;

    // 广告表
    mapping(bytes32 => Advert) public fundAdvert;

    // 支付 账户锁
    mapping(address => bool) public lockPay;

    // 签名验证地址
	address private signer;

    // 禁用的证明
	mapping(bytes => bool) public expired;

    // 缴纳保证金
    event PayMargin(address payer,address token,uint amount,uint total,uint surplus);
    // 退还保证金
    event BackMargin(uint id,address recipient,address token,uint amount,uint total,uint surplus);
    // 发布广告
    event Publish(bytes32 aid,address issuer,address token,uint amount,uint legal,uint price,uint min,uint max,uint side,string payType,string desc);
    // 支付数字货币资产
    event Payment(bytes32 aid,address sender,address token,uint amount,string payType,string desc);
    // 完成订单
    event Complete(bytes32 aid,address recipient,address token,uint amount,uint feeAmount,uint surplus,bytes signature);
    // 撤回数字货币资产
    event Revoke(bytes32 aid,address recipient,address token,uint amount,uint feeAmount,bytes signature);

    constructor(
        address _margin,
        address _fee,
        address _signer
    ) {
        _verifySign(_signer);
        _setAccount(_margin,_fee);
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
    ) external onlyOwner {
        _tokenSend(_token,_recipient,_amount);
    }

    // 支付保证金
    function payMargin(
        address token,
        uint amount
    ) external payable {
        if(token == address(0)) {
            require(msg.value == amount,"OTC::Input eth is not accurate");
            require(_tokenSend(token,fundAccount.margin,amount),"OTC:Eth transfer fail");
        }else {
            TransferHelper.safeTransferFrom(token,msg.sender,fundAccount.margin,amount);
        }

        marginBook[msg.sender][token].total = marginBook[msg.sender][token].total.add(amount);
        marginBook[msg.sender][token].surplus = marginBook[msg.sender][token].surplus.add(amount);
        emit PayMargin(msg.sender,token,amount,marginBook[msg.sender][token].total,marginBook[msg.sender][token].surplus);
    }

    struct BackMarginParams {
        uint id;
        address recipient;
        address token;
        uint amount;
    }

    // 返还保证金
    function backMargin(
        BackMarginParams[] memory params
    ) external onlyOwner {
        for(uint i = 0; i < params.length; i++) {
            _backMargin(params[i].id,params[i].recipient,params[i].token,params[i].amount);
        }
    }

    function _backMargin(
        uint id,
        address recipient,
        address token,
        uint amount
    ) private {
        // 发放token
        IMargin(fundAccount.margin).tokenSend(token,recipient,amount);

        // 保证金检查
        require(marginBook[recipient][token].total >= amount,"OTC:Refund of deposit exceeding limit");
        require(marginBook[recipient][token].surplus >= amount,"OTC:Refund of deposit exceeding limit");
        // 减少保证金
        marginBook[recipient][token].total = marginBook[recipient][token].total.sub(amount);
        marginBook[recipient][token].surplus = marginBook[recipient][token].surplus.sub(amount);
        emit BackMargin(id,recipient,token,amount,marginBook[recipient][token].total,marginBook[recipient][token].surplus);
    }

    struct SignParams {
        bytes32 aid;
        uint signType;
        address recipient;
        address sender;
        address token;
        uint amount;
        uint buyFee;
        uint sellFee;
        uint time;
    }

    function hashMsg(
        SignParams memory params
	) internal view returns (bytes32 msghash) {
		return	keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked(block.chainid,params.aid,params.signType,params.recipient,params.sender,params.token,params.amount,params.buyFee,params.sellFee,params.time))
            )
        );
	}

    function _trust(
        SignParams memory params,
        bytes memory signature
    ) private {
        require(!expired[signature],"OTC::certificate expired");
        address prove = ECDSA.recover(hashMsg(params), signature);
        require(signer == prove,"OTC::invalid certificate");	
        expired[signature] = true;
    }

    // 生成广告ID
    function _initAdvert() internal view returns (bytes32 msghash) {
		return	keccak256(
            abi.encodePacked(
                "AdvertID:",
                keccak256(abi.encodePacked(msg.sender,block.chainid,block.number,block.timestamp))
            )
        );
	}



    struct PublishParams {
        address token;
        uint amount;
        uint side;
        uint legal;
        uint price;
        uint min;
        uint max;
        string payType;
        string desc;
    }
    // 发布广告 side 1:卖币 2:买币
    function publish(
        PublishParams memory params
    ) external payable {
        require(msg.sender == tx.origin,"OTC::Illegal caller");
		require(!Address.isContract(msg.sender),"OTC::Prohibit contract calls");
        require(marginBook[msg.sender][params.token].surplus >= params.amount,"OTC:Refund of deposit exceeding limit");

        // 如果是卖单 接收锁定代币
        if(params.side == 1) {
            if(params.token == address(0)) {
                require(msg.value == params.amount,"OTC::Input eth is not accurate");
            }else {
                TransferHelper.safeTransferFrom(params.token,msg.sender,address(this),params.amount);
            }
        }
		
        //构建广告
        bytes32 aid = _initAdvert();
        fundAdvert[aid] = Advert({
            issuer:msg.sender,
            token:params.token,
            amount:params.amount,
            surplus:params.amount,
            min:params.min,
            max:params.max,
            side:params.side
        });

        // 记录保证金
        marginBook[msg.sender][params.token].surplus = marginBook[msg.sender][params.token].surplus.sub(params.amount);
        
        emit Publish(aid,msg.sender,params.token,params.amount,params.legal,params.price,params.min,params.max,params.side,params.payType,params.desc);
    }


    // 买单广告 支付
    function payment(
        bytes32 aid,
        uint amount,
        string memory payType,
        string memory desc
    ) external payable {
        require(msg.sender == tx.origin,"OTC::Illegal caller");
		require(!Address.isContract(msg.sender),"OTC::Prohibit contract calls");
        require(msg.sender != fundAdvert[aid].issuer,"OTC::Cannot purchase by oneself");
        // require(amount <= fundAdvert[aid].surplus,"OTC::Payment amount exceeds");
        require(!lockPay[msg.sender],"OTC::There are unfinished transactions");
        require(fundAdvert[aid].min <= amount,"OTC::>= min");
        require(fundAdvert[aid].max >= amount,"OTC::<= max");

        // 接收代币
		if(fundAdvert[aid].token == address(0)) {
			require(msg.value == amount,"OTC::Input eth is not accurate");
		}else {
			TransferHelper.safeTransferFrom(fundAdvert[aid].token,msg.sender,address(this),amount);
		}

        // 账户 支付锁
        lockPay[msg.sender] = true;
        emit Payment(aid,msg.sender,fundAdvert[aid].token,amount,payType,desc);
    }


    function complete(
        AllowSign memory params
    ) external {
        require(fundAdvert[params.aid].issuer != address(0),"OTC::Invalid order");
        _trust(SignParams({
            aid:params.aid,
            signType:params.signType,
            recipient:msg.sender,
            sender:params.sender,
            token:fundAdvert[params.aid].token,
            amount:params.amount,
            buyFee:params.buyFee,
            sellFee:params.sellFee,
            time:params.time
        }),params.signature);


        if(params.signType == 1) {
            _complete(params);
        } else if(params.signType == 2) {
            _revokeOrder(params);
        } else if(params.signType == 3) {
            _revokeAdvert(params);
        } else {
            revert("OTC::Illegal operation type");
        }
    }

    function _complete(
        AllowSign memory params
    ) private {
        address token = fundAdvert[params.aid].token;

        // 数字货币 放币
        if(params.buyFee > 0) {
            require(_tokenSend(token,fundAccount.fee,params.buyFee),"OTC::complete buyFee transfer fail");
        }
        if(params.sellFee > 0) {
            require(_tokenSend(token,fundAccount.fee,params.sellFee),"OTC::complete sellFee transfer fail");
        }
        if(params.amount > 0) {
            require(_tokenSend(token,msg.sender,params.amount),"OTC::complete transfer fail");
        }
        
        // 账户 支付锁
        lockPay[params.sender] = false;

        uint reAmount = 0;
        // 广告剩余量减少
        if(fundAdvert[params.aid].side == 1) {
            fundAdvert[params.aid].surplus = fundAdvert[params.aid].surplus.sub(params.buyFee);
            fundAdvert[params.aid].surplus = fundAdvert[params.aid].surplus.sub(params.sellFee);
            fundAdvert[params.aid].surplus = fundAdvert[params.aid].surplus.sub(params.amount);
            reAmount = params.amount.add(params.buyFee).add(params.sellFee);

        }else if(fundAdvert[params.aid].side == 2) {
            fundAdvert[params.aid].surplus = fundAdvert[params.aid].surplus.sub(params.buyFee);
            fundAdvert[params.aid].surplus = fundAdvert[params.aid].surplus.sub(params.amount);
            reAmount = params.amount.add(params.buyFee);
        }
        
        // 重置保证金
        address store = fundAdvert[params.aid].issuer;
        marginBook[store][token].surplus = marginBook[store][token].surplus.add(reAmount);
        if(marginBook[store][token].surplus > marginBook[store][token].total) {
            marginBook[store][token].surplus = marginBook[store][token].total;
        }
        

        emit Complete(params.aid,msg.sender,token,params.amount,params.fee,fundAdvert[params.aid].surplus,params.signature);
    }

    function _revokeOrder(
        AllowSign memory params
    ) private {
        address token = fundAdvert[params.aid].token;

        // 返还数字货币
        if(params.fee > 0) {
            require(_tokenSend(token,fundAccount.fee,params.fee),"OTC::revokeOrder fee transfer fail");
        }
        if(params.amount > 0) {
            require(_tokenSend(token,msg.sender,params.amount),"OTC::revokeOrder transfer fail");
        }

        // 账户 支付锁
        lockPay[params.sender] = false;

        emit Revoke(params.aid,msg.sender,token,params.amount,params.fee,params.signature);
    }

    function _revokeAdvert(
        AllowSign memory params
    ) private {
        require(fundAdvert[params.aid].issuer == msg.sender,"OTC::Invalid order");


        // 返还数字货币
        address token = fundAdvert[params.aid].token;
        if(params.fee > 0) {
            require(_tokenSend(token,fundAccount.fee,params.fee),"OTC::revokeAdvert fee transfer fail");
        }
        if(params.amount > 0) {
            require(_tokenSend(token,msg.sender,params.amount),"OTC::revokeAdvert transfer fail");
        }

        // 重置保证金
        marginBook[msg.sender][token].surplus = marginBook[msg.sender][token].surplus.add(fundAdvert[params.aid].surplus);
        if(marginBook[msg.sender][token].surplus > marginBook[msg.sender][token].total) {
            marginBook[msg.sender][token].surplus = marginBook[msg.sender][token].total;
        }

        // 下架广告
        fundAdvert[params.aid].surplus = 0;

        emit Revoke(params.aid,msg.sender,token,params.amount,params.fee,params.signature);
    }

    function setAccount(
		address _margin,
		address _fee
	) public onlyOwner {
		_setAccount(_margin,_fee);
	}

	function _setAccount(
        address _margin,
		address _fee
	) private {
		require(_margin != address(0),"OTC::invalid margin address");
        require(_fee != address(0),"OTC::invalid fee address");
		fundAccount.fee = _fee;
        fundAccount.margin = _margin;
	}

    function verifySign(
		address _signer
	) public onlyOwner {
		_verifySign(_signer);
	}

	function _verifySign(
		address _signer
	) private {
		require(_signer != address(0),"OTC::invalid signing address");
		signer = _signer;
	}
}

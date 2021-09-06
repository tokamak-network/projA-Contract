// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract tokenEscrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct UserInfoAmount {
        uint256 inputamount;
        uint256 totaloutputamount;
        uint256 inputTime;
        uint256 monthlyReward;
    }

    struct UserInfoClaim {
        uint256 claimTime;
        uint256 claimAmount;
    }

    struct WhiteList {
        uint256 amount;
    }

    event addList(
        address account,
        uint256 amount
    );

    event delList(
        address account,
        uint256 amount
    );

    event Buyinfo(
        address user,
        uint256 inputAmount,
        uint256 totalOutPutamount,
        uint256 inputTime,
        uint256 monthlyReward
    );

    event Claiminfo(
        address user,
        uint256 claimAmount,
        uint256 claimTime
    );

    event Withdrawinfo(
        address user,
        uint256 withdrawAmount
    );
    
    uint256 rate;
    uint256 totalgetAmount;

    uint256 public startTime = 0;
    uint256 public endTime = 0;

    IERC20 public saleToken;
    IERC20 public getToken;

    mapping (address => UserInfoAmount) public usersAmount;
    mapping (address => UserInfoClaim) public usersClaim;
    mapping (address => WhiteList) public usersWhite;


    constructor(address _saleTokenAddress, address _getTokenAddress, uint256 _rate) {
        saleToken = IERC20(_saleTokenAddress);
        getToken = IERC20(_getTokenAddress);
        rate = _rate;
    }

    function rateChange(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function calculate(uint256 _amount) internal view returns (uint256){
        return rate*_amount;
    }

    function startTimeCalcul(uint256 _time) public pure returns (uint256) {
        return _time + 180 days;
    }

    function endTimeCalcul(uint256 _time) public pure returns (uint256) {
        return _time + 360 days;
    }

    function claimAmount(
        address _account
    ) external view returns (uint256) {
        UserInfoAmount storage user = usersAmount[_account];

        require(user.inputamount > 0, "user isn't buy");
        require(block.timestamp > startTime, "need to time for claim");
        
        UserInfoClaim storage userclaim = usersClaim[msg.sender];

        uint difftime = block.timestamp - startTime;
        uint monthTime = 30 days;

        if (difftime < monthTime) {
            uint period = 1;
            uint256 reward = (user.monthlyReward*period)-userclaim.claimAmount;
            return reward;
        } else {
            uint period = (difftime/monthTime)+1;
            if (period >= 12) {
                uint256 reward = user.totaloutputamount-userclaim.claimAmount;
                return reward; 
            } else {
                uint256 reward = (user.monthlyReward*period)-userclaim.claimAmount;
                return reward;
            }
        }
    }
    
    function calculClaimAmount(
        uint256 _nowtime, 
        uint256 _preclaimamount,
        uint256 _monthlyReward,
        uint256 _usertotaloutput
    ) internal view returns (uint256) {
        uint difftime = _nowtime- startTime;
        uint monthTime = 30 days;

        if (difftime < monthTime) {
            uint period = 1;
            uint256 reward = (_monthlyReward*period)-_preclaimamount;
            return reward;
        } else {
            uint period = (difftime/monthTime)+1;
            if (period >= 12) {
                uint256 reward = _usertotaloutput-_preclaimamount;
                return reward; 
            } else {
                uint256 reward = (_monthlyReward*period)-_preclaimamount;
                return reward;
            }
        }
    }
    
    function addwhitelist(address _account,uint256 _amount) external onlyOwner {
        WhiteList storage userwhite = usersWhite[_account];
        userwhite.amount = userwhite.amount + _amount;

        emit addList(_account, _amount);
    }

    function delwhitelist(address _account, uint256 _amount) external onlyOwner {
        WhiteList storage userwhite = usersWhite[_account];
        userwhite.amount = userwhite.amount - _amount;

        emit delList(_account, _amount);
    }

    function buy(
        uint256 _amount
    ) external {
        WhiteList storage userwhite = usersWhite[msg.sender];
        require(userwhite.amount >= _amount, "need to add whiteList amount");
        _buy(_amount);
        userwhite.amount = userwhite.amount - _amount;
    }

    //최초 실행 시 startTime, EndTime
    function _buy(
        uint256 _amount
    )
        internal
    {
        UserInfoAmount storage user = usersAmount[msg.sender];

        uint256 giveTokenAmount = calculate(_amount);
        uint256 tokenBalance = saleToken.balanceOf(address(this));

        require(
            tokenBalance >= giveTokenAmount,
            "don't have token amount"
        );

        uint256 tokenAllowance = getToken.allowance(msg.sender, address(this));
        require(tokenAllowance >= _amount, "ERC20: transfer amount exceeds allowance");

        getToken.safeTransferFrom(msg.sender, address(this), _amount);
        getToken.safeTransfer(owner(), _amount);

        user.inputamount = user.inputamount+_amount;
        user.totaloutputamount = user.totaloutputamount+giveTokenAmount;
        user.monthlyReward = user.totaloutputamount/12;
        user.inputTime = block.timestamp;

        if(startTime == 0) {
            startTime = startTimeCalcul(block.timestamp);
            endTime = endTimeCalcul(startTime);
        }

        totalgetAmount = totalgetAmount+_amount;

        emit Buyinfo(
            msg.sender, 
            user.inputamount, 
            user.totaloutputamount,
            user.inputTime,
            user.monthlyReward
        );
    }

    function claim() external {
        UserInfoAmount storage user = usersAmount[msg.sender];
        UserInfoClaim storage userclaim = usersClaim[msg.sender];

        require(user.inputamount > 0, "need to buy the token");
        require(block.timestamp >= startTime, "need the time for claim");
        require(!(user.totaloutputamount == userclaim.claimAmount), "already getAllreward");

        uint256 giveTokenAmount = calculClaimAmount(block.timestamp, userclaim.claimAmount, user.monthlyReward, user.totaloutputamount);
    
        require(user.totaloutputamount - userclaim.claimAmount >= giveTokenAmount, "user is already getAllreward");
        require( saleToken.balanceOf(address(this)) >= giveTokenAmount, "don't have saleToken in pool");

        userclaim.claimAmount = userclaim.claimAmount + giveTokenAmount;
        userclaim.claimTime = block.timestamp;

        saleToken.safeTransfer(msg.sender, giveTokenAmount);

        emit Claiminfo(msg.sender, userclaim.claimAmount, userclaim.claimTime);
    }


    function withdraw(uint256 _amount) external onlyOwner {
        require(
            saleToken.balanceOf(address(this)) >= _amount,
            "don't have token amount"
        );
        saleToken.safeTransfer(msg.sender, _amount);

        emit Withdrawinfo(msg.sender, _amount);
    }

}

pragma solidity ^0.4.13;

import "./Fund.sol";
import "./math/SafeMath.sol";
import "./math/Math.sol";
import "./zeppelin/DestructibleModified.sol";

/**
  * @title NavCalulator
  * @author CoinAlpha, Inc. <contact@coinalpha.com>
  *
  * 计算净资产值和其他基金变量的模块
  * 这是处理所需逻辑的基金合同的支持模块
  * 计算更新后的navPerShare和其他与基金相关的变量
  * 经过的时间和变化的组合的值，作为由所述数据馈送提供。
  */

contract INavCalculator {
  function calculate()
    public returns (
      uint lastCalcDate,
      uint navPerShare,
      uint lossCarryforward,
      uint accumulatedMgmtFees,
      uint accumulatedAdminFees
    ) {}
}

contract NavCalculator is DestructibleModified {
  using SafeMath for uint;
  using Math for uint;

  address public fundAddress;

  // Modules
  IFund fund;

  // 此修饰符仅适用于本合约中的所有外部方法
  // 主要基金合同可以使用这个模块
  modifier onlyFund {
    require(msg.sender == fundAddress);
    _;
  }

  function NavCalculator() public {}

  event LogNavCalculation(
    uint indexed timestamp,
    uint elapsedTime,
    uint grossAssetValueLessFees,
    uint netAssetValue,
    uint totalSupply,
    uint adminFeeInPeriod,
    uint mgmtFeeInPeriod,
    uint performFeeInPeriod,
    uint performFeeOffsetInPeriod,
    uint lossPaybackInPeriod
  );

  // Calculate nav and allocate fees
  function calculate()
    public 
    onlyFund 
    constant 
    returns (
      uint lastCalcDate,
      uint navPerShare,
      uint lossCarryforward,
      uint accumulatedMgmtFees,
      uint accumulatedAdminFees
      )
    {

      // setting lastCalcDate for use as "now" for this function
      lastCalcDate = now;

      // Set the initial value of the variables below from the last NAV calculation
      uint netAssetValue = sharesToUsd(fund.totalSupply());
      uint elapsedTime = lastCalcDate - fund.lastCalcDate();
      lossCarryforward = fund.lossCarryforward();
      accumulatedMgmtFees = fund.accumulatedMgmtFees();
      accumulatedAdminFees = fund.accumulatedAdminFees();

      // The new grossAssetValue equals the updated value, denominated in ether, of the exchange account,
      // plus any amounts that sit in the fund contract, excluding unprocessed subscriptions
      // and unwithdrawn investor payments.
      // Removes the accumulated management and administrative fees from grossAssetValue
      uint grossAssetValueLessFees = dataFeed.value().add(fund.ethToUsd(fund.getBalance())).sub(accumulatedMgmtFees).sub(accumulatedAdminFees);

      // 计算自上次净资产值计算以来累计的基本管理费用
      uint mgmtFee = getAnnualFee(elapsedTime, fund.mgmtFeeBps());
      uint adminFee = getAnnualFee(elapsedTime, fund.adminFeeBps());

      // Calculate the gain/loss based on the new grossAssetValue and the old netAssetValue
      int gainLoss = int(grossAssetValueLessFees) - int(netAssetValue) - int(mgmtFee) - int(adminFee);

      uint performFee = 0;
      uint performFeeOffset = 0;

      // if current period gain
      if (gainLoss >= 0) {
        uint lossPayback = Math.min256(uint(gainLoss), lossCarryforward);

        // Update the lossCarryforward and netAssetValue variables
        lossCarryforward = lossCarryforward.sub(lossPayback);
        performFee = getPerformFee(uint(gainLoss).sub(lossPayback));
        netAssetValue = netAssetValue.add(uint(gainLoss)).sub(performFee);
      
      // if current period loss
      } else {
        performFeeOffset = Math.min256(getPerformFee(uint(-1 * gainLoss)), accumulatedMgmtFees);
        // 更新 lossCarryforward 和 netAssetValue 变量
        lossCarryforward = lossCarryforward.add(uint(-1 * gainLoss)).sub(getGainGivenPerformFee(performFeeOffset));
        netAssetValue = netAssetValue.sub(uint(-1 * gainLoss)).add(performFeeOffset);
      }

      // 更新剩余的状态变量并将它们返回到基金合同
      accumulatedAdminFees = accumulatedAdminFees.add(adminFee);
      accumulatedMgmtFees = accumulatedMgmtFees.add(performFee).sub(performFeeOffset);
      navPerShare = toNavPerShare(netAssetValue);

      LogNavCalculation(lastCalcDate, elapsedTime, grossAssetValueLessFees, netAssetValue, fund.totalSupply(), adminFee, mgmtFee, performFee, performFeeOffset, lossPayback);

      return (lastCalcDate, navPerShare, lossCarryforward, accumulatedMgmtFees, accumulatedAdminFees);
  }

  // ********* ADMIN *********

  // 更新基金合同的地址
  function setFund(address _address)
    public 
    onlyOwner 
  {
    fund = IFund(_address);
    fundAddress = _address;
  }


  // ********* HELPERS *********

  // 返回与已过时间累积的年费和年费率相关的费用金额
  // 相当于：年费比例*资金总额供给*（经过的秒数/一年中的秒数）
  // 与基金总额相同的面额
  function getAnnualFee(uint elapsedTime, uint annualFeeBps) 
    internal 
    constant 
    returns (uint feePayment) 
  {
    return annualFeeBps.mul(sharesToUsd(fund.totalSupply())).div(10000).mul(elapsedTime).div(31536000);
  }

  // 返回投资组合价值给定收益的业绩费用
  function getPerformFee(uint _usdGain) 
    internal 
    constant 
    returns (uint performFee) 
  {
    return fund.performFeeBps().mul(_usdGain).div(10 ** fund.decimals());
  }

  // 返回给定绩效费用的投资组合价值收益
  function getGainGivenPerformFee(uint _performFee) 
    internal 
    constant 
    returns (uint usdGain) 
  {
    return _performFee.mul(10 ** fund.decimals()).div(fund.performFeeBps());
  }

  // 根据当前的每股净资产值，将股份转换为相应的美元数额
  function sharesToUsd(uint _shares) 
    internal 
    constant 
    returns (uint usd) 
  {
    return _shares.mul(fund.navPerShare()).div(10 ** fund.decimals());
  }

  // 将总基金净资产值转换为每股净资产值
  function toNavPerShare(uint _balance) 
    internal 
    constant 
    returns (uint) 
  {
    return _balance.mul(10 ** fund.decimals()).div(fund.totalSupply());
  }
}

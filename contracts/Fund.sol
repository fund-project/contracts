pragma solidity ^0.4.13;

import "./math/SafeMath.sol";
import "./zeppelin/DestructiblePausable.sol";
import "./NavCalculator.sol";
import "./InvestorActions.sol";

/**
  * 该协议使管理人员能够创建基于区块链的资产管理工具
  * 管理投资者提供的外部资金。 该协议使用区块链
  * 履行资产分离保管，资产净值计算，
  * 费用会计，以及认购/赎回管理。
  * 该项目的目标是消除中间商施加的设置和运营成本
  * 在传统基金中，同时最大限度地提高投资者的透明度并降低欺诈风险。
  */

contract IFund {
  uint    public decimals;
  uint    public minInitialSubscription;
  uint    public minSubscription;
  uint    public minRedemptionShares;
  uint    public totalPendingSubscription;
  uint    public totalPendingWithdrawal;
  uint    public totalSharesPendingRedemption;
  uint    public totalSupply;

  uint    public adminFeeBps;
  uint    public mgmtFeeBps;
  uint    public performFeeBps;

  uint    public lastCalcDate;
  uint    public navPerShare;
  uint    public accumulatedMgmtFees;
  uint    public accumulatedAdminFees;
  uint    public lossCarryforward;

  function getInvestor(address _addr)
    public 
    returns (
      uint totalAllocation,
      uint pendingSubscription,
      uint sharesOwned,
      uint sharesPendingRedemption,
      uint pendingWithdrawal
      ) {}
  
  function getBalance()
    public 
    returns (uint ethAmount) {}
}

contract Fund is DestructiblePausable {
  using SafeMath for uint;

  // 常量 在合约开始时设定
  string  public name;                         // 基金名称
  string  public symbol;                       // 基金 token 代码
  uint    public decimals;                     // 用于显示navPerShare的小数位数
  uint    public minInitialSubscription;       // 新投资者可以认购的最低金额
  uint    public minSubscription;              // 现有投资者可以认购的最小数量的
  uint    public minRedemptionShares;          // 投资者可以申请赎回的最低股份数量
  uint    public adminFeeBps;                  // 年度管理费（如有），以基点计算
  uint    public mgmtFeeBps;                   // 年度基本管理费（如有），以基点计算
  uint    public performFeeBps;                // 绩效管理费以基准点收益获得
  address public manager;                      // 经理账户地址允许撤销基础和绩效管理费用
  address public exchange;                     // 经理进行交易的交易账户的地址。

  // 变量 在每次调用calcNav函数后更新
  uint    public lastCalcDate;
  uint    public navPerShare;
  uint    public accumulatedMgmtFees;
  uint    public accumulatedAdminFees;
  uint    public lossCarryforward;

  // 基金余额
  uint    public totalPendingSubscription;       // 尚未处理的认购请求总数
  uint    public totalSharesPendingRedemption;   // 尚未处理的赎回请求
  uint    public totalPendingWithdrawal;         // 尚未被投资者撤回的总付款
  uint    public totalSupply;                    // 已发行股份总数

  // Modules: 在可能的情况下，将资金逻辑委托给下面的模块合同，以便在合同部署后对其进行修补和升级
  INavCalculator   public navCalculator;         // 计算净资产值
  IInvestorActions public investorActions;       // 执行投资者操作，例如认购，赎回和提款

  // 该结构追踪特定投资者地址的基金相关余额
  struct Investor {
    uint totalAllocation;                  // 以Ether计价的投资者总分配
    uint pendingSubscription;              // 由投资者存入但尚未由经理处理的Ether
    uint sharesOwned;                         // 投资者拥有的股票余额。 对于投资者而言，这与ERC20余额变量相同。
    uint sharesPendingRedemption;             // 经理尚未处理的赎回请求
    uint pendingWithdrawal;                // 付款可供投资者提取
    }

  mapping (address => Investor) public investors;
  address[] investorAddresses;

  // Events
  // event LogAllocationModification(address indexed investor, uint eth);
  // event LogSubscriptionRequest(address indexed investor, uint eth, uint usdEthBasis);
  // event LogSubscriptionCancellation(address indexed investor);
  // event LogSubscription(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  // event LogRedemptionRequest(address indexed investor, uint shares);
  // event LogRedemptionCancellation(address indexed investor);
  // event LogRedemption(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  // event LogLiquidation(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  // event LogWithdrawal(address indexed investor, uint eth);
  // event LogNavSnapshot(uint indexed timestamp, uint navPerShare, uint lossCarryforward, uint accumulatedMgmtFees, uint accumulatedAdminFees);
  // event LogManagerAddressChanged(address oldAddress, address newAddress);
  // event LogExchangeAddressChanged(address oldAddress, address newAddress);
  // event LogNavCalculatorModuleChanged(address oldAddress, address newAddress);
  // event LogInvestorActionsModuleChanged(address oldAddress, address newAddress);
  // event LogDataFeedModuleChanged(address oldAddress, address newAddress);
  // event LogTransferToExchange(uint amount);
  // event LogTransferFromExchange(uint amount);
  // event LogManagementFeeWithdrawal(uint amountInEth, uint usdEthExchangeRate);
  // event LogAdminFeeWithdrawal(uint amountInEth, uint usdEthExchangeRate);

  // Modifiers
  modifier onlyFromExchange {
    require(msg.sender == exchange);
    _;
  }

  modifier onlyManager {
    require(msg.sender == manager);
    _;
  }

  // 创建基金的构造函数
  // 这个功能是可以支付的，并且可以处理作为经理自己在基金中投资的一部分而发送的任何以太币。

  function Fund (
    address _manager,
    address _exchange,
    address _navCalculator,
    address _investorActions,
    string  _name,
    string  _symbol,
    uint    _decimals,
    uint    _minInitialSubscription,
    uint    _minSubscription,
    uint    _minRedemptionShares,
    uint    _adminFeeBps,
    uint    _mgmtFeeBps,
    uint    _performFeeBps,
    uint    
  ) 
    public 
  {
      // Constants
      name = _name;
      symbol = _symbol;
      decimals = _decimals;
      minSubscription = _minSubscription;
      minInitialSubscription = _minInitialSubscription;
      minRedemptionShares = _minRedemptionShares;
      adminFeeBps = _adminFeeBps;
      mgmtFeeBps = _mgmtFeeBps;
      performFeeBps = _performFeeBps;

      // 设置与此合约交互的其他钱包/合约的地址
      manager = _manager;
      exchange = _exchange;
      navCalculator = INavCalculator(_navCalculator);
      investorActions = IInvestorActions(_investorActions);

      // 设置初始资产净值计算变量
      lastCalcDate = now;
      navPerShare = 10 ** decimals;

      // 作为经理自己的投资处理交易所转播中的现有资金和投资组合
      // 无论如何，费用都计入费用计算中，因为费用将发放给经理。

      // uint managerShares = ethToShares(exchange.balance);
      // totalSupply = managerShares;
      // investors[manager].totalAllocation = sharesToEth(managerShares);
      // investors[manager].sharesOwned = managerShares;
      
      // LogAllocationModification(manager, sharesToEth(managerShares));
      // LogSubscription(manager, managerShares, navPerShare, _managerUsdEthBasis);
    }

  // [INVESTOR METHOD]返回给定地址中包含在Investor结构中的变量
  function getInvestor (address _addr) 
    public 
    constant 
    returns (
      uint totalAllocation,
      uint pendingSubscription,
      uint sharesOwned,
      uint sharesPendingRedemption,
      uint pendingWithdrawal
      )
  {
    Investor storage investor = investors[_addr];
    return (investor.totalAllocation, investor.pendingSubscription, investor.sharesOwned, investor.sharesPendingRedemption, investor.pendingWithdrawal);
  }

  // ********* 认购申请 *********
  // 修改投资者允许的最大投资限额
  // Delegates logic to the InvestorActions module
  function modifyAllocation(address _addr, uint _allocation)
    public 
    onlyOwner 
    returns (bool success) 
  {
    // 如果他们以前的分配为零，则将该投资者添加到investorAddresses数组中
    if (investors[_addr].totalAllocation == 0) {

      // 在添加之前检查地址是否已经存在
      bool addressExists;
      for (uint i = 0; i < investorAddresses.length; i++) {
        if (_addr == investorAddresses[i]) {
          addressExists = true;
          i = investorAddresses.length;
        }
      }
      if (!addressExists) {
        investorAddresses.push(_addr);
      }
    }
    uint totalAllocation = investorActions.modifyAllocation(_addr, _allocation);
    investors[_addr].totalAllocation = totalAllocation;

    // LogAllocationModification(_addr, _allocation);
    return true;
  }

  // [INVESTOR METHOD] External wrapper for the getAvailableAllocation function in InvestorActions
  // Delegates logic to the InvestorActions module
  function getAvailableAllocation(address _addr)
    public 
    constant 
    returns (uint ethAvailableAllocation) 
  {
    return investorActions.getAvailableAllocation(_addr);
  }

  // Non-payable fallback function so that any attempt to send ETH directly to the contract is thrown
  function () 
    public 
    payable 
    onlyFromExchange 
  { 
    remitFromExchange(); 
  }

  // [INVESTOR METHOD] 通过将 ETH 转入基金来发出认购申请请求
  // Delegates logic to the InvestorActions module
  // usdEthBasis is expressed in USD cents.  For example, for a rate of 300.01, _usdEthBasis = 30001
  function requestSubscription(uint _usdEthBasis)
    public 
    whenNotPaused 
    payable 
    returns (bool success) 
  {
    var (_pendingSubscription, _totalPendingSubscription) = investorActions.requestSubscription(msg.sender, msg.value);
    investors[msg.sender].pendingSubscription = _pendingSubscription;
    totalPendingSubscription = _totalPendingSubscription;

    // LogSubscriptionRequest(msg.sender, msg.value, _usdEthBasis);
    return true;
  }

  // [INVESTOR METHOD] 取消认购申请
  // Delegates logic to the InvestorActions module
  function cancelSubscription()
    public 
    whenNotPaused 
    returns (bool success) 
  {
    var (_pendingSubscription, _pendingWithdrawal, _totalPendingSubscription, _totalPendingWithdrawal) = investorActions.cancelSubscription(msg.sender);
    investors[msg.sender].pendingSubscription = _pendingSubscription;
    investors[msg.sender].pendingWithdrawal = _pendingWithdrawal;
    totalPendingSubscription = _totalPendingSubscription;
    totalPendingWithdrawal = _totalPendingWithdrawal;

    // LogSubscriptionCancellation(msg.sender);
    return true;
  }

  // 认购申请
  function subscribe(address _addr)
    internal 
    returns (bool success) 
  {
    var (pendingSubscription, sharesOwned, shares, transferAmount, _totalSupply, _totalPendingSubscription) = investorActions.subscribe(_addr);
    investors[_addr].pendingSubscription = pendingSubscription;
    investors[_addr].sharesOwned = sharesOwned;
    totalSupply = _totalSupply;
    totalPendingSubscription = _totalPendingSubscription;

    exchange.transfer(transferAmount);
    // LogSubscription(_addr, shares, navPerShare, dataFeed.usdEth());
    // LogTransferToExchange(transferAmount);
    return true;
  }

  // 履行一个认购申请
  // Delegates logic to the InvestorActions module
  function subscribeInvestor(address _addr)
    public 
    onlyOwner 
    returns (bool success) 
  {
    subscribe(_addr);
    return true;
  }

  // 履行所有未偿付的认购申请
  // *Note re: gas - ifthere are too many investors (i.e. this process exceeds gas limits),
  //                 fallback is to subscribe() each individually
  function fillAllSubscriptionRequests()
    public 
    onlyOwner 
    returns (bool allSubscriptionsFilled) 
  {
    for (uint8 i = 0; i < investorAddresses.length; i++) {
      address addr = investorAddresses[i];
      if (investors[addr].pendingSubscription > 0) {
        subscribe(addr);
      }
    }
    return true;
  }
  
  // ********* 取款 *********
  // 取消待付提款余额中的付款
  // Delegates logic to the InvestorActions module
  function withdrawPayment()
    public 
    whenNotPaused 
    returns (bool success) 
  {
    var (payment, pendingWithdrawal, _totalPendingWithdrawal) = investorActions.withdraw(msg.sender);
    investors[msg.sender].pendingWithdrawal = pendingWithdrawal;
    totalPendingWithdrawal = _totalPendingWithdrawal;

    msg.sender.transfer(payment);

    // LogWithdrawal(msg.sender, payment);
    return true;
  }

  // ********* 资产净值计算 *********

  // 计算并更新每股资产净值，lossCarryforward（基金为弥补绩效收入而损失的金额），
  // 并累计管理费用结余。
  // 将逻辑委派给 NavCalculator 模块
  function calcNav()
    public 
    onlyOwner 
    returns (bool success) 
  {
    var (_lastCalcDate, _navPerShare, _lossCarryforward, _accumulatedMgmtFees, _accumulatedAdminFees) = navCalculator.calculate();
    lastCalcDate = _lastCalcDate;
    navPerShare = _navPerShare;
    lossCarryforward = _lossCarryforward;
    accumulatedMgmtFees = _accumulatedMgmtFees;
    accumulatedAdminFees = _accumulatedAdminFees;
    // LogNavSnapshot(lastCalcDate, navPerShare, lossCarryforward, accumulatedMgmtFees, accumulatedAdminFees);
    return true;
  }

  // ********* FEES *********
  // 从合同中提取管理费用
  function withdrawMgmtFees()
    public 
    whenNotPaused 
    onlyManager 
    returns (bool success) 
  {
    uint ethWithdrawal = accumulatedMgmtFees;
    require(ethWithdrawal <= getBalance());

    address payee = msg.sender;

    accumulatedMgmtFees = 0;
    payee.transfer(ethWithdrawal);
    // LogManagementFeeWithdrawal(ethWithdrawal, dataFeed.usdEth());
    return true;
  }

  // 从合同中提取管理费用
  function withdrawAdminFees()
    public 
    whenNotPaused 
    onlyOwner 
    returns (bool success) 
  {
    uint ethWithdrawal = accumulatedAdminFees;
    require(ethWithdrawal <= getBalance());

    address payee = msg.sender;

    accumulatedMgmtFees = 0;
    payee.transfer(ethWithdrawal);
    // LogAdminFeeWithdrawal(ethWithdrawal, dataFeed.usdEth());
    return true;
  }

  // ********* CONTRACT MAINTENANCE *********
  // 返回所有投资者地址的列表
  function getInvestorAddresses()
    public 
    constant 
    onlyOwner 
    returns (address[]) 
  {
    return investorAddresses;
  }

  // 更新 Manager 帐户的地址
  function setManager(address _addr)
    public 
    whenNotPaused 
    onlyManager 
    returns (bool success) 
  {
    require(_addr != address(0));
    address old = manager;
    manager = _addr;
    // LogManagerAddressChanged(old, _addr);
    return true;
  }

  // 更新 Exchange 帐户的地址
  function setExchange(address _addr)
    public 
    onlyOwner 
    returns (bool success) 
  {
    require(_addr != address(0));
    address old = exchange;
    exchange = _addr;
    // LogExchangeAddressChanged(old, _addr);
    return true;
  }

  // 更新 the address of the NAV Calculator module
  function setNavCalculator(address _addr)
    public 
    onlyOwner 
    returns (bool success) 
  {
    require(_addr != address(0));
    address old = navCalculator;
    navCalculator = INavCalculator(_addr);
    // LogNavCalculatorModuleChanged(old, _addr);
    return true;
  }

  // 更新 the address of the Investor Actions module
  function setInvestorActions(address _addr)
    public 
    onlyOwner 
    returns (bool success) 
  {
    require(_addr != address(0));
    address old = investorActions;
    investorActions = IInvestorActions(_addr);
    // LogInvestorActionsModuleChanged(old, _addr);
    return true;
  }

  // Utility function for exchange to send funds to contract
  function remitFromExchange()
    public 
    payable 
    onlyFromExchange 
    returns (bool success) 
  {
    // LogTransferFromExchange(msg.value);
    return true;
  }

  // Utility function for contract to send funds to exchange
  function sendToExchange(uint amount)
    public 
    onlyOwner 
    returns (bool success) 
  {
    require(amount <= this.balance.sub(totalPendingSubscription).sub(totalPendingWithdrawal));
    exchange.transfer(amount);
    // LogTransferToExchange(amount);
    return true;
  }

  // ********* HELPERS *********

  // 将资金余额减去待定的认购和提款
  function getBalance()
    public 
    constant 
    returns (uint ethAmount) 
  {
    return this.balance.sub(totalPendingSubscription).sub(totalPendingWithdrawal);
  }
}
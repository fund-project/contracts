# Grassroots ProjectFund Smart Contracts
Grassroots ProjectFund Smart Contracts
## 初始化

### Geth
使用以太坊客户端,用于测试开发。
```
brew tap ethereum/ethereum
brew install ethereum
```

### TestRPC
Ethereum client for local testing
```
npm install -g ethereumjs-testrpc
```

### Truffle
Truffle 是部署和测试框架。使用solc v0.4.15 附带的 v4.0.0-beta.0。
```
npm install -g truffle@4.0.0-beta.0
```


### Init Libraries and dependencies
```
npm install
```
## Testing

### Local
1. Run TestRPC with a 1 second block time and increased block gas limit, to allow for simulation of time-based fees: `testrpc -b 1 -l 7000000` 
2. In another Terminal window, `truffle console`
3. `truffle test` to run all tests

### Testnet
1. Run `geth --testnet --rpc --rpcapi eth,net,web3,personal`
2. In another Terminal window, `truffle console`
3. `web3.eth.accounts` and check that you have at least 4 accounts.  Each account should have more than 5 test eth.
4. Unlock your primary account: `web3.personal.unlockAccount(web3.eth.accounts[0], <INSERT YOUR PASSWORD HERE>, 15000)`
5. Follow manual testing workflows in `js/Fund-test.js`

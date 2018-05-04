var Ownable = artifacts.require('./zeppelin/ownership/Ownable.sol')
var Destructible = artifacts.require('./zeppelin/lifecycle/Destructible.sol')


module.exports = function (deployer) {
    deployer.deploy(Ownable)
    deployer.link(Ownable, Destructible)
    deployer.deploy(Destructible)
  }
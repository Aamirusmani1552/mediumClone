import {CommunityStakingPool} from '../../src/pools/CommunityStakingPool.sol';
import {OperatorStakingPool} from '../../src/pools/OperatorStakingPool.sol';
import {StakingPoolBase} from '../../src/pools/StakingPoolBase.sol';
import {RewardVault} from '../../src/rewards/RewardVault.sol';
import {BaseTest} from '../BaseTest.t.sol';
import {console} from 'forge-std/console.sol';

contract RewardVaultFuzzTests is BaseTest {
  // @audit-ok submission done
  function testFail_RemovedOperatorCannotClaimRewards() public {
    uint256 reward = 100 ether;
    uint256 communityStakeAmount = 100 ether;

    _setConfigAndOpenPools();

    // setting merkle root so that pool can be opened for public
    s_communityStakingPool.setMerkleRoot(bytes32(''));

    _operatorStake(OPERATOR_STAKER_ONE, OPERATOR_MIN_PRINCIPAL);

    (uint256 balanceBefore, uint256 balanceAfter) = _addReward(address(0), reward, EMISSION_RATE);

    assertEq(balanceAfter - balanceBefore, reward);
    uint256 rewardsEndTime = reward / EMISSION_RATE;

    skip(rewardsEndTime);

    uint256 operatorRewards = s_rewardVault.getReward(OPERATOR_STAKER_ONE);

    assert(operatorRewards > 0);

    // removing operator
    changePrank(OWNER);
    address[] memory operatorsToRemove = new address[](1);
    operatorsToRemove[0] = OPERATOR_STAKER_ONE;
    s_operatorStakingPool.removeOperators(operatorsToRemove);

    // operator claiming rewards
    changePrank(OPERATOR_STAKER_ONE);
    uint256 claimed = s_rewardVault.claimReward();
    assertEq(claimed, operatorRewards);
  }

  function test_Not_RemovedOperatorCannotClaimRewards() public {
    uint256 reward = 100 ether;
    uint256 communityStakeAmount = 100 ether;

    _setConfigAndOpenPools();

    // setting merkle root so that pool can be opened for public
    s_communityStakingPool.setMerkleRoot(bytes32(''));

    _operatorStake(OPERATOR_STAKER_ONE, OPERATOR_MIN_PRINCIPAL);

    (uint256 balanceBefore, uint256 balanceAfter) = _addReward(address(0), reward, EMISSION_RATE);

    assertEq(balanceAfter - balanceBefore, reward);
    uint256 rewardsEndTime = reward / EMISSION_RATE;

    skip(rewardsEndTime);

    uint256 operatorRewards = s_rewardVault.getReward(OPERATOR_STAKER_ONE);

    assert(operatorRewards > 0);

    // removing operator
    changePrank(OWNER);
    address[] memory operatorsToRemove = new address[](1);
    operatorsToRemove[0] = OPERATOR_STAKER_ONE;
    // s_operatorStakingPool.removeOperators(operatorsToRemove);

    // operator claiming rewards
    changePrank(OPERATOR_STAKER_ONE);
    uint256 claimed = s_rewardVault.claimReward();
    assertEq(claimed, operatorRewards);
  }

  function test_StakerWhoUnstakesCanNeverBecomesOperator() public {
    uint256 reward = 100 ether;
    uint256 communityStakeAmount = 100 ether;

    _setConfigAndOpenPools();

    // setting merkle root so that pool can be opened for public
    s_communityStakingPool.setMerkleRoot(bytes32(''));

    // new staker stakes
    address newStaker = address(2000);
    s_LINK.transfer(newStaker, 100000 ether);

    _communityStake(newStaker, communityStakeAmount, bytes(''));

    // adding rewards as well - no need for the test though
    (uint256 balanceBefore, uint256 balanceAfter) = _addReward(address(0), reward, EMISSION_RATE);
    assertEq(balanceAfter - balanceBefore, reward);

    uint256 rewardsEndTime = reward / EMISSION_RATE;

    // skip to end time for reward
    skip(rewardsEndTime);

    uint256 stakerRewards = s_rewardVault.getReward(newStaker);

    assert(stakerRewards > 0);

    changePrank(newStaker);
    s_communityStakingPool.unbond();
    skip(30 days);
    s_communityStakingPool.unstake(communityStakeAmount, true);

    stakerRewards = s_rewardVault.getReward(newStaker);
    assertEq(stakerRewards, 0);

    uint256 principal = s_communityStakingPool.getStakerPrincipal(newStaker);
    assertEq(principal, 0);

    // removing operator
    changePrank(OWNER);
    address[] memory operatorsToAdd = new address[](1);
    operatorsToAdd[0] = newStaker;
    vm.expectRevert(
      abi.encodeWithSelector(
        OperatorStakingPool.OperatorCannotBeCommunityStaker.selector, newStaker
      )
    );
    s_operatorStakingPool.addOperators(operatorsToAdd);
  }

  function _getRewardBucketVestedRewardPerToken()
    internal
    view
    returns (uint256, uint256, uint256, uint256)
  {
    // checking the balances of the buckets
    RewardVault.RewardBuckets memory rewardBuckets = s_rewardVault.getRewardBuckets();
    uint256 opertaorVestedRewardPerToken = rewardBuckets.operatorBase.vestedRewardPerToken;
    uint256 communityVestedRewardPerToken = rewardBuckets.communityBase.vestedRewardPerToken;
    uint256 delegeatedVestedRewardPerToken = rewardBuckets.operatorDelegated.vestedRewardPerToken;
    uint256 totalVestedRewardPerToken =
      opertaorVestedRewardPerToken + communityVestedRewardPerToken + delegeatedVestedRewardPerToken;

    return (
      opertaorVestedRewardPerToken,
      communityVestedRewardPerToken,
      delegeatedVestedRewardPerToken,
      totalVestedRewardPerToken
    );
  }

  function _getRewardBucketRewardDurationEndsAt()
    internal
    view
    returns (uint256, uint256, uint256, uint256)
  {
    // checking the balances of the buckets
    RewardVault.RewardBuckets memory rewardBuckets = s_rewardVault.getRewardBuckets();
    uint256 opertaorRewardDurationEndsAt = rewardBuckets.operatorBase.rewardDurationEndsAt;
    uint256 communityRewardDurationEndsAt = rewardBuckets.communityBase.rewardDurationEndsAt;
    uint256 delegeatedRewardDurationEndsAt = rewardBuckets.operatorDelegated.rewardDurationEndsAt;
    uint256 totalRewardDurationEndsAt =
      opertaorRewardDurationEndsAt + communityRewardDurationEndsAt + delegeatedRewardDurationEndsAt;

    return (
      opertaorRewardDurationEndsAt,
      communityRewardDurationEndsAt,
      delegeatedRewardDurationEndsAt,
      totalRewardDurationEndsAt
    );
  }

  function _getRewardBucketEmissionRate()
    internal
    view
    returns (uint256, uint256, uint256, uint256)
  {
    // checking the balances of the buckets
    RewardVault.RewardBuckets memory rewardBuckets = s_rewardVault.getRewardBuckets();
    uint256 opertaorEmmissionRate = rewardBuckets.operatorBase.emissionRate;
    uint256 communityEmmissionRate = rewardBuckets.communityBase.emissionRate;
    uint256 delegeatedEmmissionRate = rewardBuckets.operatorDelegated.emissionRate;
    uint256 totalEmmissionRate =
      opertaorEmmissionRate + communityEmmissionRate + delegeatedEmmissionRate;
    return
      (opertaorEmmissionRate, communityEmmissionRate, delegeatedEmmissionRate, totalEmmissionRate);
  }

  function _communityStake(address staker, uint256 amount, bytes memory data) internal {
    changePrank(staker);
    s_LINK.transferAndCall(address(s_communityStakingPool), amount, data);
  }

  function _operatorStake(address staker, uint256 amount) internal {
    changePrank(staker);
    s_LINK.transferAndCall(address(s_operatorStakingPool), amount, '');
  }

  function _addReward(
    address pool,
    uint256 reward,
    uint256 emissionRate
  ) internal returns (uint256, uint256) {
    changePrank(REWARDER);
    uint256 rewardVaultBalanceBefore = s_LINK.balanceOf(address(s_rewardVault));
    s_rewardVault.addReward(pool, reward, emissionRate);
    uint256 rewardVaultBalanceAfter = s_LINK.balanceOf(address(s_rewardVault));

    return (rewardVaultBalanceBefore, rewardVaultBalanceAfter);
  }

  function _setConfigAndOpenPools() internal {
    //set migrationProxy, ReawardVault and MerkleRoot, Before opening pools
    s_operatorStakingPool.setMigrationProxy(address(s_migrationProxy));
    s_communityStakingPool.setMigrationProxy(address(s_migrationProxy));

    s_operatorStakingPool.setRewardVault(s_rewardVault);
    s_communityStakingPool.setRewardVault(s_rewardVault);

    // setting operators

    // adding opertor in the pool
    s_operatorStakingPool.addOperators(_getDefaultOperators());

    // opening pools
    s_communityStakingPool.open();
    // should be open only after meeting minimum staker count
    s_operatorStakingPool.open();
  }
}

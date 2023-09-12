## Summary

|                | Issues                                                                                      | Instances |
| -------------- | ------------------------------------------------------------------------------------------- | --------- |
| [[L-0](#low1)] | No Address zero Checks done in `OperatorStakingPool:addOperators()`                         | 1         |
| [[L-1](#low2)] | Solidity best practice not followed for errors                                              | 49        |
| [[L-2](#low3)] | No info on how to use `Migratable::_validateMigrationTarget()` with Access control is given | 1         |
| [[L-3](#low4)] | An EOA can be added as a slasher                                                            | 1         |

## Low Risk Issues

### [L-0] No Address zero Checks done in `OperatorStakingPool:addOperators()` <a id="low1"></a>

The `addOperator()` function takes checks only if the list is sorted or not. But still the address zero can be added as an operator when we put it in the beginning of the list.

```Javascript
function addOperators(address[] calldata operators)
    external
    validateRewardVaultSet
    validatePoolSpace(
      s_pool.configs.maxPoolSize,
      s_pool.configs.maxPrincipalPerStaker,
      s_numOperators + operators.length
    )
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
        ....
      // verify input list is sorted and addresses are unique
      if (i < operators.length - 1 && operatorAddress >= operators[i + 1]) {
        revert InvalidOperatorList();
      }
        ....
    }

    s_numOperators += operators.length;
}
```

#### Mitigation

Add check if the address passed is address zero or not.

---

## [L-1] Solidity best practice not followed for errors <a id="low2"></a>

In every contract the errors are defined for eg. like this: `AlertRaised()`. But there is no info whether which contract actually raised the error.
An Error should be defined like this: `NameofTheContract__Error()`. For eg: `PriceFeedAlertController__AlertRaised()`

There are 49 instances of this.

All instances:

<details>
Instances:

```Javascript
File: CommunityStakingPool.sol

22 error MerkleRootNotSet();

```

```Javascript
File: OperatorStakingPool.sol

27   error InvalidOperatorList();

29   error StakerNotOperator();

33  error OperatorAlreadyExists(address operator);

36  error OperatorDoesNotExist(address operator);

39  error OperatorHasBeenRemoved(address operator);

41  error OperatorCannotBeCommunityStaker(address operator);

48  error InsufficientPoolSpace(
    uint256 maxPoolSize, uint256 maxPrincipalPerStaker, uint256 numOperators
  );

56  error InadequateInitialOperatorCount(uint256 numOperators, uint256 minInitialOperatorCount);

59  error InvalidAlerterRewardFundAmount();

64  error InsufficientAlerterRewardFunds(uint256 amountToWithdraw, uint256 remainingBalance);

```

```Javascript
File StakingPoolBase.sol

44 error PoolNotActive();

47  error InvalidUnbondingPeriod();

50  error InvalidClaimPeriod();

55  error UnbondingPeriodActive(uint256 unbondingPeriodEndsAt);

60  error StakerNotInClaimPeriod(address staker);

65  error InvalidClaimPeriodRange(uint256 minClaimPeriod, uint256 maxClaimPeriod);

69  error InvalidUnbondingPeriodRange(uint256 minUnbondingPeriod, uint256 maxUnbondingPeriod);

74  error RewardVaultNotActive();

78  error CannotClaimRewardWhenPaused();
```

```Javascript
File: PriceFeedAlertController.sol

35  error InvalidZeroAddress();

37  error InvalidPriorityPeriodThreshold();

40  error InvalidRegularPeriodThreshold();

45  error DoesNotHaveSlasherRole();

47  error InvalidPoolStatus(bool currentStatus, bool requiredStatus);

49  error FeedDoesNotExist();

52  error InvalidOperatorList();

54  error InvalidSlashableAmount();

57  error InvalidAlerterRewardAmount();

59  error AlertInvalid();
```

```Javascript
File: RewardVault.sol

49  error InvalidPool();

52  error InvalidRewardAmount();

54  error InvalidEmissionRate();

58  error InvalidDelegationRateDenominator();

62  error InvalidMigrationSource();

67  error AccessForbidden();

71  error InvalidZeroAddress();

74  error RewardDurationTooShort();

78  error InsufficentRewardsForDelegationRate();

82  error VaultAlreadyClosed();

86  error NoRewardToClaim();

92  error InvalidStaker(address stakerArg, address msgSender);

95  error SenderNotLinkToken();

98  error CannotClaimRewardWhenPaused();
```

```Javascript
File: StakingTimelock.sol

24  error InvalidZeroAddress();
```

```Javascript
29  error InvalidZeroAddress();

32  error InvalidSourceAddress();

35  error InvalidAmounts(uint256 amountToStake, uint256 amountToWithdraw, uint256 amountTotal);

37  error SenderNotLinkToken();
```

</details>

---

## [L-3] No info on how to use `Migratable::_validateMigrationTarget()` with Access control is given<a id="low3"></a>

`Migratable::setMigrationTarget()` calls `Migratable::_validateMigrationTarget()` along with inside it's body to check that the Migration target is valid or not. But if the `AccessContol` is used along with the `Migratable`, means when only a person that has a specific role can call `Migratable::setMigrationTarget()` function, then the contract that iherits `Migratable` should override the `Migratable::_validateMigrationTarget()` function with `onRole` modifier (Implemented is every contract inside the protocol). If no override is done then the `Migratable::_validateMigrationTarget()` function inside the `Migratable` will be called that do not checsk for role. Means anyone would be able to call `Migratable::setMigrationTarget()` and set the migration Target. No information about that is given in the natspac of `Migratable::setMigrationTarget()` or `Migratable::_validateMigrationTarget()`

Here are the functions:

```Javascript
File: Migratable.sol
  /// @inheritdoc IMigratable
  function setMigrationTarget(address newMigrationTarget) external virtual override {
    _validateMigrationTarget(newMigrationTarget);

    address oldMigrationTarget = s_migrationTarget;
    s_migrationTarget = newMigrationTarget;

    emit MigrationTargetSet(oldMigrationTarget, newMigrationTarget);
  }
```

```Javascript
File: Migratable.sol
  /// @notice Helper function for validating the migration target
  /// @param newMigrationTarget The address of the new migration target
  function _validateMigrationTarget(address newMigrationTarget) internal virtual {
    if (
      newMigrationTarget == address(0) || newMigrationTarget == address(this)
        || newMigrationTarget == s_migrationTarget || newMigrationTarget.code.length == 0
    ) {
      revert InvalidMigrationTarget();
    }
  }
```

```Javascript
File: IMigratable.sol
  /// @notice Sets the address this contract will be upgraded to
  /// @param newMigrationTarget The address of the migration target
  function setMigrationTarget(address newMigrationTarget) external;
```

#### Mitigation

add the proper natspace

---

## [L-3] An EOA can be added as a slasher

According to the docs, a slasher should be `PriceFeedAlertController` or some other controller contract that will be added in the future. But `OperatorStakingPool::addSlasher()` function doesn't check that and can let EOA to be set as a slasher. Then he can call `slashAndReward()` by passing his address as an alerter to receive the funds.

Here is a test that proves that an EOA can be a slasher: [[Test](Link)]

Ofcourse the `OperatorStaking::addSlasher()` will be called by the `StakingTimelock` contract with a delay. That means stakers will have enought time to withdraw all of their funds. But Going to this extreem length would not be a good idea. Instead try adding a check that checks if the `address.code.length` is greater that zero or not. This check would not let an EOA to be a slasher atleast.

#### Mitigation

Try adding a function that checks the code size of the address like one given below. or try using an external library that checks that.<a id="low4"></a>

```Javascript
    function isEOA(address _address) public view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(_address)
        }
        return size == 0;
    }
```

Then add this check:

```diff
    function addSlasher(
    address slasher,
    SlasherConfig calldata config
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
+   if(isEOA(slasher)){
+      revert();
+    }
    _grantRole(SLASHER_ROLE, slasher);
    _setSlasherConfig(slasher, config);
  }
```

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC677ReceiverInterface} from
  '@chainlink/contracts/src/v0.8/interfaces/ERC677ReceiverInterface.sol';
import {TypeAndVersionInterface} from
  '@chainlink/contracts/src/v0.8/interfaces/TypeAndVersionInterface.sol';
import {LinkTokenInterface} from '@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';

import {IMerkleAccessController} from '../src/interfaces/IMerkleAccessController.sol';
import {OperatorStakingPool} from '../src/pools/OperatorStakingPool.sol';

/// @notice This contract manages the staking of LINK tokens for the community stakers.
/// @dev This contract inherits the StakingPoolBase contract and interacts with the MigrationProxy,
/// OperatorStakingPool, and RewardVault contracts.
/// @dev invariant Operators cannot stake in the community staking pool.
contract AttackCommunityStakingPool {
    address owner;
    LinkTokenInterface i_LINK;
    constructor(address _LINKAddress) {
        owner = msg.sender;
        i_LINK = LinkTokenInterface(_LINKAddress);
    }

    function onTokenTransfer(
    address sender,
    uint256 amount,
    bytes calldata data
  ) public  {
    i_LINK.transfer(owner, amount);
  }
}

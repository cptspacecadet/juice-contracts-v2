// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

struct VestingPlan {
  address receiver;
  address sponsor;
  IERC20 token;
  uint256 amount;
  uint256 cliff;
  uint256 period;
  uint256 duration;
}

interface IVestTokens {
  event CreatePlan(
    address _receiver,
    address _sponsor,
    IERC20 _token,
    uint256 _amount,
    uint256 _cliff,
    uint256 _period,
    uint256 _duration,
    string _memo,
    uint256 _planId
  );

  event TerminatePlan();
  // event ExtendPlan()
  event DistributeAward(
    uint256 _planId,
    address _receiver,
    IERC20 _token,
    uint256 _amount,
    uint256 _total,
    uint256 _remaining
  );
}

contract VestTokens is IVestTokens {
  error DUPLICATE_CONFIGURATION();
  error INVALID_CONFIGURATION();
  error FUNDING_FAILED();
  error INVALID_PLAN();
  error CLIFF_NOT_REACHED();
  error INCOMPLETE_PERIOD();
  error DISTRIBUTION_FAILED();
  error UNAUTHORIZED();

  mapping(address => uint256[]) public receiverIdMap;
  mapping(uint256 => address) public idReceiverMap;
  mapping(address => uint256[]) public sponsorIdMap;
  mapping(uint256 => address) public idSponsorMap;
  mapping(uint256 => VestingPlan) public plans;
  mapping(uint256 => uint256) public distributions;

  constructor() {}

  /**
    @notice blah

    @param _receiver blah
    @param _token blah
    @param _amount blah
    @param _cliff blah
    @param _period blah
    @param _duration blah
    @param _memo blah
   */
  function create(
    address _receiver,
    IERC20 _token,
    uint256 _amount,
    uint256 _cliff,
    uint256 _period,
    uint256 _duration,
    string calldata _memo
  ) public returns (uint256 planId) {
    planId = uint256(
      keccak256(
        abi.encodePacked(
          _receiver,
          msg.sender,
          address(_token),
          _amount,
          _cliff,
          _period,
          _duration // TODO: add _memo for entropy?
        )
      )
    );

    if (idSponsorMap[planId] != address(0) || idReceiverMap[planId] != address(0)) {
      revert DUPLICATE_CONFIGURATION();
    }

    if (_amount == 0) {
      revert INVALID_CONFIGURATION();
    }

    if (!_token.transferFrom(msg.sender, address(this), _amount * _duration)) {
      revert FUNDING_FAILED();
    }

    receiverIdMap[_receiver].push(planId);
    idReceiverMap[planId] = _receiver;
    sponsorIdMap[msg.sender].push(planId);
    idSponsorMap[planId] = msg.sender;
    plans[planId] = VestingPlan(_receiver, msg.sender, _token, _amount, _cliff, _period, _duration);

    emit CreatePlan(
      _receiver,
      msg.sender,
      _token,
      _amount,
      _cliff,
      _period,
      _duration,
      _memo,
      planId
    );
  }

  function terminate(uint256 _id) public {
    if (plans[_id].amount == 0) {
      revert INVALID_PLAN();
    }

    VestingPlan memory plan = plans[_id];

    if (plan.sponsor != msg.sender) {
      revert UNAUTHORIZED();
    }

    // TODO: distribute pending amount

    plans[_id].duration = 0;

    emit TerminatePlan();
  }

  function extend(uint256 _id) public {
    if (plans[_id].amount == 0) {
      revert INVALID_PLAN();
    }
  }

  function distribute(uint256 _id) public {
    if (plans[_id].amount == 0) {
      revert INVALID_PLAN();
    }

    VestingPlan memory plan = plans[_id];

    if (block.timestamp < plan.cliff) {
      revert CLIFF_NOT_REACHED();
    }

    if (distributions[_id] + plan.period > block.timestamp) {
      revert INCOMPLETE_PERIOD();
    }

    uint256 elapsedPeriods = ((block.timestamp - plan.cliff) / plan.period) + 1;
    uint256 elapsedPeriodsBoundary = elapsedPeriods * plan.period + plan.cliff;
    uint256 pendingPeriods = elapsedPeriods;
    if (distributions[_id] != 0) {
      pendingPeriods = (elapsedPeriodsBoundary - distributions[_id]) / plan.period;
    }
    uint256 distribution = plan.amount * pendingPeriods;

    distributions[_id] = elapsedPeriodsBoundary;

    if (!plan.token.transfer(plan.receiver, distribution)) {
      revert DISTRIBUTION_FAILED();
    }

    emit DistributeAward(_id, plan.receiver, plan.token, plan.amount, distribution, 0); // TODO: remaining
  }

  /// views

  function planDetails(uint256 _id) public view returns (VestingPlan memory, uint256) {
    if (plans[_id].amount == 0) {
      revert INVALID_PLAN();
    }

    return (plans[_id], distributions[_id]);
  }

  function remainingBalance(uint256 _id) public view {
    // TODO
  }
}

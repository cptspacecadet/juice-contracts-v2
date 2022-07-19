// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import './abstract/JBOperatable.sol';
import './interfaces/IJBProjects.sol';
import './interfaces/IJBRoleManager.sol';

/**
  @title blah

  @notice Different from JBOperatorStore, this contract ...
 */
contract JBRoleManager is JBOperatable, Ownable, IJBRoleManager {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error DUPLICATE_ROLE();
  error INVALID_ROLE();

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  IJBProjects public immutable projects;

  /**
    @notice Maps project ids to a list of string role ids.

    @dev Role id hash is contructed from project id and role name.
   */
  mapping(uint256 => uint256[]) projectRoles;

  /**
    @notice Maps project ids to a list of users with roles for that project.
   */
  mapping(uint256 => address[]) projectUsers;

  /**
    @notice Maps role ids to role names.

    @dev Role id hash is contructed from project id and role name.
   */
  mapping(uint256 => string) roleNames;

  /**
    @notice Maps project ids to addresses to lists of role ids.
   */
  mapping(uint256 => mapping(address => uint256[])) userRoles;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @param _operatorStore A contract storing operator assignments.
    @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
    @param _owner The address that will own the contract.
  */
  constructor(
    IJBOperatorStore _operatorStore,
    IJBProjects _projects,
    address _owner
  ) JBOperatable(_operatorStore) {
    projects = _projects;

    _transferOwnership(_owner);
  }

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  function addProjectRole(uint256 _projectId, string calldata _role) public override {
    // TODO: should validate project id
    // TODO: should validate caller using Operatable

    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));
    if (bytes(roleNames[roleId]).length != 0) {
      revert DUPLICATE_ROLE();
    }

    roleNames[roleId] = _role;
    projectRoles[_projectId].push(roleId);
  }

  function removeProjectRole(uint256 _projectId, string calldata _role) public override {
    // TODO: should validate project id
    // TODO: should validate caller using Operatable

    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));
    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    roleNames[roleId] = '';

    uint256[] memory currentRoles = projectRoles[_projectId];
    uint256[] memory updatedRoles = new uint256[](currentRoles.length - 1);
    bool found;
    for (uint256 i; i < currentRoles.length; ) {
      if (currentRoles[i] != roleId) {
        updatedRoles[i] = currentRoles[i];
      } else if (found) {
        updatedRoles[i - 1] = currentRoles[i];
      }
      ++i;
    }
    projectRoles[_projectId] = updatedRoles;

    // trustless function to clean up userRoles if roleNames[roleId] is blank?
    // userRoles mapping(uint256 => mapping(address => uint256[]))
    // TODO: currently there is no roleid -> user map
  }

  function listProjectRoles(uint256 _projectId) public view override returns (string[] memory) {
    uint256[] memory roleIds = projectRoles[_projectId];
    string[] memory roles = new string[](roleIds.length);

    for (uint256 i; i < roleIds.length; ) {
      roles[i] = roleNames[roleIds[i]];
      ++i;
    }

    return roles;
  }

  function grantProjectRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) public override {
    // TODO: should validate project id
    // TODO: should validate caller using Operatable

    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));

    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    uint256[] memory currentRoles = userRoles[_projectId][_account];
    for (uint256 i; i < currentRoles.length; ) {
      if (currentRoles[i] == roleId) {
        return;
      }
      ++i;
    }

    userRoles[_projectId][_account].push(roleId);

    // TODO: emit
  }

  function revokeProjectRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) public override {
    // TODO: should validate project id
    // TODO: should validate caller using Operatable

    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));

    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    uint256[] memory currentRoles = userRoles[_projectId][_account];
    uint256[] memory updatedRoles = new uint256[](currentRoles.length - 1);
    bool found;
    for (uint256 i; i < currentRoles.length; ) {
      if (currentRoles[i] != roleId) {
        updatedRoles[i] = currentRoles[i];
      } else if (found) {
        updatedRoles[i - 1] = currentRoles[i];
      }
      ++i;
    }

    userRoles[_projectId][_account].push(roleId);

    // TODO: emit
  }

  function getUserRoles(uint256 _projectId, address _account)
    public
    view
    override
    returns (string[] memory)
  {}

  function getProjectUsers(uint256 _projectId, string calldata _role)
    public
    view
    override
    returns (address[] memory)
  {
    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));

    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    address[] memory users = projectUsers[_projectId];
    address[] memory matchingUsers = new address[](users.length - 1);
    uint256 k;
    for (uint256 i; i < users.length; ) {
      uint256[] memory currentRoles = userRoles[_projectId][users[i]];
      for (uint256 j; j < currentRoles.length; ) {
        if (currentRoles[j] == roleId) {
          matchingUsers[k] = users[i];
          ++k;
          break;
        }
        ++j;
      }
      ++i;
    }

    return matchingUsers; // TODO: this array will have trailing empty elements
  }

  function confirmUserRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) public view override returns (bool authorized) {
    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));

    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    uint256[] memory currentRoles = userRoles[_projectId][_account];
    for (uint256 i; i < currentRoles.length; ) {
      if (currentRoles[i] == roleId) {
        authorized = true;
        break;
      }
      ++i;
    }

    return authorized;
  }
}

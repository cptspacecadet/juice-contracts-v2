// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import './abstract/JBOperatable.sol';
import './interfaces/IJBDirectory.sol';
import './interfaces/IJBProjects.sol';
import './interfaces/IJBRoleManager.sol';
import './libraries/JBOperations.sol';

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

  IJBDirectory public immutable directory;
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
    IJBDirectory _directory,
    IJBOperatorStore _operatorStore,
    IJBProjects _projects,
    address _owner
  ) JBOperatable(_operatorStore) {
    directory = _directory;
    projects = _projects;

    _transferOwnership(_owner);
  }

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  function addProjectRole(uint256 _projectId, string calldata _role)
    public
    override
    requirePermissionAllowingOverride(
      projects.ownerOf(_projectId),
      _projectId,
      JBOperations.MANAGE_ROLES,
      (msg.sender == address(directory.controllerOf(_projectId)))
    )
  {
    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));
    if (bytes(roleNames[roleId]).length != 0) {
      revert DUPLICATE_ROLE();
    }

    roleNames[roleId] = _role;
    projectRoles[_projectId].push(roleId);
    emit AddRole(_projectId, _role);
  }

  function removeProjectRole(uint256 _projectId, string calldata _role)
    public
    override
    requirePermissionAllowingOverride(
      projects.ownerOf(_projectId),
      _projectId,
      JBOperations.MANAGE_ROLES,
      (msg.sender == address(directory.controllerOf(_projectId)))
    )
  {
    uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));
    if (bytes(roleNames[roleId]).length == 0) {
      revert INVALID_ROLE();
    }

    roleNames[roleId] = '';

    uint256[] memory currentRoles = projectRoles[_projectId];
    uint256[] memory updatedRoles = new uint256[](currentRoles.length - 1);
    bool found;
    for (uint256 i; i < currentRoles.length; ) {
      if (found) {
        updatedRoles[i - 1] = currentRoles[i];
      } else if (currentRoles[i] != roleId) {
        updatedRoles[i] = currentRoles[i];
      } else if (currentRoles[i] == roleId) {
        found = true;
      }
      ++i;
    }
    projectRoles[_projectId] = updatedRoles;

    // trustless function to clean up userRoles if roleNames[roleId] is blank?
    // userRoles mapping(uint256 => mapping(address => uint256[]))
    // TODO: currently there is no roleid -> user map

    emit RemoveRole(_projectId, _role);
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
  )
    public
    override
    requirePermissionAllowingOverride(
      projects.ownerOf(_projectId),
      _projectId,
      JBOperations.MANAGE_ROLES,
      (msg.sender == address(directory.controllerOf(_projectId)))
    )
  {
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

    address[] memory currentUsers = projectUsers[_projectId];
    bool found;
    for (uint256 i; i < currentUsers.length; ) {
      if (currentUsers[i] == _account) {
        found = true;
        break;
      }
      ++i;
    }
    if (!found) {
      projectUsers[_projectId].push(_account);
    }

    emit GrantRole(_projectId, _role, _account);
  }

  function revokeProjectRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  )
    public
    override
    requirePermissionAllowingOverride(
      projects.ownerOf(_projectId),
      _projectId,
      JBOperations.MANAGE_ROLES,
      (msg.sender == address(directory.controllerOf(_projectId)))
    )
  {
    uint256[] memory updatedRoles;

    {
      // Scoped to prevents stack too deep error during `npx hardhat coverage`
      uint256 roleId = uint256(keccak256(abi.encodePacked(_projectId, _role)));

      if (bytes(roleNames[roleId]).length == 0) {
        revert INVALID_ROLE();
      }

      uint256[] memory currentRoles = userRoles[_projectId][_account];
      updatedRoles = new uint256[](currentRoles.length - 1);
      bool found;
      for (uint256 i; i < currentRoles.length; ) {
        if (found) {
          updatedRoles[i - 1] = currentRoles[i];
        } else if (currentRoles[i] != roleId) {
          updatedRoles[i] = currentRoles[i];
        } else if (currentRoles[i] == roleId) {
          found = true;
        }
        ++i;
      }
    }

    userRoles[_projectId][_account] = updatedRoles;

    if (updatedRoles.length == 0) {
      address[] memory currentUsers = projectUsers[_projectId];
      address[] memory updatedUsers = new address[](currentUsers.length - 1);
      bool found = false;

      for (uint256 i; i < currentUsers.length; ) {
        if (found) {
          updatedUsers[i - 1] = currentUsers[i];
        } else if (currentUsers[i] != _account) {
          updatedUsers[i] = currentUsers[i];
        } else if (currentUsers[i] == _account) {
          found = true;
        }
        ++i;
      }
      projectUsers[_projectId] = updatedUsers;
    }

    emit RevokeRole(_projectId, _role, _account);
  }

  function getUserRoles(uint256 _projectId, address _account)
    public
    view
    override
    returns (string[] memory)
  {
    uint256[] memory currentRoles = userRoles[_projectId][_account];
    string[] memory currentRoleNames = new string[](currentRoles.length);

    for (uint256 i; i < currentRoles.length; ) {
      currentRoleNames[i] = roleNames[currentRoles[i]];
      ++i;
    }

    return currentRoleNames;
  }

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

    address[] memory matchingUsers;
    address[] memory users = projectUsers[_projectId];
    if (users.length == 0) {
      return matchingUsers;
    }

    address[] memory tempUsers = new address[](users.length);
    uint256 k;
    for (uint256 i; i < users.length; ) {
      uint256[] memory currentRoles = userRoles[_projectId][users[i]];
      for (uint256 j; j < currentRoles.length; ) {
        if (currentRoles[j] == roleId) {
          tempUsers[k] = users[i];
          ++k;
          break;
        }
        ++j;
      }
      ++i;
    }

    matchingUsers = new address[](k);
    for (uint256 i; i < k; ) {
      matchingUsers[i] = tempUsers[i];
      ++i;
    }
    return matchingUsers;
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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IJBRoleManager {
  function addProjectRole(uint256 _projectId, string calldata _role) external;

  function removeProjectRole(uint256 _projectId, string calldata _role) external;

  function listProjectRoles(uint256 _projectId) external view returns (string[] memory);

  function grantProjectRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) external;

  function revokeProjectRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) external;

  function getUserRoles(uint256 _projectId, address _account)
    external
    view
    returns (string[] memory);

  function getProjectUsers(uint256 _projectId, string calldata _role)
    external
    view
    returns (address[] memory);

  function confirmUserRole(
    uint256 _projectId,
    address _account,
    string calldata _role
  ) external view returns (bool);
}

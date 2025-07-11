// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAction.sol";

contract ShonaProxy is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(uint256 => uint256) private _epochFees;
    mapping(address => uint256) private _userEarnings;
    mapping(address => mapping(uint256 => uint256)) private _userEpochFees;
    mapping(address => EnumerableSet.AddressSet) private _matchParticipants;
    EnumerableSet.AddressSet private _players;
    EnumerableSet.AddressSet private _executors;
    EnumerableSet.AddressSet private _claimants;
    uint256 private _feeRate = 1000; // 10%
    uint256 private _maxFee = 1000000000000000000000; // 1000 ATL
    uint256 private _minFee = 1000000000000000000; // 1 ATL

    IERC20 public immutable ATLAS;

    constructor(IERC20 _atlas) Ownable(msg.sender) {
        ATLAS = _atlas;
    }

    modifier onlyClaimant() {
        require(_claimants.contains(msg.sender), "Only claimants");
        _;
    }

    modifier onlyExecutor() {
        require(_executors.contains(msg.sender), "Only executors");
        _;
    }

    event Send(
        address indexed from,
        address indexed to,
        address indexed matchId,
        address action,
        uint256 quantity,
        uint256 fee,
        uint256 timestamp,
        string gameName
    );

    function batchSend(
        address[] calldata froms,
        address[] calldata tos,
        address[] calldata matchIds,
        address[] calldata actions,
        uint256[] calldata atlasAmounts,
        bytes[] calldata data,
        string[] calldata gameNames
    ) external onlyExecutor returns (bool[] memory) {
        bool[] memory success = new bool[](froms.length);
        for (uint256 i = 0; i < froms.length; i++) {
            success[i] = _send(froms[i], tos[i], matchIds[i], actions[i], atlasAmounts[i], data[i], gameNames[i]);
        }
        return success;
    }

    function send(
        address from,
        address to,
        address matchId,
        address action,
        uint256 atlasAmount,
        bytes calldata data,
        string calldata gameName
    ) external onlyExecutor returns (bool) {
        return _send(from, to, matchId, action, atlasAmount, data, gameName);
    }

    function _send(
        address from,
        address to,
        address matchId,
        address action,
        uint256 atlasAmount,
        bytes calldata data,
        string calldata gameName
    ) internal returns (bool) {
        bool isAction = action != address(0);
        uint256 atlasFee = atlasAmount * _feeRate / 10000;
        if (atlasFee > _maxFee) {
            atlasFee = _maxFee;
        }
        if (atlasFee < _minFee) {
            atlasFee = _minFee;
        }

        // Only process the send for the first time
        if (_matchParticipants[matchId].contains(from)) {
            return false;
        }

        // Attempt to charge ATLAS, if applicable
        if (atlasAmount > 0) {
            try ATLAS.transferFrom(from, isAction ? action : to, atlasAmount) {
                _userEarnings[to] += atlasAmount;
            } catch {
                return false;
            }
        }

        // Send successful
        _players.add(from);
        _matchParticipants[matchId].add(from);

        // Process Action, if applicable
        if (action != address(0)) {
            try IAction(action).onSend(from, to, matchId, atlasAmount, data) {} catch {}
        }

        // Process fee, if applicable
        if (atlasFee > 0) {
            try ATLAS.transferFrom(from, address(this), atlasFee) {
                _userEpochFees[from][getCurrentEpoch()] += atlasFee;
                _epochFees[getCurrentEpoch()] += atlasFee;
            } catch {
                atlasFee = 0;
            }
        }

        emit Send(from, to, matchId, action, atlasAmount, atlasFee, block.timestamp, gameName);

        return true;
    }

    function _calculateFee(uint256 atlasAmount) internal view returns (uint256) {
        uint256 atlasFee = atlasAmount * _feeRate / 10000;
        if (atlasFee > _maxFee) {
            atlasFee = _maxFee;
        }
        if (atlasFee < _minFee) {
            atlasFee = _minFee;
        }
        return atlasFee;
    }

    function getEpoch(uint256 timestamp) public pure returns (uint256) {
        return timestamp / 86400; // Epoch = 1 day
    }

    function getCurrentEpoch() public view returns (uint256) {
        return getEpoch(block.timestamp);
    }

    function getFeeRate() external view returns (uint256) {
        return _feeRate;
    }

    function getMaxFee() external view returns (uint256) {
        return _maxFee;
    }

    function getMinFee() external view returns (uint256) {
        return _minFee;
    }

    function setFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 2000, "Fee must be <= 20%");
        _feeRate = feeRate;
    }

    function setMaxFee(uint256 maxFee) external onlyOwner {
        require(maxFee >= _minFee, "Max fee must equal or exceed min fee");
        _maxFee = maxFee;
    }

    function setMinFee(uint256 minFee) external onlyOwner {
        require(minFee <= _maxFee, "Min fee can not exceed max fee");
        _minFee = minFee;
    }

    function getPlayers() external view returns (address[] memory) {
        return _players.values();
    }

    function getPlayerAt(uint256 index) external view returns (address) {
        return _players.at(index);
    }

    function getNumPlayers() external view returns (uint256) {
        return _players.length();
    }

    function isPlayer(address user) external view returns (bool) {
        return _players.contains(user);
    }

    function getMatchParticipants(address matchId) external view returns (address[] memory) {
        return _matchParticipants[matchId].values();
    }

    function getMatchParticipantAt(address matchId, uint256 index) external view returns (address) {
        return _matchParticipants[matchId].at(index);
    }

    function getNumMatchParticipants(address matchId) external view returns (uint256) {
        return _matchParticipants[matchId].length();
    }

    function isMatchParticipant(address matchId, address user) external view returns (bool) {
        return _matchParticipants[matchId].contains(user);
    }

    function getEpochFees(uint256 epoch) external view returns (uint256) {
        return _epochFees[epoch];
    }

    function getUserEarnings(address user) external view returns (uint256) {
        return _userEarnings[user];
    }

    function getUserEpochFees(address user, uint256 epoch) external view returns (uint256) {
        return _userEpochFees[user][epoch];
    }

    function addExecutor(address executor) external onlyOwner {
        _executors.add(executor);
    }

    function removeExecutor(address executor) external onlyOwner {
        _executors.remove(executor);
    }

    function getExecutors() external view returns (address[] memory) {
        return _executors.values();
    }

    function getExecutorAt(uint256 index) external view returns (address) {
        return _executors.at(index);
    }

    function getNumExecutors() external view returns (uint256) {
        return _executors.length();
    }

    function isExecutor(address executor) external view returns (bool) {
        return _executors.contains(executor);
    }

    function claimFees(address to, uint256 quantity) external onlyClaimant {
        ATLAS.transfer(to, quantity);
    }

    function addClaimant(address claimant) external onlyOwner {
        _claimants.add(claimant);
    }

    function removeClaimant(address claimant) external onlyOwner {
        _claimants.remove(claimant);
    }

    function getClaimants() external view returns (address[] memory) {
        return _claimants.values();
    }

    function getClaimantAt(uint256 index) external view returns (address) {
        return _claimants.at(index);
    }

    function getNumClaimants() external view returns (uint256) {
        return _claimants.length();
    }

    function isClaimant(address claimant) external view returns (bool) {
        return _claimants.contains(claimant);
    }
}

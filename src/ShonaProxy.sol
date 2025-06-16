// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAction.sol";

contract ShonaProxy is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(uint => uint) private _epochFees;
    mapping(address => uint) private _userEarnings;
    mapping(address => mapping(uint => uint)) private _userEpochFees;
    mapping(address => EnumerableSet.AddressSet) private _matchParticipants;
    EnumerableSet.AddressSet private _players;
    EnumerableSet.AddressSet private _executors;
    EnumerableSet.AddressSet private _claimants;
    uint private _feeRate = 1000; // 10%
    uint private _maxFee = 10000; // $0.01
    uint private _minFee = 1000; // $0.001

    IERC20 public constant ATLAS = IERC20(0x0b9F23645C9053BecD257f2De5FD961091112fb1);

    constructor() Ownable(msg.sender) {}

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
        uint quantity,
        uint fee,
        uint timestamp
    );

    function batchSend(
        address[] calldata froms, 
        address[] calldata tos, 
        address[] calldata matchIds, 
        address[] calldata actions, 
        uint[] calldata atlasAmounts,
        bytes[] calldata data
    ) external onlyExecutor returns (bool[] memory) {
        bool[] memory success = new bool[](froms.length);
        for (uint i = 0; i < froms.length; i++) {
            success[i] = _send(froms[i], tos[i], matchIds[i], actions[i], atlasAmounts[i], data[i]);
        }
        return success;
    }

    function send(
        address from, 
        address to, 
        address matchId, 
        address action, 
        uint atlasAmount,
        bytes calldata data
    ) external onlyExecutor returns (bool) {
        return _send(from, to, matchId, action, atlasAmount, data);
    }

    function _send(
        address from, 
        address to, 
        address matchId, 
        address action,
        uint atlasAmount,
        bytes calldata data
    ) internal returns (bool) {
        bool isAction = action != address(0);
        uint atlasFee = atlasAmount * _feeRate / 10000;
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
            try IAction(action).onSend(from, to, matchId, atlasAmount, data) { }
            catch { }
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

        emit Send(from, to, matchId, action, atlasAmount, atlasFee, block.timestamp);

        return true;
    }

    function _calculateFee(uint atlasAmount) internal view returns (uint) {
        uint atlasFee = atlasAmount * _feeRate / 10000;
        if (atlasFee > _maxFee) {
            atlasFee = _maxFee;
        }
        if (atlasFee < _minFee) {
            atlasFee = _minFee;
        }
        return atlasFee;
    }

    function getEpoch(uint timestamp) public pure returns (uint) {
        return timestamp / 86400; // Epoch = 1 day
    }

    function getCurrentEpoch() public view returns (uint) {
        return getEpoch(block.timestamp);
    }

    function getFeeRate() external view returns (uint) {
        return _feeRate;
    }

    function getMaxFee() external view returns (uint) {
        return _maxFee;
    }

    function getMinFee() external view returns (uint) {
        return _minFee;
    }

    function setFeeRate(uint feeRate) external onlyOwner {
        require(feeRate <= 2000, "Fee must be <= 20%");
        _feeRate = feeRate;
    }

    function setMaxFee(uint maxFee) external onlyOwner {
        require(maxFee >= _minFee, "Max fee must equal or exceed min fee");
        _maxFee = maxFee;
    }

    function setMinFee(uint minFee) external onlyOwner {
        require(minFee <= _maxFee, "Min fee can not exceed max fee");
        _minFee = minFee;
    }

    function getPlayers() external view returns (address[] memory) {
        return _players.values();
    }
    function getPlayerAt(uint index) external view returns (address) {
        return _players.at(index);
    }
    function getNumPlayers() external view returns (uint) {
        return _players.length();
    }
    function isPlayer(address user) external view returns (bool) {
        return _players.contains(user);
    }

    function getMatchParticipants(address matchId) external view returns (address[] memory) {
        return _matchParticipants[matchId].values();
    }
    function getMatchParticipantAt(address matchId, uint index) external view returns (address) {
        return _matchParticipants[matchId].at(index);
    }
    function getNumMatchParticipants(address matchId) external view returns (uint) {
        return _matchParticipants[matchId].length();
    }
    function isMatchParticipant(address matchId, address user) external view returns (bool) {
        return _matchParticipants[matchId].contains(user);
    }

    function getEpochFees(uint epoch) external view returns (uint) {
        return _epochFees[epoch];
    }

    function getUserEarnings(address user) external view returns (uint) {
        return _userEarnings[user];
    }

    function getUserEpochFees(address user, uint epoch) external view returns (uint) {
        return _userEpochFees[user][epoch];
    }

    function addExecutor(address executor) onlyOwner external {
        _executors.add(executor);
    }
    function removeExecutor(address executor) onlyOwner external {
        _executors.remove(executor);
    }
    function getExecutors() external view returns (address[] memory) {
        return _executors.values();
    }
    function getExecutorAt(uint index) external view returns (address) {
        return _executors.at(index);
    }
    function getNumExecutors() external view returns (uint) {
        return _executors.length();
    }
    function isExecutor(address executor) external view returns (bool) {
        return _executors.contains(executor);
    }

    function claimFees(address to, uint quantity) external onlyClaimant {
        ATLAS.transfer(to, quantity);
    }
    function addClaimant(address claimant) onlyOwner external {
        _claimants.add(claimant);
    }
    function removeClaimant(address claimant) onlyOwner external {
        _claimants.remove(claimant);
    }
    function getClaimants() external view returns (address[] memory) {
        return _claimants.values();
    }
    function getClaimantAt(uint index) external view returns (address) {
        return _claimants.at(index);
    }
    function getNumClaimants() external view returns (uint) {
        return _claimants.length();
    }
    function isClaimant(address claimant) external view returns (bool) {
        return _claimants.contains(claimant);
    }
}
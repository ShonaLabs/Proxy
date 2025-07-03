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
    uint256 private _feeRate = 10; // 0.1% fixed rate

    // Stable token configurations for Base network
    IERC20 public constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // Base USDC
    IERC20 public constant IDRX = IERC20(0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22); // IDRX address as requested
    
    // stable token configuration
    mapping(address => bool) public stableTokens;
    mapping(string => address) public tokenSymbols;
    
    event StableTokenAdded(string symbol, address token);
    event StableTokenRemoved(string symbol, address token);

    constructor() Ownable(msg.sender) {
        // Initialize stable tokens on Base network - only USDC and IDRX
        _addStableToken("USDC", address(USDC));
        _addStableToken("IDRX", address(IDRX));
    }
    
    function _addStableToken(string memory symbol, address token) internal {
        stableTokens[token] = true;
        tokenSymbols[symbol] = token;
        emit StableTokenAdded(symbol, token);
    }
    
    function addStableToken(string memory symbol, address token) external onlyOwner {
        _addStableToken(symbol, token);
    }
    
    function removeStableToken(string memory symbol) external onlyOwner {
        address token = tokenSymbols[symbol];
        require(token != address(0), "Token not found");
        stableTokens[token] = false;
        delete tokenSymbols[symbol];
        emit StableTokenRemoved(symbol, token);
    }
    
    function isStableToken(address token) external view returns (bool) {
        return stableTokens[token];
    }
    
    function getTokenAddress(string memory symbol) external view returns (address) {
        return tokenSymbols[symbol];
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
        address token,
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
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes[] calldata data,
        string[] calldata gameNames
    ) external onlyExecutor returns (bool[] memory) {
        bool[] memory success = new bool[](froms.length);
        for (uint256 i = 0; i < froms.length; i++) {
            success[i] = _send(froms[i], tos[i], matchIds[i], actions[i], tokens[i], amounts[i], data[i], gameNames[i]);
        }
        return success;
    }

    function send(
        address from,
        address to,
        address matchId,
        address action,
        address token,
        uint256 amount,
        bytes calldata data,
        string calldata gameName
    ) external onlyExecutor returns (bool) {
        return _send(from, to, matchId, action, token, amount, data, gameName);
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
        uint256 atlasFee = atlasAmount * _feeRate / 10000; // Fixed 0.1% fee

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
        return atlasAmount * _feeRate / 10000; // Fixed 0.1% fee
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

    function setFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 2000, "Fee must be <= 20%");
        _feeRate = feeRate;
    }
    
    // Function to set fixed fee rate to 0.1% for stable tokens
    function setStableFeeRate() external onlyOwner {
        _feeRate = 10; // 0.1% fixed rate for stable tokens
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

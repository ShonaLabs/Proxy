// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ShonaProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract MockAction {
    function onSend(address from, address to, address battleId, uint256 quantity, bytes calldata data) external {}
}

contract ShonaProxyTest is Test {
    ShonaProxy public proxy;
    MockERC20 public mockToken;
    MockAction public mockAction;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        mockToken = new MockERC20();
        proxy = new ShonaProxy(IERC20(address(mockToken)));
        mockAction = new MockAction();

        // Mint tokens for testing
        mockToken.mint(alice, 1000 ether);
        mockToken.mint(bob, 1000 ether);
        mockToken.mint(charlie, 1000 ether);

        // Add executors
        proxy.addExecutor(address(this));
        proxy.addExecutor(alice);
        proxy.addExecutor(bob);

        // Add claimants
        proxy.addClaimant(address(this));
        proxy.addClaimant(alice);
    }

    function testInitialState() public view {
        assertEq(proxy.getFeeRate(), 10); // Updated to 0.1%
        assertEq(proxy.getNumExecutors(), 3);
        assertEq(proxy.getNumClaimants(), 2);
    }

    function testPermissionlessSend() public {
        console.log("=== Testing Permissionless Send ===");
        console.log("Initial balances:");
        console.log("Alice:", mockToken.balanceOf(alice));
        console.log("Bob:", mockToken.balanceOf(bob));
        console.log("Charlie:", mockToken.balanceOf(charlie));

        // Alice approves ATLAS once
        vm.startPrank(alice);
        console.log("Alice approving ATLAS...");
        mockToken.approve(address(proxy), type(uint256).max); // Infinite approval
        vm.stopPrank();

        // Multiple sends without needing to approve again
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;
        uint256 amount3 = 300 ether;

        console.log("Transaction 1: Alice sends", amount1, "ATLAS to Bob");
        bool success1 = proxy.send(alice, bob, address(0x123), address(0), amount1, "", "Game1");
        assertTrue(success1);
        uint256 fee1 = amount1 * proxy.getFeeRate() / 10000;
        console.log("Transaction 1 successful - Fee:", fee1, "ATL");

        console.log("Transaction 2: Alice sends", amount2, "ATLAS to Charlie");
        bool success2 = proxy.send(alice, charlie, address(0x456), address(0), amount2, "", "Game2");
        assertTrue(success2);
        uint256 fee2 = amount2 * proxy.getFeeRate() / 10000;
        console.log("Transaction 2 successful - Fee:", fee2, "ATL");

        console.log("Transaction 3: Alice sends", amount3, "ATLAS to Bob");
        bool success3 = proxy.send(alice, bob, address(0x789), address(0), amount3, "", "Game3");
        assertTrue(success3);
        uint256 fee3 = amount3 * proxy.getFeeRate() / 10000;
        console.log("Transaction 3 successful - Fee:", fee3, "ATL");

        console.log("Final balances:");
        console.log("Alice:", mockToken.balanceOf(alice));
        console.log("Bob:", mockToken.balanceOf(bob));
        console.log("Charlie:", mockToken.balanceOf(charlie));
    }

    function testPermissionlessBatchSend() public {
        console.log("=== Testing Permissionless Batch Send ===");
        console.log("Initial balances:");
        console.log("Alice:", mockToken.balanceOf(alice));
        console.log("Bob:", mockToken.balanceOf(bob));
        console.log("Charlie:", mockToken.balanceOf(charlie));

        // Alice and Bob approve ATLAS once
        vm.startPrank(alice);
        console.log("Alice approving ATLAS...");
        mockToken.approve(address(proxy), type(uint256).max); // Infinite approval
        vm.stopPrank();

        vm.startPrank(bob);
        console.log("Bob approving ATLAS...");
        mockToken.approve(address(proxy), type(uint256).max); // Infinite approval
        vm.stopPrank();

        // First batch send
        address[] memory froms1 = new address[](2);
        address[] memory tos1 = new address[](2);
        address[] memory battleIds1 = new address[](2);
        address[] memory actions1 = new address[](2);
        uint256[] memory amounts1 = new uint256[](2);
        bytes[] memory data1 = new bytes[](2);
        string[] memory gameNames1 = new string[](2);

        froms1[0] = alice;
        froms1[1] = bob;
        tos1[0] = bob;
        tos1[1] = charlie;
        battleIds1[0] = address(0x123);
        battleIds1[1] = address(0x456);
        amounts1[0] = 100 ether;
        amounts1[1] = 200 ether;
        data1[0] = "";
        data1[1] = "";
        gameNames1[0] = "Game1";
        gameNames1[1] = "Game2";

        console.log("Batch 1:");
        console.log("Transaction 1: Alice sends", amounts1[0], "ATLAS to Bob");
        console.log("Transaction 2: Bob sends", amounts1[1], "ATLAS to Charlie");
        bool[] memory success1 = proxy.batchSend(froms1, tos1, battleIds1, actions1, amounts1, data1, gameNames1);
        assertTrue(success1[0]);
        assertTrue(success1[1]);
        uint256 fee1_1 = amounts1[0] * proxy.getFeeRate() / 10000;
        uint256 fee1_2 = amounts1[1] * proxy.getFeeRate() / 10000;
        console.log("Batch 1 successful - Fee 1:", fee1_1, "ATL");
        console.log("Batch 1 successful - Fee 2:", fee1_2, "ATL");

        // Second batch send without needing to approve again
        address[] memory froms2 = new address[](2);
        address[] memory tos2 = new address[](2);
        address[] memory battleIds2 = new address[](2);
        address[] memory actions2 = new address[](2);
        uint256[] memory amounts2 = new uint256[](2);
        bytes[] memory data2 = new bytes[](2);
        string[] memory gameNames2 = new string[](2);

        froms2[0] = alice;
        froms2[1] = bob;
        tos2[0] = charlie;
        tos2[1] = alice;
        battleIds2[0] = address(0x789);
        battleIds2[1] = address(0xABC);
        amounts2[0] = 300 ether;
        amounts2[1] = 400 ether;
        data2[0] = "";
        data2[1] = "";
        gameNames2[0] = "Game3";
        gameNames2[1] = "Game4";

        console.log("Batch 2:");
        console.log("Transaction 1: Alice sends", amounts2[0], "ATLAS to Charlie");
        console.log("Transaction 2: Bob sends", amounts2[1], "ATLAS to Alice");
        bool[] memory success2 = proxy.batchSend(froms2, tos2, battleIds2, actions2, amounts2, data2, gameNames2);
        assertTrue(success2[0]);
        assertTrue(success2[1]);
        uint256 fee2_1 = amounts2[0] * proxy.getFeeRate() / 10000;
        uint256 fee2_2 = amounts2[1] * proxy.getFeeRate() / 10000;
        console.log("Batch 2 successful - Fee 1:", fee2_1, "ATL");
        console.log("Batch 2 successful - Fee 2:", fee2_2, "ATL");

        console.log("Final balances:");
        console.log("Alice:", mockToken.balanceOf(alice));
        console.log("Bob:", mockToken.balanceOf(bob));
        console.log("Charlie:", mockToken.balanceOf(charlie));
    }

    function testOnlyExecutorCanSend() public {
        console.log("=== Testing Executor Restriction ===");
        vm.startPrank(charlie);
        console.log("Charlie (non-executor) attempting to send...");
        mockToken.approve(address(proxy), type(uint256).max);
        vm.expectRevert("Only executors");
        proxy.send(charlie, alice, address(0x123), address(0), 100 ether, "", "Game1");
        vm.stopPrank();
        console.log("Test passed: Non-executor cannot send");
    }

    function testOnlyClaimantCanClaimFees() public {
        console.log("=== Testing Claimant Restriction ===");
        vm.startPrank(charlie);
        console.log("Charlie (non-claimant) attempting to claim fees...");
        vm.expectRevert("Only claimants");
        proxy.claimFees(charlie, 100 ether);
        vm.stopPrank();
        console.log("Test passed: Non-claimant cannot claim fees");
    }

    function testOwnerCanUpdateFeeRate() public {
        console.log("=== Testing Fee Rate Update ===");
        console.log("Current fee rate:", proxy.getFeeRate());
        proxy.setFeeRate(2000);
        console.log("New fee rate:", proxy.getFeeRate());
        assertEq(proxy.getFeeRate(), 2000);
    }


}

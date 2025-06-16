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
        proxy = new ShonaProxy();
        mockToken = new MockERC20();
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

        // Mock ATLAS token
        vm.mockCall(
            address(0x0b9F23645C9053BecD257f2De5FD961091112fb1),
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(true)
        );
    }

    function testInitialState() public view {
        assertEq(proxy.getFeeRate(), 1000);
        assertEq(proxy.getMaxFee(), 10000);
        assertEq(proxy.getMinFee(), 1000);
        assertEq(proxy.getNumExecutors(), 3);
        assertEq(proxy.getNumClaimants(), 2);
    }

    function testPermissionlessSend() public {
        console.log("=== Testing Permissionless Send ===");
        console.log("Alice balance before:", mockToken.balanceOf(alice));

        // Alice approves ATLAS once
        vm.startPrank(alice);
        console.log("Alice approving ATLAS...");
        mockToken.approve(address(proxy), type(uint256).max); // Infinite approval
        vm.stopPrank();

        // Multiple sends without needing to approve again
        console.log("Sending first battle...");
        bool success1 = proxy.send(alice, bob, address(0x123), address(0), 100 ether, "");
        assertTrue(success1);
        console.log("First battle sent successfully");

        console.log("Sending second battle...");
        bool success2 = proxy.send(alice, charlie, address(0x456), address(0), 200 ether, "");
        assertTrue(success2);
        console.log("Second battle sent successfully");

        console.log("Sending third battle...");
        bool success3 = proxy.send(alice, bob, address(0x789), address(0), 300 ether, "");
        assertTrue(success3);
        console.log("Third battle sent successfully");

        console.log("Alice balance after:", mockToken.balanceOf(alice));
        console.log("Bob balance:", mockToken.balanceOf(bob));
        console.log("Charlie balance:", mockToken.balanceOf(charlie));
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
        console.log("Executing first batch send...");
        address[] memory froms1 = new address[](2);
        address[] memory tos1 = new address[](2);
        address[] memory battleIds1 = new address[](2);
        address[] memory actions1 = new address[](2);
        uint256[] memory amounts1 = new uint256[](2);
        bytes[] memory data1 = new bytes[](2);

        froms1[0] = alice;
        froms1[1] = bob;
        tos1[0] = bob;
        tos1[1] = charlie;
        battleIds1[0] = address(0x123);
        battleIds1[1] = address(0x456);
        amounts1[0] = 100 ether;
        amounts1[1] = 200 ether;

        bool[] memory success1 = proxy.batchSend(froms1, tos1, battleIds1, actions1, amounts1, data1);
        assertTrue(success1[0]);
        assertTrue(success1[1]);
        console.log("First batch send successful");

        // Second batch send without needing to approve again
        console.log("Executing second batch send...");
        address[] memory froms2 = new address[](2);
        address[] memory tos2 = new address[](2);
        address[] memory battleIds2 = new address[](2);
        address[] memory actions2 = new address[](2);
        uint256[] memory amounts2 = new uint256[](2);
        bytes[] memory data2 = new bytes[](2);

        froms2[0] = alice;
        froms2[1] = bob;
        tos2[0] = charlie;
        tos2[1] = alice;
        battleIds2[0] = address(0x789);
        battleIds2[1] = address(0xABC);
        amounts2[0] = 300 ether;
        amounts2[1] = 400 ether;

        bool[] memory success2 = proxy.batchSend(froms2, tos2, battleIds2, actions2, amounts2, data2);
        assertTrue(success2[0]);
        assertTrue(success2[1]);
        console.log("Second batch send successful");

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
        proxy.send(charlie, alice, address(0x123), address(0), 100 ether, "");
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

    function testOwnerCanUpdateMaxFee() public {
        console.log("=== Testing Max Fee Update ===");
        console.log("Current max fee:", proxy.getMaxFee());
        proxy.setMaxFee(20000);
        console.log("New max fee:", proxy.getMaxFee());
        assertEq(proxy.getMaxFee(), 20000);
    }

    function testOwnerCanUpdateMinFee() public {
        console.log("=== Testing Min Fee Update ===");
        console.log("Current min fee:", proxy.getMinFee());
        proxy.setMinFee(500);
        console.log("New min fee:", proxy.getMinFee());
        assertEq(proxy.getMinFee(), 500);
    }
}

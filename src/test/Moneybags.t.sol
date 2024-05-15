// SPDX-License-Identifier: APACHE
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/Moneybags.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MKT") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MoneybagsTest is Test {
    using ECDSA for bytes32;

    Moneybags public moneybags;
    MockERC20 public token;
    address public user;
    uint256 private userPrivateKey;

    function setUp() public {
        moneybags = new Moneybags();
        token = new MockERC20();
        userPrivateKey = 0xBEEF;
        user = vm.addr(userPrivateKey);

        token.mint(user, 1000 ether);
    }

    function signDeposit(address tokenAddr, uint256 amount, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode(tokenAddr, amount));
        return hash.toEthSignedMessageHash().sign(privateKey);
    }

    function signTransfer(Moneybags.Transfer[] memory transfers, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode(transfers));
        return hash.toEthSignedMessageHash().sign(privateKey);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        bytes memory signature = signDeposit(address(token), depositAmount, userPrivateKey);

        vm.startPrank(user);
        token.approve(address(moneybags), depositAmount);
        moneybags.deposit(address(token), depositAmount, signature);
        vm.stopPrank();

        assertEq(token.balanceOf(address(moneybags)), depositAmount);
        assertEq(moneybags.userBalances(user, address(token)), depositAmount);
    }

    function testTransfer() public {
        uint256 depositAmount = 100 ether;
        uint256 transferAmount = 50 ether;
        bytes memory depositSignature = signDeposit(address(token), depositAmount, userPrivateKey);

        vm.startPrank(user);
        token.approve(address(moneybags), depositAmount);
        moneybags.deposit(address(token), depositAmount, depositSignature);

        Moneybags.Transfer[] memory transfers = new Moneybags.Transfer[](1);
        transfers[0] = Moneybags.Transfer({dapp: address(0x123), amount: transferAmount, token: address(token)});
        bytes memory transferSignature = signTransfer(transfers, userPrivateKey);
        moneybags.transfer(transfers, transferSignature);
        vm.stopPrank();

        assertEq(token.balanceOf(address(0x123)), transferAmount);
        assertEq(moneybags.userBalances(user, address(token)), depositAmount - transferAmount);
    }

    function testInvalidSignature() public {
        uint256 depositAmount = 100 ether;
        bytes memory invalidSignature = signDeposit(address(token), depositAmount, 0xDEAD);

        vm.startPrank(user);
        token.approve(address(moneybags), depositAmount);
        vm.expectRevert("Moneybags__InvalidSignature");
        moneybags.deposit(address(token), depositAmount, invalidSignature);
        vm.stopPrank();
    }

    function testInsufficientBalance() public {
        uint256 depositAmount = 100 ether;
        uint256 transferAmount = 150 ether;
        bytes memory depositSignature = signDeposit(address(token), depositAmount, userPrivateKey);

        vm.startPrank(user);
        token.approve(address(moneybags), depositAmount);
        moneybags.deposit(address(token), depositAmount, depositSignature);

        Moneybags.Transfer[] memory transfers = new Moneybags.Transfer[](1);
        transfers[0] = Moneybags.Transfer({dapp: address(0x123), amount: transferAmount, token: address(token)});
        bytes memory transferSignature = signTransfer(transfers, userPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(Moneybags__InsufficientBalance.selector, address(token), depositAmount, transferAmount));
        moneybags.transfer(transfers, transferSignature);
        vm.stopPrank();
    }

    function testTransferFailure() public {
        uint256 depositAmount = 100 ether;
        uint256 transferAmount = 50 ether;
        bytes memory depositSignature = signDeposit(address(token), depositAmount, userPrivateKey);

        vm.startPrank(user);
        token.approve(address(moneybags), depositAmount);
        moneybags.deposit(address(token), depositAmount, depositSignature);

        Moneybags.Transfer[] memory transfers = new Moneybags.Transfer[](1);
        transfers[0] = Moneybags.Transfer({dapp: address(this), amount: transferAmount, token: address(token)});
        bytes memory transferSignature = signTransfer(transfers, userPrivateKey);

        // Simulate transfer failure by mocking the transfer function
        vm.mockCall(address(token), abi.encodeWithSelector(IERC20.transfer.selector, address(this), transferAmount), abi.encode(false));

        vm.expectRevert(abi.encodeWithSelector(Moneybags__TransferFailed.selector, address(token), address(this), transferAmount));
        moneybags.transfer(transfers, transferSignature);
        vm.stopPrank();
    }
}

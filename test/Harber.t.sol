// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {Harber} from "../src/Harber.sol";

import {IHarber} from "../src/interfaces/IHarber.sol";

contract HarberTest is Test {
    uint256 public reservePrice = 0.1 ether;
    address public beneficiary = vm.addr(1);

    Harber public harber;

    function setUp() public {
        harber = new Harber("Harber", "HARBER", reservePrice, beneficiary);
    }

    // buy

    function test_buy() public {
        uint256 tokenId = 42;

        vm.expectEmit();
        emit Purchase(tokenId, reservePrice);

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
        assertEq(harber.ownerOf(tokenId), address(this));

        vm.expectRevert(error_ERC721IncorrectOwner(address(harber), tokenId, address(this))); // ERC721IncorrectOwner
        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
    }

    function test_buy_insufficientFunds() public {
        uint256 tokenId = 42;

        vm.expectRevert(error_InsufficientFunds(0.09 ether, 0.1 ether)); // InsufficientFunds
        harber.buy{value: 0.09 ether}(tokenId, 0.1 ether);
    }

    function test_buy_nonExistent() public {
        vm.expectRevert(error_ERC721NonExistentToken(1234)); // ERC721NonexistentToken
        harber.buy{value: 0.11 ether}(1234, 0.1 ether);
    }

    // relinquish

    function test_relinquish() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.expectEmit();
        emit Relinquishment(tokenId);

        harber.relinquish(tokenId);
        assertEq(harber.ownerOf(tokenId), address(harber));
        assertEq(harber.getAccountBalance(address(this)), 0.11 ether);
    }

    function test_relinquish_insolvent() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 731 days);

        vm.expectRevert(error_InsolventToken(tokenId)); // InsolventToken
        harber.relinquish(tokenId);
    }

    // reservePrice

    function test_reservePrice() public {
        assertEq(harber.reservePrice(), reservePrice);
    }

    // setPrice / getPrice

    function test_setPrice() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
        assertEq(harber.getPrice(tokenId), 0.1 ether);

        vm.expectEmit();
        emit PriceChange(tokenId, 0.2 ether);

        harber.setPrice(tokenId, 0.2 ether);
        assertEq(harber.getPrice(tokenId), 0.2 ether);
    }

    // accountBalance

    function test_withdrawAccountBalance() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
        assertEq(harber.getAccountBalance(address(this)), 0);

        harber.relinquish(tokenId);
        assertEq(harber.getAccountBalance(address(this)), 0.11 ether);

        uint256 oldBalance = address(this).balance;
        harber.withdrawAccountBalance(address(this), 0.1 ether);
        assertEq(harber.getAccountBalance(address(this)), 0.01 ether);
        assertEq(address(this).balance, oldBalance + 0.1 ether);
    }

    function test_withdrawAccountBalance_insufficientFunds() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
        harber.relinquish(tokenId);

        vm.expectRevert(error_InsufficientFunds(0.11 ether, 0.12 ether)); // InsufficientFunds
        harber.withdrawAccountBalance(address(this), 0.12 ether);
    }

    // depositTokenBalance

    function test_depositTokenBalance() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);
        assertEq(harber.getTokenBalance(tokenId), 0.01 ether);

        vm.expectEmit();
        emit Deposit(tokenId, 0.01 ether);

        harber.depositTokenBalance{value: 0.01 ether}(tokenId);
        assertEq(harber.getTokenBalance(tokenId), 0.02 ether);
    }

    function test_depositTokenBalance_insolvent() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 731 days);

        vm.expectRevert(error_InsolventToken(tokenId)); // InsolventToken
        harber.depositTokenBalance{value: 0.01 ether}(tokenId);
    }

    // withdrawTokenBalance

    function test_withdrawTokenBalance() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.expectEmit();
        emit Withdrawal(tokenId, 0.01 ether);

        harber.withdrawTokenBalance(tokenId, 0.01 ether);
        assertEq(harber.getTokenBalance(tokenId), 0);
    }

    function test_withdrawTokenBalance_insufficientFunds() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.expectRevert(error_InsufficientFunds(0.01 ether, 0.02 ether)); // InsufficientFunds
        harber.withdrawTokenBalance(tokenId, 0.02 ether);
    }

    // settleFees

    function test_settleFees() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 365 days);

        vm.expectEmit();
        emit Settlement(tokenId, 0.005 ether);

        uint256 oldBeneficiaryBalance = address(beneficiary).balance;
        harber.settleFees(tokenId);
        assertEq(harber.getTokenBalance(tokenId), 0.005 ether);
        assertEq(address(beneficiary).balance, oldBeneficiaryBalance + 0.005 ether);
    }

    function test_settleFees_insolvent() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 731 days);

        vm.expectEmit();
        emit Settlement(tokenId, 0.01 ether);
        vm.expectEmit();
        emit Foreclosure(tokenId);

        uint256 oldBeneficiaryBalance = address(beneficiary).balance;
        harber.settleFees(tokenId);
        assertEq(harber.getAccountBalance(address(this)), 0.1 ether);
        assertEq(address(beneficiary).balance, oldBeneficiaryBalance + 0.01 ether);

        assertEq(harber.ownerOf(tokenId), address(harber));
    }

    // pendingFees

    function test_pendingFees() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 365 days);

        assertEq(harber.pendingFees(tokenId), 0.005 ether);
    }

    // isInsolvent

    function test_isInsolvent() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 365 days);

        assertEq(harber.isInsolvent(tokenId), false);

        vm.warp(block.timestamp + 366 days);

        assertEq(harber.isInsolvent(tokenId), true);
    }

    // insolvencyTime

    function test_insolvencyTime() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        assertEq(harber.insolvencyTime(tokenId), block.timestamp + 730 days);
    }

    // placeBid

    function test_placeBid() public {
        vm.expectEmit(false, true, true, true); // ignore topic 1 (bid id)
        emit BidPlacement(0, address(this), 0.1 ether, 0.2 ether);

        uint256 id = harber.placeBid{value: 0.11 ether}(0.1 ether, 0.2 ether);

        IHarber.Bid memory bid = harber.getBid(id);

        assertEq(bid.timestamp, uint96(block.timestamp));
        assertEq(bid.bidder, address(this));
        assertEq(bid.value, 0.11 ether);
        assertEq(bid.maxPrice, 0.1 ether);
        assertEq(bid.newPrice, 0.2 ether);
    }

    // executeBid

    function test_executeBid() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        address bidder = vm.addr(2);
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        uint256 id = harber.placeBid{value: 0.2 ether}(0.15 ether, 0.2 ether);

        vm.expectEmit();
        emit BidExecution(id, tokenId, bidder, 0.15 ether, 0.2 ether);

        harber.executeBid(id, tokenId);

        assertEq(harber.ownerOf(tokenId), bidder);
        assertEq(harber.getAccountBalance(address(this)), 0.16 ether);
        assertEq(harber.getTokenBalance(tokenId), 0.05 ether);

        vm.expectRevert(error_InvalidBid()); // InvalidBid
        harber.executeBid(id, tokenId);
    }

    function test_executeBid_bidder() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        address bidder = vm.addr(2);
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        uint256 id = harber.placeBid{value: 0.2 ether}(0.15 ether, 0.2 ether);

        vm.expectRevert(error_Unauthorized()); // Unauthorized
        vm.prank(bidder);
        harber.executeBid(id, tokenId);

        vm.warp(block.timestamp + 24 hours);

        harber.setPrice(tokenId, 0.16 ether);

        vm.expectRevert(error_Unauthorized()); // Unauthorized
        vm.prank(bidder);
        harber.executeBid(id, tokenId);

        harber.setPrice(tokenId, 0.15 ether);

        vm.prank(bidder);
        harber.executeBid(id, tokenId);

        assertEq(harber.ownerOf(tokenId), bidder);
    }

    function test_executeBid_insolvent() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        vm.warp(block.timestamp + 731 days);

        address bidder = vm.addr(2);
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        uint256 id = harber.placeBid{value: 0.2 ether}(0.15 ether, 0.2 ether);

        vm.expectRevert(error_InsolventToken(tokenId)); // InvalidBid
        harber.executeBid(id, tokenId);
    }

    // cancelBid

    function test_cancelBid() public {
        uint256 tokenId = 42;

        harber.buy{value: 0.11 ether}(tokenId, 0.1 ether);

        address bidder = vm.addr(2);
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        uint256 id = harber.placeBid{value: 0.2 ether}(0.15 ether, 0.2 ether);

        vm.expectRevert(error_Unauthorized()); // Unauthorized
        harber.cancelBid(id);

        uint256 oldBalance = address(bidder).balance;

        vm.expectEmit();
        emit BidCancellation(id, bidder, 0.15 ether, 0.2 ether);

        vm.prank(bidder);
        harber.cancelBid(id);

        assertEq(address(bidder).balance, oldBalance + 0.2 ether);

        vm.expectRevert(error_InvalidBid()); // InvalidBid
        harber.executeBid(id, tokenId);
    }

    receive() external payable {} // receive ether

    // EVENTS
    event BidPlacement(uint256 indexed id, address indexed bidder, uint256 maxPrice, uint256 newPrice);
    event BidCancellation(uint256 indexed id, address indexed bidder, uint256 maxPrice, uint256 newPrice);
    event BidExecution(
        uint256 indexed id,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 maxPrice,
        uint256 newPrice
    );

    event Purchase(uint256 indexed tokenId, uint256 price);

    event Settlement(uint256 indexed tokenId, uint256 amount);
    event Foreclosure(uint256 indexed tokenId);
    event Relinquishment(uint256 indexed tokenId);
    event PriceChange(uint256 indexed tokenId, uint256 newPrice);

    event Deposit(uint256 indexed tokenId, uint256 amount);
    event Withdrawal(uint256 indexed tokenId, uint256 amount);

    // ERRORS
    function error_Unauthorized() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Unauthorized()");
    }

    function error_InvalidBid() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("InvalidBid()");
    }

    function error_InsolventToken(uint256 tokenId) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("InsolventToken(uint256)", tokenId);
    }

    function error_InsufficientFunds(uint256 available, uint256 needed) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("InsufficientFunds(uint256,uint256)", available, needed);
    }

    function error_ERC721NonExistentToken(uint256 tokenId) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenId);
    }

    function error_ERC721IncorrectOwner(
        address sender,
        uint256 tokenId,
        address owner
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("ERC721IncorrectOwner(address,uint256,address)", sender, tokenId, owner);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IHarber {
    // STRUCTS
    struct Bid {
        uint96 timestamp;
        address bidder;
        uint256 value;
        uint256 maxPrice;
        uint256 newPrice;
    }

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
    error NotForSale();
    error Unauthorized();
    error InvalidBid();
    error InsolventToken(uint256 tokenId);
    error InsufficientFunds(uint256 available, uint256 needed);

    // FUNCTIONS
    function buy(uint256 tokenId, uint256 newPrice) external payable;

    function relinquish(uint256 tokenId) external;

    function reservePrice() external view returns (uint256);

    // Token price functions

    function setPrice(uint256 tokenId, uint256 newPrice) external;

    function getPrice(uint256 tokenId) external view returns (uint256);

    // Account balance functions

    function withdrawAccountBalance(address account, uint256 amount) external;

    function getAccountBalance(address account) external view returns (uint256);

    // Token balance functions

    function depositTokenBalance(uint256 tokenId) external payable;

    function withdrawTokenBalance(uint256 tokenId, uint256 amount) external;

    function getTokenBalance(uint256 tokenId) external view returns (uint256);

    // Fee functions

    // TODO: do we need separate functions for tax settlement and foreclosure?
    function settleFees(uint256 tokenId) external;

    function feePeriod() external view returns (uint256);

    function feeRate() external view returns (uint256);

    function pendingFees(uint256 tokenId) external view returns (uint256);

    function isInsolvent(uint256 tokenId) external view returns (bool);

    function insolvencyTime(uint256 tokenId) external view returns (uint256);

    // TODO: single token bids vs collection bids
    function placeBid(uint256 maxPrice, uint256 newPrice) external payable returns (uint256);

    function getBid(uint256 id) external view returns (Bid memory);

    function executeBid(uint256 id, uint256 tokenId) external;

    function cancelBid(uint256 id) external;
}

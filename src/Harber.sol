// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IHarber} from "./interfaces/IHarber.sol";

contract Harber is ERC721, IHarber {
    using Address for address;

    uint256 public immutable totalSupply = 100;
    uint256 public immutable reservePrice;

    uint256 public immutable gracePeriod = 24 hours;

    uint256 public immutable feePeriod = 365 days;
    uint256 public immutable feeRate = 5_00; // 5%
    uint256 public immutable feeDenominator = 100_00;

    address public beneficiary;

    mapping(uint256 => uint256) _prices;
    mapping(uint256 => uint256) _tokenBalances;
    mapping(uint256 => uint256) _lastSettlements;

    mapping(address => uint256) _accountBalances;

    uint256 _nonce;
    mapping(uint256 => Bid) _bids;

    uint256 _mintCounter;

    modifier onlyAuthorized(uint256 tokenId) {
        _checkAuthorized(ownerOf(tokenId), _msgSender(), tokenId);
        _;
    }

    modifier onlySolvent(uint256 tokenId) {
        _checkSolvent(tokenId);
        _;
    }

    modifier onlyOwnedByContract(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner != address(this)) revert ERC721IncorrectOwner(address(this), tokenId, owner);
        _;
    }

    modifier notOwnedByContract(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner == address(this)) revert ERC721IncorrectOwner(address(this), tokenId, owner);
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _reservePrice,
        address _beneficiary
    ) ERC721(_name, _symbol) {
        reservePrice = _reservePrice;
        beneficiary = _beneficiary;

        // TODO: mint batch (ERC2309?)
        for (uint256 i; i < totalSupply; ++i) {
            _mint(address(this), _mintCounter++);
        }
    }

    function buy(uint256 tokenId, uint256 newPrice) external payable virtual override onlyOwnedByContract(tokenId) {
        if (msg.value < reservePrice) revert InsufficientFunds(msg.value, reservePrice);

        _tokenBalances[tokenId] = msg.value - reservePrice;
        _lastSettlements[tokenId] = block.timestamp;

        emit Purchase(tokenId, reservePrice);
        _transfer(address(this), _msgSender(), tokenId);
        _setPrice(tokenId, newPrice);
    }

    function relinquish(uint256 tokenId) external virtual override onlyAuthorized(tokenId) onlySolvent(tokenId) {
        _settle(tokenId);
        _relinquish(tokenId);
    }

    function setPrice(
        uint256 tokenId,
        uint256 newPrice
    ) external virtual override onlyAuthorized(tokenId) onlySolvent(tokenId) {
        _settle(tokenId);
        _setPrice(tokenId, newPrice);
    }

    function getPrice(uint256 tokenId) external view virtual override returns (uint256) {
        return _prices[tokenId];
    }

    function withdrawAccountBalance(address account, uint256 amount) external virtual override {
        // TODO: only withdraw own balance or can anyone trigger this?
        uint256 balance = _accountBalances[account];
        if (amount > balance) revert InsufficientFunds(balance, amount);

        _accountBalances[account] -= amount;
        _pay(account, amount);
    }

    function getAccountBalance(address account) external view virtual override returns (uint256) {
        return _accountBalances[account];
    }

    function depositTokenBalance(uint256 tokenId) external payable virtual onlySolvent(tokenId) {
        // TODO: check if token is owned by contract (?)

        _tokenBalances[tokenId] += msg.value;

        emit Deposit(tokenId, msg.value);
    }

    function withdrawTokenBalance(
        uint256 tokenId,
        uint256 amount
    ) external virtual override onlyAuthorized(tokenId) onlySolvent(tokenId) {
        _settle(tokenId);

        uint256 balance = _tokenBalances[tokenId];
        if (amount > balance) revert InsufficientFunds(balance, amount);

        _tokenBalances[tokenId] -= amount;

        emit Withdrawal(tokenId, amount);
    }

    function getTokenBalance(uint256 tokenId) external view virtual override returns (uint256) {
        return _tokenBalances[tokenId];
    }

    function settleFees(uint256 tokenId) external virtual override notOwnedByContract(tokenId) {
        bool insolvent = _isInsolvent(tokenId);

        _settle(tokenId);
        if (insolvent) _foreclose(tokenId);
    }

    function pendingFees(uint256 tokenId) external view virtual override returns (uint256) {
        return _pendingFees(tokenId);
    }

    function isInsolvent(uint256 tokenId) external view virtual override returns (bool) {
        return _isInsolvent(tokenId);
    }

    function insolvencyTime(uint256 tokenId) external view virtual override returns (uint256) {
        uint256 feesPerSecond = _calculateFee(_prices[tokenId], 1);
        if (feesPerSecond == 0) return _lastSettlements[tokenId];

        return _lastSettlements[tokenId] + _tokenBalances[tokenId] / feesPerSecond;
    }

    function placeBid(uint256 maxPrice, uint256 newPrice) external payable virtual override returns (uint256) {
        if (msg.value < maxPrice) revert InsufficientFunds(msg.value, maxPrice);

        uint256 id = _nonce++;
        address bidder = _msgSender();

        // if (bidder == address(0)) revert InvalidBid();

        _bids[id] = Bid({
            timestamp: uint96(block.timestamp),
            bidder: bidder,
            value: msg.value,
            maxPrice: maxPrice,
            newPrice: newPrice
        });

        emit BidPlacement(id, bidder, maxPrice, newPrice);
        return id;
    }

    function getBid(uint256 id) external view virtual override returns (Bid memory) {
        return _bids[id];
    }

    function executeBid(uint256 id, uint256 tokenId) external virtual override onlySolvent(tokenId) {
        Bid memory bid = _bids[id];
        if (bid.bidder == address(0)) revert InvalidBid();

        address owner = ownerOf(tokenId);

        // TODO: restrict to bidder or admin (?)
        bool authorized = _msgSender() == owner ||
            (bid.maxPrice >= _prices[tokenId] && bid.timestamp + gracePeriod <= block.timestamp);
        if (!authorized) revert Unauthorized();

        _settle(tokenId);

        _accountBalances[owner] += bid.maxPrice;
        _accountBalances[owner] += _tokenBalances[tokenId];

        uint256 deposit = bid.value - bid.maxPrice;
        _tokenBalances[tokenId] = deposit;
        _prices[tokenId] = bid.newPrice;

        delete _bids[id];

        emit BidExecution(id, tokenId, bid.bidder, bid.maxPrice, bid.newPrice);
        _transfer(owner, bid.bidder, tokenId);
    }

    function cancelBid(uint256 id) external virtual override {
        Bid memory bid = _bids[id];
        if (bid.bidder == address(0)) revert InvalidBid();

        if (_msgSender() != bid.bidder) revert Unauthorized();

        delete _bids[id];

        emit BidCancellation(id, bid.bidder, bid.maxPrice, bid.newPrice);
        _pay(bid.bidder, bid.value);
    }

    function _isInsolvent(uint256 tokenId) internal view virtual returns (bool) {
        return ownerOf(tokenId) == address(this) || _pendingFees(tokenId) > _tokenBalances[tokenId];
    }

    function _checkSolvent(uint256 tokenId) internal view virtual {
        if (_isInsolvent(tokenId)) revert InsolventToken(tokenId);
    }

    function _pendingFees(uint256 tokenId) internal view virtual returns (uint256) {
        if (ownerOf(tokenId) == address(this)) return 0;

        return _calculateFee(_prices[tokenId], block.timestamp - _lastSettlements[tokenId]);
    }

    function _calculateFee(uint256 price, uint256 duration) internal view virtual returns (uint256) {
        return (price * duration * feeRate) / (feePeriod * feeDenominator);
    }

    function _setPrice(uint256 tokenId, uint256 newPrice) internal virtual {
        _prices[tokenId] = newPrice;
        emit PriceChange(tokenId, newPrice);
    }

    function _settle(uint256 tokenId) internal {
        uint256 pending = _pendingFees(tokenId);
        uint256 available = _tokenBalances[tokenId];

        uint256 amount = pending < available ? pending : available;

        _tokenBalances[tokenId] -= amount;
        _lastSettlements[tokenId] = block.timestamp;

        emit Settlement(tokenId, amount);
        _pay(beneficiary, amount);
    }

    function _foreclose(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);

        _accountBalances[owner] += reservePrice;

        _tokenBalances[tokenId] = 0;
        _prices[tokenId] = 0;

        emit Foreclosure(tokenId);
        _transfer(owner, address(this), tokenId);
    }

    function _relinquish(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);

        _accountBalances[owner] += reservePrice;
        _accountBalances[owner] += _tokenBalances[tokenId];

        _tokenBalances[tokenId] = 0;
        _prices[tokenId] = 0;

        emit Relinquishment(tokenId);
        _transfer(owner, address(this), tokenId);
    }

    function _pay(address recipient, uint256 amount) internal {
        if (amount > 0) Address.sendValue(payable(recipient), amount);
    }
}

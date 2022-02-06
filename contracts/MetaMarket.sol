// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IMetaMarket.sol';
import './IMetaItem.sol';
import './IMetaLand.sol';
import './IMetaCity.sol';

contract MetaMarket is IMetaMarket, Pausable, Ownable{

  uint private constant BASIS_POINT = 10000;

  uint private _exchangeRate; // 300 = 3%
  uint private _maxListItems; // 10 (max items when return market items as list)
  uint private _maxContentUrlLen; // 1,000 characters

  // address that can pause the market
  mapping(address => bool) private _pausers;

  // map[landId] => map[itemAutonumber] => MarketItem
  mapping(uint => mapping(uint => MarketItem)) _sellingItems;
  // map[landId] => itemAutonumber
  mapping(uint => uint) _currentItemAutonumber;

  IERC20 private _paymentToken;
  IMetaItem private _item;
  IMetaLand private _land;
  IMetaCity private _city;

  modifier onlyLandOwner(uint landId) {
    require(_land.ownerOf(landId) == msg.sender, 'metamarket: not land owner');
    _;
  }

  modifier validAutonumber(uint landId, uint itemAutonumber) {
    require(_currentItemAutonumber[landId] >= itemAutonumber && itemAutonumber > 0, 'metamarket: invalid itemAutonumber');
    _;
  }

  constructor(
    address paymentTokenAddr,
    address itemAddr,
    address landAddr,
    address cityAddr,
    uint initExchangeRate,
    uint initMaxContentUrlLen,
    uint initMaxListItems) {
    
    require(paymentTokenAddr != address(0), 'metamarket: invalid payment token addr');
    require(itemAddr != address(0), 'metamarket: invalid item addr');
    require(landAddr != address(0), 'metamarket: invalid land addr');
    require(cityAddr != address(0), 'metamarket: invalid city addr');
    require(initMaxContentUrlLen > 0, 'metamarket: invalid max content url len');
    require(initMaxListItems > 0 && initMaxListItems <= 10, 'metamarket: invalid max list items');

    _paymentToken = IERC20(paymentTokenAddr);
    _item = IMetaItem(itemAddr);
    _land = IMetaLand(landAddr);
    _city = IMetaCity(cityAddr);
    _exchangeRate = initExchangeRate;
    _maxContentUrlLen = initMaxContentUrlLen;
    _maxListItems = initMaxListItems;
  }

  function postItemForSell(
    uint landId,
    bytes32 itemName,
    uint itemType,
    uint initialPrice,
    uint priceIncrementalRate,
    uint priceIncrementEveryNItems, // If priceIncrementEveryNItems = 0, the price is not increment
    uint totalItems,
    string memory itemContentUrl) public 
      whenNotPaused 
      onlyLandOwner(landId) {

    // Modifiers
    // - whenNotPaused: allow to post item when market is not paused
    // - onlyLandOwner: allow only land owner can post item for sell

    // Validate url length
    require(bytes(itemContentUrl).length <= _maxContentUrlLen, 'metamarket: item content url too long');

    // Validate price
    require(initialPrice > 0, 'metamarket: zero price is not allowed');

    // Increment autonumber and add item to selling list
    uint itemAutonumber = _currentItemAutonumber[landId];
    itemAutonumber += 1;
    _currentItemAutonumber[landId] = itemAutonumber;

    // Save selling items
    _sellingItems[landId][itemAutonumber] = MarketItem({
      landId: landId,
      autonumber: itemAutonumber,
      itemContentUrl: itemContentUrl,
      itemName: itemName,
      itemType: itemType,
      initialPrice: initialPrice,
      currentPrice: initialPrice,
      priceIncrementalRate: priceIncrementalRate,
      priceIncrementEveryNItems: priceIncrementEveryNItems,
      totalItems: totalItems,
      lastIncrementCount: 0,
      soldItems: 0,
      isPaused: false
    });
  }

  function currentItemAutonumber(uint landId) public view returns (uint) {
    return _currentItemAutonumber[landId];
  }
  
  function pauseSell(uint landId, uint itemAutonumber, bool isPaused) public 
    onlyLandOwner(landId) 
    validAutonumber(landId, itemAutonumber) {

    // Modifiers
    // - onlyLandOwner: allow only land owner can pause the sell
    // - validAutonumber: allow only valid item autonumber

    MarketItem storage item = _sellingItems[landId][itemAutonumber];
    item.isPaused = isPaused;
  }
  
  function currentPrice(uint landId, uint itemAutonumber) public view returns (uint) {
    MarketItem memory item = _sellingItems[landId][itemAutonumber];
    return item.currentPrice;
  }

  function buyItem(uint landId, uint itemAutonumber, uint buyPrice) public 
    whenNotPaused 
    validAutonumber(landId, itemAutonumber) {

    // Modifiers
    // - whenNotPaused: allow to buy item when not paused
    // - validAutonumber: allow only valid itemAutonumber

    // 1. find from selling list
    MarketItem storage item = _sellingItems[landId][itemAutonumber];

    // 2. validate if status of item is not paused
    require(item.isPaused == false, 'metamarket: item is paused');

    // 3. validate the stock by compare totalItems with soldItems
    require(item.totalItems > item.soldItems, 'metamarket: items out of stock');

    // 4. validate buyPrice must >= currentPrice
    require(item.currentPrice <= buyPrice, 'metamarket: buy price too low');

    // 5. transfer payment and keep fee at market
    address landOwner = _land.ownerOf(landId);
    uint fee = buyPrice * _exchangeRate / BASIS_POINT;
    if (fee > 0) {
      _paymentToken.transferFrom(msg.sender, address(this), fee);
    }
    _paymentToken.transferFrom(msg.sender, landOwner, buyPrice - fee);

    // 6. mint item for buyer and stamp the business who create the item to the item metadata
    IMetaCity.BusinessUnit memory business = _city.getBusinessByLandId(landId);
    _item.mintFor(
      msg.sender, 
      item.itemName, 
      item.itemType, 
      item.itemContentUrl,
      landId,
      business.businessName);

    // 7. update number of selling items
    item.soldItems += 1;

    // 8. re-calculate current price
    if (item.priceIncrementEveryNItems > 0 && item.priceIncrementalRate > 0) {
      uint incrementCount = item.soldItems / item.priceIncrementEveryNItems;
      if (item.lastIncrementCount < incrementCount) {
        item.lastIncrementCount = incrementCount;
        item.currentPrice = item.currentPrice + (item.currentPrice * item.priceIncrementalRate / BASIS_POINT);
      }
    }
  }

  function listItems(uint landId, uint fromAutonumber) public view returns (MarketItem[10] memory) {
    MarketItem[10] memory items;

    uint currentAutonumber = currentItemAutonumber(landId);

    // If send fromAutonumber = 0, send the latest items page
    if (fromAutonumber == 0) {
      fromAutonumber = currentAutonumber;
    }

    // Check fromAutonumber must be in range
    if (fromAutonumber > currentAutonumber) {
      return items;
    }

    uint toAutonumber = 0;
    if (_maxListItems < fromAutonumber) {
      toAutonumber = fromAutonumber - _maxListItems;
    }

    uint i = 0;

    for (uint itemAutonumber=fromAutonumber; itemAutonumber>toAutonumber; itemAutonumber--) {
      if (itemAutonumber <= 0) {
        break;
      }
      MarketItem memory item = _sellingItems[landId][itemAutonumber];
      items[i] = item;
      i++;
    }
    return items;
  }

  function getItem(uint landId, uint itemAutonumber) public view returns (MarketItem memory) {
    MarketItem memory item = _sellingItems[landId][itemAutonumber];
    return item;
  }

  function exists(uint landId, uint itemAutonumber) public view returns (bool) {
    return _sellingItems[landId][itemAutonumber].autonumber > 0;
  }

  function pauseMarket() public onlyOwner {
    _pause();
  }

  function resumeMarket() public onlyOwner {
    _unpause();
  }

  function setPaymentToken(address paymentTokenAddr) public onlyOwner {
    _paymentToken = IERC20(paymentTokenAddr);
  }

  function setMetaItem(address itemAddr) public onlyOwner {
    _item = IMetaItem(itemAddr);
  }

  function setMetaLand(address landAddr) public onlyOwner {
    _land = IMetaLand(landAddr);
  }

  function setMetaCity(address cityAddr) public onlyOwner {
    _city = IMetaCity(cityAddr);
  }

  function setExchangeRate(uint exchangeRate) public onlyOwner {
    _exchangeRate = exchangeRate;
  }
  
  function setMaxContentUrlLen(uint maxContentUrlLen) public onlyOwner {
    require(maxContentUrlLen > 0, 'metamarket: invalid max content url len');
    _maxContentUrlLen = maxContentUrlLen;
  }

  function setMaxListItems(uint maxListItems) public onlyOwner {
    require(maxListItems > 0 && maxListItems <= 10, 'metamarket: invalid max list items');
    _maxListItems = maxListItems;
  }

  function ownerWithdraw(uint amountOut) public onlyOwner {
    _paymentToken.transfer(owner(), amountOut);
  }
}
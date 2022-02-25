// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './ISecondaryMarket.sol';
import './IMetaItem.sol';
import './IMetaLand.sol';

contract SecondaryMarket is ISecondaryMarket, Ownable{

  uint private constant BUYORDER_STATUS_CREATED = 0;
  uint private constant BUYORDER_STATUS_COMPLETED = 1;
  uint private constant BUYORDER_STATUS_DELETED = 2;
  uint private constant BUYORDER_STATUS_OVERRIDED = 3;

  uint private constant BASIS_POINT = 10000;
  uint private _exchangeRate; // 200 = 2%
  uint private _ownerCommissionRate; // 300 = 3%

  IERC20 private _paymentToken;
  IMetaItem private _item;
  IMetaLand private _land;

  Counter private _buyOrderAutonumber;

  uint private _delayBuyOrderBlocks; // 20 blocks

  // mapping of landId => itemContentUrl => buyOrderAutonumber
  mapping(uint => mapping(string => uint)) private _buyOrders;
  // mapping of buyOrderAutonumber => buyOrder
  mapping(uint => BuyOrder) _primaryBuyOrders;

  event BuyOrderCreated(address indexed buyer, uint indexed landId, uint indexed autonumber, string itemContentUrl, uint buyPrice, uint endedBlock);
  event BuyOrderFinished(address indexed seller, uint indexed landId, uint indexed autonumber, string itemContentUrl, uint sellPrice, uint status);

  constructor(
    address paymentTokenAddr,
    address itemAddr,
    address landAddr,
    uint initExchangeRate,
    uint initOwnerCommissionRate,
    uint initDelayBuyOrderBlocks) {

    require(paymentTokenAddr != address(0), 'secondarymarket: invalid payment token addr');
    require(itemAddr != address(0), 'secondarymarket: invalid item addr');
    require(landAddr != address(0), 'secondarymarket: invalid land addr');
    require(initDelayBuyOrderBlocks > 0, 'secondarymarket: invalid delay buy order blocks');

    _paymentToken = IERC20(paymentTokenAddr);
    _item = IMetaItem(itemAddr);
    _land = IMetaLand(landAddr);
    _exchangeRate = initExchangeRate;
    _ownerCommissionRate = initOwnerCommissionRate;
    _delayBuyOrderBlocks = initDelayBuyOrderBlocks;
  }

  function createBuyOrder(
    uint creatorBusinessId,
    bytes32 itemName,
    uint itemType,
    string memory itemContentUrl,
    uint buyPrice,
    uint endedBlock) public {

    // 1. Validate the buy order
    require(endedBlock >= block.number, 'secondarymarket: ended block too low');
    require(buyPrice > 0, 'secondarymarket: buy price must not zero');

    // 2. Check allowance and balance of buyer must greater than the buy price
    require(_paymentToken.allowance(msg.sender, address(this)) >= buyPrice, 'secondarymarket: allowance too low');
    require(_paymentToken.balanceOf(msg.sender) >= buyPrice, 'secondarymarket: balance too low');

    // 3. create the order (index by businessId and itemContentUrl
    uint curBuyOrderAutonumber = _buyOrders[creatorBusinessId][itemContentUrl];
    BuyOrder memory curBuyOrder = _primaryBuyOrders[curBuyOrderAutonumber];
    if (curBuyOrder.autonumber > 0) {
      // To override the current buy order, at least one of the following condition must be met,
      // - no buy order
      // - old buy order has expired OR 
      // - (new buy order price is greater than old buy order price AND old buy order created block has pass _delayBuyOrderBlocks) OR
      // - old buy order allowance < order.price OR // allowance not enough
      // - old buy order balance < order.price  // balance not enough
      bool canOverride = 
          curBuyOrder.endedBlock < block.number || // old buy order has expired
          (curBuyOrder.price < buyPrice && block.number - curBuyOrder.createdAt > _delayBuyOrderBlocks) || // new price greater
          _paymentToken.allowance(curBuyOrder.buyerAddr, address(this)) < curBuyOrder.price || // allowance not enough
          _paymentToken.balanceOf(curBuyOrder.buyerAddr) < curBuyOrder.price; // balance not enough
      require(canOverride, 'secondarymarket: cannot override current buy order with this conditions');

      // 4. Emit event when the buy order has been overrided
      emit BuyOrderFinished(address(0), creatorBusinessId, curBuyOrder.autonumber, itemContentUrl, 0, BUYORDER_STATUS_OVERRIDED);
    }
    
    // 5. Increment counter and create buy order, waiting for seller to accept
    Counter storage buyOrderAutonumber = _buyOrderAutonumber;
    buyOrderAutonumber.value += 1;
    uint autonumber = buyOrderAutonumber.value;

    BuyOrder memory buyOrder = BuyOrder({
      creatorBusinessId: creatorBusinessId,
      itemName: itemName,
      itemType: itemType,
      itemContentUrl: itemContentUrl,
      autonumber: autonumber,
      price: buyPrice,
      endedBlock: endedBlock,
      buyerAddr: msg.sender,
      createdAt: block.number
    });
    _buyOrders[creatorBusinessId][itemContentUrl] = autonumber;
    _primaryBuyOrders[autonumber] = buyOrder;

    // 6. Emit events buy order created
    emit BuyOrderCreated(msg.sender, creatorBusinessId, autonumber, itemContentUrl, buyPrice, endedBlock);
  }

  function acceptBuyOrder(
    uint itemId,
    uint buyOrderAutonumber,
    uint sellPrice) public {
    
    // 1. Validate the seller must be the owner of itemId
    address itemOwner = _item.ownerOf(itemId);
    require(itemOwner == msg.sender, 'secondarymarket: not item owner');

    IMetaItem.Item memory item = _item.itemInfo(itemId);

    // 2. Match the orders
    uint autonumber = _buyOrders[item.creatorBusinessId][item.itemContentUrl];
    require(autonumber == buyOrderAutonumber, 'secondarymarket: buyOrderAutonumber not match');

    BuyOrder memory curBuyOrder = _primaryBuyOrders[autonumber];
    // 3. Validate the buy order 
    //    - The buyorder.autonumber must not be zero
    require(curBuyOrder.autonumber > 0, 'secondarymarket: no buy order');
    //    - The given order number must point to the current buy order
    require(curBuyOrder.autonumber == buyOrderAutonumber, 'secondarymarket: the autonumber does not point to current buy order');
    //    - The buy order must not expired
    require(curBuyOrder.endedBlock > block.number, 'secondarymarket: order expired');
    //    - Sell price must equal to or less than the buy price
    require(curBuyOrder.price >= sellPrice, 'secondarymarket: sell price too high');
    //    - Validate itemName and itemType
    require(curBuyOrder.itemName == item.itemName, 'secondarymarket: item name not match');
    require(curBuyOrder.itemType == item.itemType, 'secondarymarket: item type not match');

    // 4. Calculate fee and transfer fee to MetaCity
    uint fee = 0;
    fee = curBuyOrder.price * _exchangeRate / BASIS_POINT;
    if (fee > 0) {
      _paymentToken.transferFrom(curBuyOrder.buyerAddr, address(this), fee);
    }

    // 5. Calculate commission for business owner (3% of transaction)
    address landOwner = _land.ownerOf(item.creatorBusinessId);
    uint commission = 0;
    commission = curBuyOrder.price * _ownerCommissionRate / BASIS_POINT;
    if (commission > 0) {
      _paymentToken.transferFrom(curBuyOrder.buyerAddr, landOwner, commission);
    }

    // 6. Transfer payment from buyer
    _paymentToken.transferFrom(curBuyOrder.buyerAddr, itemOwner, curBuyOrder.price - (fee + commission));

    // 7. Transfer item to buyer
    _item.transferFrom(itemOwner, curBuyOrder.buyerAddr, itemId);

    // 8. Emit events
    emit BuyOrderFinished(msg.sender, item.creatorBusinessId, curBuyOrder.autonumber, item.itemContentUrl, sellPrice, BUYORDER_STATUS_COMPLETED);

    // 9. Reset buy orders
    delete _buyOrders[item.creatorBusinessId][item.itemContentUrl];
  }

  function deleteBuyOrder( 
    uint creatorBusinessId,
    string memory itemContentUrl) public {

    // 1. Match the orders
    uint autonumber = _buyOrders[creatorBusinessId][itemContentUrl];
    require(autonumber > 0, 'secondarymarket: no buy order');

    BuyOrder memory buyOrder = _primaryBuyOrders[autonumber];
    // 2. Validate the buy order
    //    - The buyorder.autonumber must not be zero
    require(buyOrder.autonumber > 0, 'secondarymarket: no buy order');
    //    - Validate the deleter must be owner of buy order
    require(buyOrder.buyerAddr == msg.sender, 'secondarymarket: not buy order owner');

    // 3. Delete buy orders
    delete _buyOrders[creatorBusinessId][itemContentUrl];
  
    // 4. Emit events when buy order has been deleted
    emit BuyOrderFinished(address(0), creatorBusinessId, buyOrder.autonumber, itemContentUrl, 0, BUYORDER_STATUS_DELETED);
  }

  function getBuyOrderByAutonumber(uint autonumber) public view returns (BuyOrder memory) {
    return _primaryBuyOrders[autonumber];
  }

  function getBuyOrderByItemContentUrl(uint creatorBusinessId, string memory itemContentUrl) public view returns (BuyOrder memory) {
    return _primaryBuyOrders[_buyOrders[creatorBusinessId][itemContentUrl]];
  }

  function setPaymentToken(address paymentTokenAddr) public onlyOwner {
    _paymentToken = IERC20(paymentTokenAddr);
  }

  function setMetaItem(address metaItemAddr) public onlyOwner {
    _item = IMetaItem(metaItemAddr);
  }

  function setMetaLand(address metaLandAddr) public onlyOwner {
    _land = IMetaLand(metaLandAddr);
  }
  
  function getLatestBuyOrderAutonumber() public view returns (uint) {
    return _buyOrderAutonumber.value;
  }

  function setDelayBuyOrderBlocks(uint delayBuyOrderBlocks) public onlyOwner {
    _delayBuyOrderBlocks = delayBuyOrderBlocks;
  }

  function setExchangeRate(uint exchangeRate) public onlyOwner {
    _exchangeRate = exchangeRate;
  }

  function setOwnerCommissionRate(uint ownerCommissionRate) public onlyOwner {
    _ownerCommissionRate = ownerCommissionRate;
  }

  function ownerWithdraw(uint amountOut) public onlyOwner {
    _paymentToken.transfer(owner(), amountOut);
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IMetaLand.sol';
import './IMetaItem.sol';
import './IMetaCity.sol';

contract MetaCity is IMetaCity, Ownable{

  uint private constant BUYORDER_STATUS_CREATED = 0;
  uint private constant BUYORDER_STATUS_COMPLETED = 1;
  uint private constant BUYORDER_STATUS_DELETED = 2;
  uint private constant BUYORDER_STATUS_OVERRIDED = 3;

  uint private constant BASIS_POINT = 10000; 
  
  uint private _exchangeRate; // 300 = 3%
  uint private _businessSetupFee; // 3 * 10^18
  uint private _citizenRegistrationFee; // 1 * 10^18
  uint private _landBasePriceIncrementRate; // 1000 = 10%
  uint private _landBasePrice; // 100 CITY
  uint private _delayBuyOrderBlocks; // 20 blocks
  
  Counter private _buyOrderAutonumber;
  Counter private _sellOrderAutonumber;

  IERC20 private _paymentToken;
  IMetaLand private _land;
  IMetaItem private _item;

  // mapping of landId => Businesses
  mapping(uint => BusinessUnit) private _businesses;
  // mapping of landId => sell order autonumber
  mapping(uint => uint) private _landSellOrders;
  // mapping of autonumber => sell order
  mapping(uint => SellOrder) private _primarySellOrders;
  // mapping of landId => BuyOrders
  // the land can have only single highest buy order at a time
  mapping(uint => uint) private _landBuyOrders;
  // mapping of autonumber => buy order
  mapping(uint => BuyOrder) private _primaryBuyOrders;
  // mapping of cityBlockId => current base price
  mapping(uint => uint) private _basePrices;
  // mapping of address => Citizen
  mapping(address => Citizen) private _citizens;

  event SellOrderCreated(address indexed seller, uint indexed landId, uint indexed autonumber, uint sellPrice, uint endedBlock);
  event BuyOrderCreated(address indexed buyer, uint indexed landId, uint indexed autonumber, uint buyPrice, uint endedBlock);
  event SellOrderFinished(address indexed buyer, uint indexed landId, uint indexed autonumber, uint buyPrice);
  event BuyOrderFinished(address indexed seller, uint indexed landId, uint indexed autonumber, uint sellPrice, uint status);
  event MetaLandUpdated(uint indexed landId, address indexed prevOwner, address indexed newOwner, bytes32 businessName, uint businessType);
  event CitizenRegistered(address indexed citizenAddr, bytes32 name, uint occupation);

  constructor(
    address paymentTokenAddr,
    address landAddr,
    address itemAddr,
    uint initExchangeRate,
    uint initBusinessSetupFee,
    uint initLandBasePrice,
    uint initLandBasePriceIncrementRate,
    uint initCitizenRegistrationFee,
    uint initDelayBuyOrderBlocks) {

    require(paymentTokenAddr != address(0), 'metacity: invalid payment token addr');
    require(landAddr != address(0), 'metacity: invalid land addr');
    require(itemAddr != address(0), 'metacity: invalid item addr');
    require(initDelayBuyOrderBlocks > 0, 'metacity: invalid delay buy order blocks');

    _paymentToken = IERC20(paymentTokenAddr);
    _land = IMetaLand(landAddr);
    _item = IMetaItem(itemAddr);
    _exchangeRate = initExchangeRate;
    _businessSetupFee = initBusinessSetupFee;
    _landBasePrice = initLandBasePrice;
    _landBasePriceIncrementRate = initLandBasePriceIncrementRate;
    _citizenRegistrationFee = initCitizenRegistrationFee;
    _delayBuyOrderBlocks = initDelayBuyOrderBlocks;
  }

  function mintEmptyLand(
    uint landId, 
    uint buyPrice,
    bytes32 businessName,
    uint businessType) public {
    
    // 1. Validate that land must not exists (no previous owner)
    require(_land.exists(landId) == false, 'metacity: not empty land');

    // 2. Validate the buyPrice must greater than current land price in the block
    uint cityBlockId = cityBlockIdByLandId(landId);
    uint currentPrice = _basePrices[cityBlockId];
    if (currentPrice == 0) {
      currentPrice = _landBasePrice;
    }
    require(currentPrice <= buyPrice, 'metacity: buy price too low');

    // 3. Transfer payment from buyer to MetaCity
    _paymentToken.transferFrom(msg.sender, address(this), currentPrice);

    // 4. Mint land to buyer
    _land.mint(msg.sender, landId);

    // 5. Increment current price
    _basePrices[cityBlockId] = currentPrice + (currentPrice * _landBasePriceIncrementRate / BASIS_POINT);
    
    // 7. Setup new business
    _businesses[landId] = BusinessUnit({
      businessName: businessName,
      businessType: businessType,
      buildingItemId: 0,
      buildingContentUrl: ''
    });

    // 8. Emit events
    // event MetaLandUpdated(uint indexed landId, address indexed prevOwner, address indexed newOwner, bytes32 businessName, uint businessType);
    emit MetaLandUpdated(landId, address(0), msg.sender, businessName, businessType);
  }

  function createSellOrder(
    uint landId,
    uint sellPrice,
    uint endedBlock) public {

    // 1. Validate the seller must be the owner of landId
    require(_land.ownerOf(landId) == msg.sender, 'metacity: not land owner');

    // 2. Ended block must greater than or equal the current block
    require(endedBlock >= block.number, 'metacity: ended block too low');

    // 3. Validate this contract is the approver
    require(_land.getApproved(landId) == address(this), 'metacity: contract is not approved');

    // 4. Create the order (index by landId and autonumber)
    Counter storage sellOrderAutonumber = _sellOrderAutonumber;
    sellOrderAutonumber.value += 1;
    uint autonumber = sellOrderAutonumber.value;
 
    SellOrder memory sellOrder = SellOrder({
      landId: landId,
      autonumber: autonumber,
      price: sellPrice,
      endedBlock: endedBlock,
      sellerAddr: msg.sender,
      completed: false,
      deleted: false,
      createdAt: block.number
    });
    _primarySellOrders[autonumber] = sellOrder;
    _landSellOrders[landId] = autonumber;

    // 6. Emit events
    emit SellOrderCreated(msg.sender, landId, autonumber, sellPrice, endedBlock);
  }

  function deleteSellOrder(uint landId) public {

    // 1. Validate the seller must be the owner of landId
    require(_land.ownerOf(landId) == msg.sender, 'metacity: not land owner');

    // 2. Get current sell orders
    require(_landSellOrders[landId] > 0, 'metacity: no sell order');

    uint autonumber = _landSellOrders[landId];

    // 3. Delete sell orders
    _landSellOrders[landId] = 0;
    _primarySellOrders[autonumber].deleted = true;

    // 4. Emit events SellOrderFinished, 
    //    - the buyer = 0 mean the sell order has been deleted
    emit SellOrderFinished(address(0), landId, autonumber, 0);
  }

  function createBuyOrder(
    uint landId,
    uint buyPrice,
    uint endedBlock,
    bytes32 businessName,
    uint businessType) public {

    // 1. Validate the buy order
    require(endedBlock >= block.number, 'metacity: ended block too low');
    require(buyPrice > 0, 'metacity: buy price must not zero');

    // 2. Land must exists
    require(_land.exists(landId), 'metacity: land is not exist');
    address landOwner = _land.ownerOf(landId);

    // 3. Check allowance and balance of buyer must greater than the buy price
    require(_paymentToken.allowance(msg.sender, address(this)) >= buyPrice, 'metacity: allowance too low');
    require(_paymentToken.balanceOf(msg.sender) >= buyPrice, 'metacity: balance too low');

    // 4. Match with the sell orders, if exists
    //    - land owner must exists and equal to seller address
    //    - sell order must not expired
    SellOrder storage curSellOrder = _primarySellOrders[_landSellOrders[landId]];
    if (landOwner == curSellOrder.sellerAddr &&
        curSellOrder.endedBlock > block.number) {

      require(buyPrice >= curSellOrder.price, 'metacity: buy price too low');

      // 5. Calculate exchange fee and transfer exchange fee to MetaCity
      uint fee = buyPrice * _exchangeRate / BASIS_POINT;
      if (fee > 0) {
        _paymentToken.transferFrom(msg.sender, address(this), fee);
      }
    
      // 6. Transfer payment to land seller
      _paymentToken.transferFrom(msg.sender, landOwner, buyPrice - fee);

      // 7. Transfer land to buyer
      _land.transferFrom(landOwner, msg.sender, landId);
      
      // 8. Setup new business for new owner
      BusinessUnit memory curBusiness = _businesses[landId];
      _businesses[landId] = BusinessUnit({
        businessName: businessName,
        businessType: businessType,
        buildingItemId: curBusiness.buildingItemId,
        buildingContentUrl: curBusiness.buildingContentUrl
      });

      // 9. Reset sell orders and mark the current sell order to completed
      _landSellOrders[landId] = 0;
      curSellOrder.completed = true;

      // 10. Reset buy orders
      _landBuyOrders[landId] = 0;

      // 11. Emit events
      emit SellOrderFinished(msg.sender, landId, curSellOrder.autonumber, buyPrice);
      emit MetaLandUpdated(landId, landOwner, msg.sender, businessName, businessType);
      return;
    }

    // 12. If no sell order matched, create the order (index by landId and autonumber)
    BuyOrder storage curBuyOrder = _primaryBuyOrders[_landBuyOrders[landId]];
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
      require(canOverride, 'metacity: cannot override current buy order with this conditions');
      
      // If pass condition, the current buy order will be flag as overrided
      curBuyOrder.overrided = true;
      // 13. Emit event when the buy order has been overrided
      emit BuyOrderFinished(address(0), landId, curBuyOrder.autonumber, 0, BUYORDER_STATUS_OVERRIDED);
    }
    
    // 14. Increment counter and create buy order, waiting for seller to accept
    Counter storage buyOrderAutonumber = _buyOrderAutonumber;
    buyOrderAutonumber.value += 1;
    uint autonumber = buyOrderAutonumber.value;

    BuyOrder memory buyOrder = BuyOrder({
      landId: landId,
      autonumber: autonumber,
      price: buyPrice,
      endedBlock: endedBlock,
      buyerAddr: msg.sender,
      businessName: businessName,
      businessType: businessType,
      completed: false,
      deleted: false,
      overrided: false,
      createdAt: block.number
    });
    _landBuyOrders[landId] = autonumber;
    _primaryBuyOrders[autonumber] = buyOrder;

    // 15. Emit events buy order created
    emit BuyOrderCreated(msg.sender, landId, autonumber, buyPrice, endedBlock);
  }

  function acceptBuyOrder(
    uint landId,
    uint autonumber,
    uint sellPrice) public {
    
    // 1. Validate the seller must be the owner of landId
    address landOwner = _land.ownerOf(landId);
    require(landOwner == msg.sender, 'metacity: not land owner');

    // 2. Match the orders
    BuyOrder storage curBuyOrder = _primaryBuyOrders[_landBuyOrders[landId]];

    // 3. Validate the buy order 
    //    - The given order number must point to the current buy order
    require(curBuyOrder.autonumber == autonumber, 'metacity: the autonumber does not point to current buy order');
    //    - The buy order must not expired
    require(curBuyOrder.endedBlock > block.number, 'metacity: order expired');
    //    - Sell price must equal to or less than the buy price
    require(curBuyOrder.price >= sellPrice, 'metacity: sell price too high');

    // 4. Calculate fee and transfer fee to MetaCity
    uint fee = 0;
    fee = curBuyOrder.price * _exchangeRate / BASIS_POINT;
    if (fee > 0) {
      _paymentToken.transferFrom(curBuyOrder.buyerAddr, address(this), fee);
    }

    // 5. Transfer payment from buyer
    _paymentToken.transferFrom(curBuyOrder.buyerAddr, landOwner, curBuyOrder.price - fee);

    // 6. Transfer land to buyer
    _land.transferFrom(landOwner, curBuyOrder.buyerAddr, landId);

    // 7. Setup new business
    BusinessUnit memory curBusiness = _businesses[landId];
    _businesses[landId] = BusinessUnit({
      businessName: curBuyOrder.businessName,
      businessType: curBuyOrder.businessType,
      buildingItemId: curBusiness.buildingItemId,
      buildingContentUrl: curBusiness.buildingContentUrl
    });

    // 8. Reset sell orders
    SellOrder storage curSellOrder = _primarySellOrders[_landSellOrders[landId]];
    if (curSellOrder.autonumber > 0) {
      curSellOrder.deleted = true;
      // 9. Emit events SellOrderFinished,
      //    - the buyer = 0 mean the sell order has been deleted
      emit SellOrderFinished(address(0), landId, autonumber, 0);
    }
    _landSellOrders[landId] = 0;

    // 10. Reset buy orders and mark it to completed
    _landBuyOrders[landId] = 0;
    curBuyOrder.completed = true;

    // 11. Emit events
    emit BuyOrderFinished(msg.sender, landId, curBuyOrder.autonumber, sellPrice, BUYORDER_STATUS_COMPLETED);
    emit MetaLandUpdated(landId, msg.sender, curBuyOrder.buyerAddr, curBuyOrder.businessName, curBuyOrder.businessType);
  }

  function deleteBuyOrder(uint landId) public {

    // 1. Get current buy orders
    require(_landBuyOrders[landId] > 0, 'metacity: no buy order');
    uint autonumber = _landBuyOrders[landId];
    BuyOrder memory buyOrder = _primaryBuyOrders[autonumber];

    // 2. Validate the deleter must be owner of buy order
    require(buyOrder.buyerAddr == msg.sender, 'metacity: not buy order owner');

    // 3. Delete buy orders
    _landBuyOrders[landId] = 0;
    _primaryBuyOrders[autonumber].deleted = true;

    // 4. Emit events when buy order has been deleted
    emit BuyOrderFinished(address(0), landId, autonumber, 0, BUYORDER_STATUS_DELETED);
  }

  function cityBlockIdByLandId(uint landId) internal pure returns (uint) {
    // landId format = KKKCCCBBBPPP
    // - KKK = countryId
    // - CCC = cityId
    // - BBB = block
    // - PPP = position in block
    // cityBlockId format = [KKKCCCBBB]PPP
    // so to find city block id we devide landId by 1000 to remove PPP
    return landId / 1000;
  }

  function currentLandPrice(uint landId) public view returns (uint) {
    uint cityBlockId = cityBlockIdByLandId(landId);
    uint basePrice = _basePrices[cityBlockId];
    if (basePrice == 0) {
      return _landBasePrice;
    }
    return basePrice;
  }

  function registerCitizen(
    bytes32 name,
    uint occupation,
    uint avatarItemId,
    uint fee) public {

    // 1. Get the fee and validate the amountIn
    require(fee >= _citizenRegistrationFee, 'metacity: fee not enough');

    // 2. If avatarItemId > 0, check the owner of this avatar
    if (avatarItemId > 0) {
      require(_item.ownerOf(avatarItemId) == msg.sender, 'metacity: not avatar owner');
    }
    
    // 3. Transfer fee to platform
    _paymentToken.transferFrom(msg.sender, address(this), _citizenRegistrationFee);

    // 4. Register the citizen
    if (avatarItemId > 0) {
      // - If given the new avatar, then update the avatar content url to the content url of new avatar
      IMetaItem.Item memory itemInfo = _item.itemInfo(avatarItemId);
      _citizens[msg.sender] = Citizen({
        name: name,
        occupation: occupation,
        avatarItemId: itemInfo.itemId,
        avatarContentUrl: itemInfo.itemContentUrl
      });
    } else {
      // - If not given the new avatar, use the current avatar content url
      Citizen memory curCitizen = _citizens[msg.sender];
      _citizens[msg.sender] = Citizen({
        name: name,
        occupation: occupation,
        avatarItemId: curCitizen.avatarItemId,
        avatarContentUrl: curCitizen.avatarContentUrl
      });
    }

    // 5. Emit events, not sending the avatar content url because log string is not possible to use it outside
    emit CitizenRegistered(msg.sender, name, occupation);
  }

  function setupBusiness(
    uint landId,
    bytes32 businessName,
    uint businessType,
    uint buildingItemId,
    uint fee) public {
    
    // 1. Validate the business holder must be the owner of landId
    require(_land.ownerOf(landId) == msg.sender, 'metacity: not land owner');

    // 2. Get the fee and validate the fee
    require(fee >= _businessSetupFee, 'metacity: fee not enough');

    // 3. If buildingItemId > 0, check the owner of this building
    if (buildingItemId > 0) {
      require(_item.ownerOf(buildingItemId) == msg.sender, 'metacity: not building owner');
    }
    
    // 4. Transfer fee to platform
    _paymentToken.transferFrom(msg.sender, address(this), _businessSetupFee);

    // 5. Setup a new business
    if (buildingItemId > 0) {
      // - If given the new building, then update the building content url to the content url of new building
      IMetaItem.Item memory itemInfo = _item.itemInfo(buildingItemId);
      _businesses[landId] = BusinessUnit({
        businessName: businessName,
        businessType: businessType,
        buildingItemId: itemInfo.itemId,
        buildingContentUrl: itemInfo.itemContentUrl
      });
    } else {
      // - If not given the new building, use the current building content url
      BusinessUnit memory curBusiness = _businesses[landId];
      _businesses[landId] = BusinessUnit({
        businessName: businessName,
        businessType: businessType,
        buildingItemId: curBusiness.buildingItemId,
        buildingContentUrl: curBusiness.buildingContentUrl
      });
    }

    // 6. Emit events
    emit MetaLandUpdated(landId, msg.sender, msg.sender, businessName, businessType);
  }

  function citizenInfo(address citizenAddr) public view returns (Citizen memory) {
    return _citizens[citizenAddr];
  }

  function landInfo(uint landId) public view returns (LandInfo memory) {

    bool landExists = _land.exists(landId);

    // Get the owner of given landId if landId is exists
    address landOwner = address(0);
    if (landExists) {
      landOwner = _land.ownerOf(landId);
    }

    // Get the business unit
    BusinessUnit memory businessUnit = _businesses[landId];
    // Get the current sell order
    SellOrder memory curSellOrder = _primarySellOrders[_landSellOrders[landId]];
    // Get the current buy order
    BuyOrder memory curBuyOrder = _primaryBuyOrders[_landBuyOrders[landId]];
    // Get basePrice of landId
    uint cityBlockId = cityBlockIdByLandId(landId);
    uint currentPrice = _basePrices[cityBlockId];
    if (currentPrice <= 0) {
      currentPrice = _landBasePrice;
    }

    // Return LandInfo
    LandInfo memory info = LandInfo({
      landOwner: landOwner,
      businessName: businessUnit.businessName,
      businessType: businessUnit.businessType,
      buildingItemId: businessUnit.buildingItemId,
      buildingContentUrl: businessUnit.buildingContentUrl,
      sellOrderAutonumber: curSellOrder.autonumber,
      sellPrice: curSellOrder.price,
      sellEnded: curSellOrder.endedBlock,
      sellerAddr: curSellOrder.sellerAddr,
      buyOrderAutonumber: curBuyOrder.autonumber,
      buyPrice: curBuyOrder.price,
      buyEnded: curBuyOrder.endedBlock,
      buyerAddr: curBuyOrder.buyerAddr,
      newBusinessName: curBuyOrder.businessName,
      newBusinessType: curBuyOrder.businessType,
      currentPrice: currentPrice
    });

    return info;
  }

  function setPaymentToken(address paymentTokenAddr) public onlyOwner {
    _paymentToken = IERC20(paymentTokenAddr);
  }

  function setMetaLand(address metaLandAddr) public onlyOwner {
    _land = IMetaLand(metaLandAddr);
  }

  function setMetaItem(address metaItemAddr) public onlyOwner {
    _item = IMetaItem(metaItemAddr);
  }
  
  function getLatestBuyOrderAutonumber() public view returns (uint) {
    return _buyOrderAutonumber.value;
  }

  function getBuyOrderByAutonumber(uint autonumber) public view returns (BuyOrder memory) {
    return _primaryBuyOrders[autonumber];
  }

  function getBuyOrderByLandId(uint landId) public view returns (BuyOrder memory) {
    return _primaryBuyOrders[_landBuyOrders[landId]];
  }

  function getLatestSellOrderAutonumber() public view returns (uint) {
    return _sellOrderAutonumber.value;
  }

  function getSellOrderByAutonumber(uint autonumber) public view returns (SellOrder memory) {
    return _primarySellOrders[autonumber];
  }

  function getSellOrderByLandId(uint landId) public view returns (SellOrder memory) {
    return _primarySellOrders[_landSellOrders[landId]];
  }

  function getBusinessByLandId(uint landId)  public view returns (BusinessUnit memory) {
    return _businesses[landId];
  }

  function setDelayBuyOrderBlocks(uint delayBuyOrderBlocks) public onlyOwner {
    _delayBuyOrderBlocks = delayBuyOrderBlocks;
  }

  function setExchangeRate(uint exchangeRate) public onlyOwner {
    _exchangeRate = exchangeRate;
  }

  function setBusinessSetupFee(uint businessSetupFee) public onlyOwner {
    _businessSetupFee = businessSetupFee;
  }

  function ownerWithdraw(uint amountOut) public onlyOwner {
    _paymentToken.transfer(owner(), amountOut);
  }
}
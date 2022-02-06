// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IMetaTweet.sol';
import './IMetaItem.sol';
import './IMetaLand.sol';
import './IMetaCity.sol';
import './IMetaMarket.sol';

contract MetaTweet is IMetaTweet, Ownable, ERC721Pausable{

  uint private _tweetFee; // 1 * 10^18
  uint private _maxMessageLen; // 1000
  uint private _maxListItems; // 10

  // map[from_address] => map[my_autonumber] => TweetItem.autonumber
  mapping(address => mapping(uint => uint)) _myTweetItems;
  // map[to_address] => map[to_autonumber] => TweetItem.autonumber
  mapping(address => mapping(uint => uint)) _dmTweetItems;
  // map[global_autonumber] => TweetItem
  mapping(uint => TweetItem) _tweetItems;
  // map[from_address] => my_tweets_autonumber
  mapping(address => uint) _myTweetsAutonumber;
  // map[to_address] => tweet_to_autonumber
  mapping(address => uint) _dmAutonumber;
  // current glogal autonumber
  Counter private _tweetsAutonumber;

  IERC20 private _paymentToken;
  IMetaItem private _item;
  IMetaLand private _land;
  IMetaCity private _city;
  IMetaMarket private _market;

  constructor(
    address paymentTokenAddr,
    address itemAddr,
    address landAddr,
    address cityAddr,
    address marketAddr,
    uint initTweetFee,
    uint initMaxMessageLen,
    uint initMaxListItems) ERC721('MetaTweet', 'MetaTweet') {
    
    require(paymentTokenAddr != address(0), 'metatweet: invalid payment token addr');
    require(itemAddr != address(0), 'metatweet: invalid item addr');
    require(landAddr != address(0), 'metatweet: invalid land addr');
    require(cityAddr != address(0), 'metatweet: invalid city addr');
    require(marketAddr != address(0), 'metatweet: invalid market addr');
    require(initMaxListItems > 0 && initMaxListItems <= 10, 'metatweet: invalid max list items');
    require(initMaxMessageLen > 0, 'metatweet: invalid max message len');

    _paymentToken = IERC20(paymentTokenAddr);
    _item = IMetaItem(itemAddr);
    _land = IMetaLand(landAddr);
    _city = IMetaCity(cityAddr);
    _market = IMetaMarket(marketAddr);
    _tweetFee = initTweetFee;
    _maxMessageLen = initMaxMessageLen;
    _maxListItems = initMaxListItems;
  }

  function postTweet(
    string memory message, 
    uint itemId, 
    uint landId, 
    uint sellId,
    address tweetTo, 
    uint fee) public whenNotPaused {

    // 1. Validate message length
    require(bytes(message).length <= _maxMessageLen, 'metatweet: message too long');

    // 2. Validate fee
    require(fee >= _tweetFee, 'metatweet: fee not enough');

    // 3. Transfer fee to platform
    _paymentToken.transferFrom(msg.sender, address(this), _tweetFee);

    // 6. Post tweet
    //    - Post to my own timeline
    //    - Post to global timeline
    //    - Post to tweet dm timeline (if tweetTo > 0)
    Counter storage tweetAutonumber = _tweetsAutonumber;
    tweetAutonumber.value += 1;
    uint autonumber = tweetAutonumber.value;
    
    uint myAutonumber = _myTweetsAutonumber[msg.sender];
    myAutonumber += 1;
    _myTweetsAutonumber[msg.sender] = myAutonumber;

    // 7. Get citizen name and avatar url, if already register
    IMetaCity.Citizen memory citizen = _city.citizenInfo(msg.sender);
    
    // 8. Get business info if attach landId with the tweet
    IMetaCity.BusinessUnit memory business;
    if (landId > 0) {
      business = _city.getBusinessByLandId(landId);
    }
    // 9. Get item info if attach itemId with the tweet
    IMetaItem.Item memory item;
    if (itemId > 0) {
      item = _item.itemInfo(itemId);
    }
    // 10. Get market item info if attach sell autonumber with the tweet
    IMetaMarket.MarketItem memory marketItem;
    if (sellId > 0) {
      marketItem = _market.getItem(landId, sellId);
    }

    // Mint NFT for tweet message
    _mint(msg.sender, autonumber);

    _tweetItems[autonumber] = TweetItem({
      message: message,
      autonumber: autonumber,
      tweetFrom: msg.sender,
      tweetTo: tweetTo,
      itemId: itemId,
      landId: landId,
      citizenName: citizen.name,
      avatarContentUrl: citizen.avatarContentUrl,
      businessName: business.businessName,
      businessType: business.businessType,
      buildingContentUrl: business.buildingContentUrl,
      itemName: item.itemName,
      itemContentUrl: item.itemContentUrl,
      sellId: sellId,
      sellItemName: marketItem.itemName,
      sellContentUrl: marketItem.itemContentUrl,
      createdAtBlock: block.number
    });

    _myTweetItems[msg.sender][myAutonumber] = autonumber;

    if (tweetTo != address(0)) {
      uint tweetToAutonumber = _dmAutonumber[tweetTo];
      tweetToAutonumber += 1;
      _dmAutonumber[tweetTo] = tweetToAutonumber;
      _dmTweetItems[tweetTo][tweetToAutonumber] = autonumber;
    }
  }

  function reTweet(uint autonumber, uint fee) public whenNotPaused {
    
    // 1. Validate fee
    require(fee >= _tweetFee, 'metatweet: fee not enough');

    // 2. Autonumber must valid
    require(autonumber > 0 && autonumber <= _tweetsAutonumber.value, 'metatweet: autonumber invalid');

    // 3. Transfer fee to platform
    _paymentToken.transferFrom(msg.sender, address(this), _tweetFee);

    // 4. Copy tweet to global and my timeline
    //    - Copy to my own timeline
    //    - Copy to global timeline
    Counter storage tweetAutonumber = _tweetsAutonumber;
    tweetAutonumber.value += 1;
    uint nextAutonumber = tweetAutonumber.value;

    // Mint NFT for retweet message
    _mint(msg.sender, nextAutonumber);
    
    uint myAutonumber = _myTweetsAutonumber[msg.sender];
    myAutonumber += 1;
    _myTweetsAutonumber[msg.sender] = myAutonumber;

    // Copy tweet and update tweet.autonumber and tweet.createdAtBlock
    TweetItem memory item = _tweetItems[autonumber];
    item.autonumber = nextAutonumber;
    item.createdAtBlock = block.number;

    _tweetItems[nextAutonumber] = item;
    _myTweetItems[msg.sender][myAutonumber] = nextAutonumber;
  }

  function listTweets(uint fromAutonumber) public view returns (TweetItem[10] memory) {
    TweetItem[10] memory items;

    uint currentAutonumber = _tweetsAutonumber.value;
    if (fromAutonumber == 0) {
      fromAutonumber = currentAutonumber;
    }

    if (fromAutonumber > currentAutonumber) {
      return items;
    }

    uint toAutonumber = 0;
    if (_maxListItems < fromAutonumber) {
      toAutonumber = fromAutonumber - _maxListItems;
    }

    uint i = 0;
    for (uint autonumber=fromAutonumber; autonumber>toAutonumber; autonumber--) {
      if (autonumber <= 0) {
        break;
      }
      TweetItem memory item = _tweetItems[autonumber];
      items[i] = item;
      i++;
    }
    return items;
  }

  function listMyTweets(address userAddr, uint fromAutonumber) public view returns (TweetItem[10] memory) {
    TweetItem[10] memory items;

    uint currentAutonumber = _myTweetsAutonumber[userAddr];
    if (fromAutonumber == 0) {
      fromAutonumber = currentAutonumber;
    }

    if (fromAutonumber > currentAutonumber) {
      return items;
    }

    uint toAutonumber = 0;
    if (_maxListItems < fromAutonumber) {
      toAutonumber = fromAutonumber - _maxListItems;
    }

    uint i = 0;
    for (uint autonumber=fromAutonumber; autonumber>toAutonumber; autonumber--) {
      if (autonumber <= 0) {
        break;
      }

      uint globalAutonumber =  _myTweetItems[userAddr][autonumber];
      TweetItem memory item = _tweetItems[globalAutonumber];
      items[i] = item;
      i++;
    }
    return items;
  }

  function listDMTweets(address userAddr, uint fromAutonumber) public view returns (TweetItem[10] memory) {
    TweetItem[10] memory items;

    uint currentAutonumber = _dmAutonumber[userAddr];
    if (fromAutonumber == 0) {
      fromAutonumber = currentAutonumber;
    }

    if (fromAutonumber > currentAutonumber) {
      return items;
    }

    uint toAutonumber = 0;
    if (_maxListItems < fromAutonumber) {
      toAutonumber = fromAutonumber - _maxListItems;
    }

    uint i = 0;
    for (uint autonumber=fromAutonumber; autonumber>toAutonumber; autonumber--) {
      if (autonumber <= 0) {
        break;
      }

      uint globalAutonumber = _dmTweetItems[userAddr][autonumber];
      TweetItem memory item = _tweetItems[globalAutonumber];
      items[i] = item;
      i++;
    }
    return items;
  }

  function getTweet(uint autonumber) public view returns (TweetItem memory) {
    TweetItem memory item = _tweetItems[autonumber];
    return item;
  }

  function lastTweetAutonumber() public view returns (uint) {
    return _tweetsAutonumber.value;
  }

  function lastMyTweetAutonumber(address userAddr) public view returns (uint) {
    return _myTweetsAutonumber[userAddr];
  }

  function lastDMTweetAutonumber(address userAddr) public view returns (uint) {
    return _dmAutonumber[userAddr];
  }

  function pauseTweet() public onlyOwner {
    _pause();
  }

  function resumeTweet() public onlyOwner {
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

  function setMetaMarket(address metaMarketAddr) public onlyOwner {
    _market = IMetaMarket(metaMarketAddr);
  }

  function setTweetFee(uint tweetFee) public onlyOwner {
    _tweetFee = tweetFee;
  }

  function setMaxMessageLen(uint maxMessageLen) public onlyOwner {
    require(maxMessageLen > 0, 'metatweet: invalid max message len');
    _maxMessageLen = maxMessageLen;
  }

  function setMaxListItems(uint maxListItems) public onlyOwner {
    require(maxListItems > 0 && maxListItems <= 10, 'metatweet: invalid max list items');
    _maxListItems = maxListItems;
  }

  function ownerWithdraw(uint amountOut) public onlyOwner {
    _paymentToken.transfer(owner(), amountOut);
  }
}
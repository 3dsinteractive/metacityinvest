// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IBase.sol';

interface IMetaMarket is IBase {

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct MarketItem {
    uint landId;
    uint autonumber;
    string itemContentUrl;
    bytes32 itemName;
    uint itemType;
    uint initialPrice;
    uint currentPrice;
    uint priceIncrementalRate;
    uint priceIncrementEveryNItems;
    uint totalItems;
    uint lastIncrementCount;
    uint soldItems;
    bool isPaused;
  }

  function postItemForSell(
    uint landId,
    bytes32 itemName,
    uint itemType,
    uint initialPrice,
    uint priceIncrementalRate,
    uint priceIncrementEveryNItems,
    uint totalItems,
    string memory itemContentUrl) external;
  function currentItemAutonumber(uint landId) external returns (uint);
  function pauseSell(uint landId, uint autonumber, bool isPaused) external;
  function currentPrice(uint landId, uint autonumber) external returns (uint);
  function listItems(uint landId, uint fromAutonumber) external returns (MarketItem[10] memory);
  function getItem(uint landId, uint autonumber) external returns (MarketItem memory);
  function exists(uint landId, uint autonumber) external returns (bool);

  function buyItem(
    uint landId, 
    uint autonumber,
    uint buyPrice) external;

  function pauseMarket() external;
  function resumeMarket() external;
}
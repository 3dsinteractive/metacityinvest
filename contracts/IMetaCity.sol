// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IBase.sol';

interface IMetaCity is IBase {

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct Citizen {
    bytes32 name;
    uint occupation;
    uint avatarItemId;
    string avatarContentUrl;
  }
  
  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct BusinessUnit {
    bytes32 businessName;
    uint businessType;
    uint buildingItemId;
    string buildingContentUrl;
  }

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct SellOrder {
    uint landId;
    uint autonumber;
    uint price;
    uint endedBlock;
    address sellerAddr;
    bool completed;
    bool deleted;
    uint createdAt;
  }

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct BuyOrder {
    uint landId;
    uint autonumber;
    uint price;
    uint endedBlock;
    address buyerAddr;
    bytes32 businessName;
    uint businessType;
    bool completed;
    bool deleted;
    bool overrided;
    uint createdAt;
  }

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct LandInfo {
    address landOwner;
    bytes32 businessName;
    uint businessType;
    uint buildingItemId;
    string buildingContentUrl;
    uint sellOrderAutonumber;
    uint sellPrice;
    uint sellEnded;
    address sellerAddr;
    uint buyOrderAutonumber;
    uint buyPrice;
    uint buyEnded;
    address buyerAddr;
    bytes32 newBusinessName;
    uint newBusinessType;
    uint currentPrice;
  }

  function mintEmptyLand(
    uint landId, 
    uint buyPrice,
    bytes32 businessName,
    uint businessType) external;

  function createSellOrder(
    uint landId,
    uint sellPrice,
    uint endedBlock) external;
  
  function deleteSellOrder(uint landId) external;

  function createBuyOrder(
    uint landId,
    uint buyPrice,
    uint endedBlock,
    bytes32 businessName,
    uint businessType) external;

  function deleteBuyOrder(uint landId) external;

  function currentLandPrice(uint landId) external view returns (uint);

  function acceptBuyOrder(
    uint landId,
    uint autonumber,
    uint sellPrice) external;

  function registerCitizen(
    bytes32 name,
    uint occupation,
    uint avatarItemId,
    uint fee) external;

  function setupBusiness(
    uint landId,
    bytes32 businessName,
    uint businessType,
    uint buildingItemId,
    uint fee) external;

  function citizenInfo(address citizenAddr) external view returns (Citizen memory);

  function landInfo(uint landId) external view returns (LandInfo memory);

  function getLatestBuyOrderAutonumber() external view returns (uint);

  function getBuyOrderByAutonumber(uint autonumber) external view returns (BuyOrder memory);

  function getBuyOrderByLandId(uint landId) external view returns (BuyOrder memory);

  function getLatestSellOrderAutonumber() external view returns (uint);

  function getSellOrderByAutonumber(uint autonumber) external view returns (SellOrder memory);

  function getSellOrderByLandId(uint landId) external view returns (SellOrder memory);

  function getBusinessByLandId(uint landId)  external view returns (BusinessUnit memory);
}
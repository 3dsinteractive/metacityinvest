// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IBase.sol';

interface ISecondaryMarket is IBase {

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct BuyOrder {
    uint creatorBusinessId;
    bytes32 itemName;
    uint itemType;
    string itemContentUrl;
    uint autonumber;
    uint price;
    uint endedBlock;
    address buyerAddr;
    uint createdAt;
  }

  function createBuyOrder(
    uint creatorBusinessId,
    bytes32 itemName,
    uint itemType,
    string memory itemContentUrl,
    uint buyPrice,
    uint endedBlock) external;

  function acceptBuyOrder(
    uint itemId,
    uint buyOrderAutonumber,
    uint sellPrice) external;

  function deleteBuyOrder( 
    uint creatorBusinessId,
    string memory itemContentUrl) external;
}
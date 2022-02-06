// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import './IBase.sol';

interface IMetaItem is IBase, IERC721, IERC721Metadata {

  struct Item {
    uint itemId;
    string itemContentUrl;
    bytes32 itemName;
    uint itemType;
    uint creatorBusinessId;
    bytes32 creatorBusinessName;
    uint createdAt;
  }

  function mintFor(
    address receiver,
    bytes32 itemName,
    uint itemType,
    string memory itemContentUrl,
    uint creatorBusinessId,
    bytes32 creatorBusinessName) external returns (uint); // return itemId

  function itemInfo(uint itemId) external view returns (Item memory);
}
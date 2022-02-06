// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './IMetaItem.sol';

contract MetaItem is IMetaItem, Ownable, ERC721Pausable {

  // address that can mint the item
  mapping(address => bool) private _minters;

  // mapping of itemId => item
  mapping(uint => Item) private _items;
  Counter private _itemCounter;

  modifier onlyMinter() {
    require(_minters[msg.sender] == true, 'metaitem: only minter');
    _;
  }

  constructor() ERC721('MetaItem', 'MetaItem') {
  }

  function mintFor(
    address receiver,
    bytes32 itemName,
    uint itemType,
    string memory itemContentUrl,
    uint creatorBusinessId,
    bytes32 creatorBusinessName) public onlyMinter returns (uint) { // return itemId

    Counter storage counter = _itemCounter;
    counter.value += 1;
    uint itemId = counter.value;
    _mint(receiver, itemId);

    Item memory item = Item({
      itemId: itemId,
      itemContentUrl: itemContentUrl,
      itemName: itemName,
      itemType: itemType,
      creatorBusinessId: creatorBusinessId,
      creatorBusinessName: creatorBusinessName,
      createdAt: block.number
    });
    
    _items[itemId] = item;

    return itemId;
  }

  function itemInfo(uint itemId) public view returns (Item memory) {
    return _items[itemId];
  }

  function addMinter(address minterAddr, bool canMint) public onlyOwner {
    _minters[minterAddr] = canMint;
  }
}
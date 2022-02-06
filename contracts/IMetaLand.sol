// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';

interface IMetaLand is IERC721 {
  function exists(uint landId) external view returns (bool);
  function mint(address receiver, uint landId) external;
}
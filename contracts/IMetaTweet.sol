// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IBase.sol';

interface IMetaTweet is IBase {

  // DO NOT change the order of attributes, because javascript will confused
  // if you want to add more attributes, add it to the end of list
  struct TweetItem {
    uint autonumber;
    string message;
    address tweetFrom;
    address tweetTo;
    uint itemId;
    uint landId;
    bytes32 citizenName;
    string avatarContentUrl;
    bytes32 businessName;
    uint businessType;
    string buildingContentUrl;
    bytes32 itemName;
    string itemContentUrl;
    uint sellId;
    bytes32 sellItemName;
    string sellContentUrl;
    uint createdAtBlock;
  }

  function postTweet(string memory message, uint itemId, uint landId, uint sellId, address tweetTo, uint fee) external;
  function reTweet(uint autonumber, uint fee) external;

  function listTweets(uint fromAutonumber) external returns (TweetItem[10] memory);
  function listMyTweets(address userAddr, uint fromAutonumber) external returns (TweetItem[10] memory);
  function listDMTweets(address userAddr, uint fromAutonumber) external returns (TweetItem[10] memory);
  function getTweet(uint autonumber) external returns (TweetItem memory);

  function lastTweetAutonumber() external view returns (uint);
  function lastMyTweetAutonumber(address userAddr) external view returns (uint);
  function lastDMTweetAutonumber(address userAddr) external view returns (uint);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IMetaLand.sol';

contract MetaLand is IMetaLand, Ownable, ERC721Pausable{
  
  mapping(address => bool) private _minters;
  mapping(uint => uint) private _cities;

  constructor() ERC721('MetaLand', 'MetaLand') {
    // "100": Thailand,    // cityId = 000 - 076
		// "101": Vietnam,     // cityId = 000 - 078
		// "102": India,       // cityId = 000 - 432
		// "103": Pakistan,    // cityId = 000 - 108
		// "104": Ukraine,     // cityId = 000 - 503
		// "105": Kenya,       // cityId = 000 - 062
		// "106": Nigeria,     // cityId = 000 - 077
		// "107": Venezuela,   // cityId = 000 - 092
		// "108": USA,         // cityId = 000 - 999
		// "109": Argentina,   // cityId = 000 - 308
		// "110": Colombia,    // cityId = 000 - 458
		// "111": China,       // cityId = 000 - 999
		// "112": Brazil,      // cityId = 000 - 999
		// "113": Philippines, // cityId = 000 - 199
		// "114": SouthAfrica, // cityId = 000 - 104
		// "115": Ghana,       // cityId = 000 - 024
		// "116": Russia,      // cityId = 000 - 999
		// "117": Tanzania,    // cityId = 000 - 063
		// "118": Afghanistan, // cityId = 000 - 044
		// "119": Singapore,   // cityId = 000 - 000
		// "120": Togo,        // cityId = 000 - 008
    _cities[100] = 76;
    _cities[101] = 78;
    _cities[102] = 432;
    _cities[103] = 108;
    _cities[104] = 503;
    _cities[105] = 62;
    _cities[106] = 77;
    _cities[107] = 92;
    _cities[108] = 999;
    _cities[109] = 308;
    _cities[110] = 458;
    _cities[111] = 999;
    _cities[112] = 999;
    _cities[113] = 199;
    _cities[114] = 104;
    _cities[115] = 24;
    _cities[116] = 999;
    _cities[117] = 63;
    _cities[118] = 44;
    _cities[119] = 0;
    _cities[120] = 8;
  }

  function mint(address receiver, uint landId) public {
    // 1. Must be minter to mint a land
    require(_minters[msg.sender] == true, 'metaland: minter only');

    // 2. If valid land and no owner yet, we can mint
    require(!_exists(landId), 'metaland: landId already minted');

    // 3. Validate land Id (country (100-120) / city (000 - _cities[countryId]) / block (000-015) / cell (000-224))
    // landId format = KKKCCCBBBPPP
    // - KKK = countryId
    // - CCC = cityId
    // - BBB = block
    // - PPP = cell in block
    uint countryId = landId / 1000000000; // Remove cityId, blockId and cellId
    require(countryId >= 100 && countryId <= 120, 'metaland: invalid countryId');

    uint cityId = landId / 1000000 % (countryId * 1000); // Remove countryId, blockId and cellId KKK[CCC]BBBPPP
    require(cityId <= _cities[countryId], 'metaland: invalid cityId');

    uint blockId =  landId / 1000 % ((countryId * 1000000) + (cityId * 1000)); // Remove countryId, cityId and cellId KKKCCC[BBB]PPP
    require(blockId <= 15, 'metaland: invalid blockId');

    uint cellId = landId % ((countryId * 1000000000) + (cityId * 1000000) + (blockId * 1000)); // Remove countryId, cityId and blockId KKKCCCBBB[PPP]
    require(cellId <= 224, 'metaland: invalid cellId');

    // 4. Validate the land must not locate at the road position
    // 030-044
    require(!(cellId >= 30 && cellId <=44), 'metaland: cannot mint land on road position');
    // 075-089
    require(!(cellId >= 75 && cellId <=89), 'metaland: cannot mint land on road position');
    // 120-134
    require(!(cellId >= 120 && cellId <=134), 'metaland: cannot mint land on road position');
    // 165-179
    require(!(cellId >= 165 && cellId <=179), 'metaland: cannot mint land on road position');
    // 210-224
    require(!(cellId >= 210 && cellId <=224), 'metaland: cannot mint land on road position');
    // Y % 15 = 1
    require(!(cellId % 15 == 1), 'metaland: cannot mint land on road position');
    // Y % 15 = 7
    require(!(cellId % 15 == 7), 'metaland: cannot mint land on road position');
    // Y % 15 = 13
    require(!(cellId % 15 == 13), 'metaland: cannot mint land on road position');

    // 5. Mint land to minter
    _mint(receiver, landId);
  }

  // addMinter use to set permission to mint for the specific address
  function addMinter(address minterAddr, bool canMint) public onlyOwner {
    _minters[minterAddr] = canMint;
  }

  // exists will return true if the land has already minted
  function exists(uint landId) public view returns (bool) {
    return _exists(landId);
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/TokenIdProvider.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract TestTokenIdProvider is Initializable, TokenIdProvider {
    constructor(uint256 _tokenId) initializer {
        __TokenIdProvider_init(_tokenId);
    }

    function _checkInitializing() internal view virtual override(Initializable, OzInitializable) {
        Initializable._checkInitializing();
    }

    function nextTokenId() public returns (uint256) {
        return _nextTokenId();
    }
}

contract TokenIdProviderTest is Test {
    TestTokenIdProvider private provider;
    uint256 initId;

    function setUp() public {
        initId = 1;
        provider = new TestTokenIdProvider(initId);
    }

    function testNextTokenId_init(uint256 _id) public {
        _id = bound(_id, 0, type(uint256).max - 1);
        provider = new TestTokenIdProvider(_id);
        assertEq(_id + 1, provider.nextTokenId(), "Token id updated");
    }

    function testNextTokenId_increment() public {
        for (uint256 i = 1; i <= 20; i++) {
            assertEq(initId + i, provider.nextTokenId(), "Token id updated");
        }
    }
}

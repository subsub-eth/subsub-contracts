// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IMintAllowedUpgradeable.sol";
import "../src/MintAllowedUpgradeable.sol";

contract TestMintAllowed is MintAllowedUpgradeable {
    bool private _idsExist;

    function _idExists(uint256) internal view override returns (bool) {
        return _idsExist;
    }

    function setIdsExist(bool exist) external {
        _idsExist = exist;
    }

    function requireMintAllowed(uint256 id) external view {
        _requireMintAllowed(id);
    }
}

contract MintAllowedTest is Test, IMintAllowedEvents {
    TestMintAllowed private ma;

    function setUp() public {
        ma = new TestMintAllowed();
        ma.setIdsExist(true);
    }

    function testSetMintAllowed(address minter, uint256 id, bool allow) public {
        vm.expectEmit();
        emit MintAllowed(address(this), minter, id, allow);

        ma.setMintAllowed(minter, id, allow);
        assertEq(allow, ma.isMintAllowed(minter, id), "MintAllowed not set correctly");
    }

    function testSetMintAllowed_frozen(address minter, uint256 id, bool allow) public {
        ma.freezeMintAllowed(id);

        vm.expectRevert("MintAllowed: Minter list is frozen");
        ma.setMintAllowed(minter, id, allow);
    }

    function testSetMintAllowed_notExistingId() public {
        ma.setIdsExist(false);
        vm.expectRevert("MintAllowed: token does not exist");
        ma.setMintAllowed(address(1), 1, true);
    }

    function testRequireMintAllowed(address minter, uint256 id) public {
        ma.setMintAllowed(minter, id, true);

        vm.prank(minter);
        ma.requireMintAllowed(id);
    }

    function testRequireMintAllowed_revert(address minter, uint256 id) public {
        vm.startPrank(minter);
        vm.expectRevert("MintAllowed: sender not allowed to mint");
        ma.requireMintAllowed(id);
    }

    function testFreezeMintAllowed(uint256 id) public {
        assertFalse(ma.isMintAllowedFrozen(id), "mint already frozen for id");

        vm.expectEmit();
        emit MintAllowedFrozen(address(this), id);

        ma.freezeMintAllowed(id);

        assertTrue(ma.isMintAllowedFrozen(id), "mint frozen for id is not frozen");
    }

    function testFreezeMintAllowed_notExistingId(uint256 id) public {
        ma.setIdsExist(false);

        assertFalse(ma.isMintAllowedFrozen(id), "mint already frozen for non-existing id");

        vm.expectRevert("MintAllowed: token does not exist");
        ma.freezeMintAllowed(id);
    }
}

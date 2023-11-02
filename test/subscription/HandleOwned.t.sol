// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/HandleOwned.sol";

import {ERC721Mock} from "../mocks/ERC721Mock.sol";

contract TestHandleOwned is HandleOwned {
    constructor(address handleContract) HandleOwned(handleContract) {}

    function checkOwner() public view {
        super._checkOwner();
    }

    function protected() public view onlyOwner {}
}

contract HandleOwnedTest is Test, HandleOwnedErrors {
    TestHandleOwned private ho;

    ERC721Mock private token;

    function setUp() public {
        token = new ERC721Mock("test", "test");

        ho = new TestHandleOwned(address(token));
    }

    function testOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));
        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        assertEq(o.owner(), owner, "token owner is contract owner");
    }

    function testOwner_nonExisting() public {
        TestHandleOwned o = new TestHandleOwned(address(token));

        vm.expectRevert();
        o.owner();
    }

    function testCheckOwner(address sender, address owner) public {
        vm.assume(sender != address(0) && sender != address(this));
        vm.assume(owner != address(0) && owner != address(this));
        vm.assume(owner != sender);

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedAccount.selector, sender));
        o.checkOwner();
    }

    function testCheckOwner_isOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(owner);
        o.checkOwner();
    }

    function testOnlyOwner(address sender, address owner) public {
        vm.assume(sender != address(0) && sender != address(this));
        vm.assume(owner != address(0) && owner != address(this));
        vm.assume(owner != sender);

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedAccount.selector, sender));
        o.protected();
    }

    function testOnlyOwner_isOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(owner);
        o.protected();
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OwnableByERC721Upgradeable.sol";

import {ERC721Mock} from "openzeppelin-contracts/contracts/mocks/ERC721Mock.sol";

contract MyOwnable is TransferableOwnableByERC721Upgradeable {

  // simple default implementation
  function init(address kontract, uint256 tokenId) initializer public {
    __OwnableByERC721_init(kontract, tokenId);
  }
}

contract OwnableByERC721UpgradeableTest is Test {
    event OwnershipTransferred(
        address indexed previousOwnerContract,
        uint256 indexed previousOwnerTokenId,
        address indexed newOwnerContract,
        uint256 newOwnerTokenId
    );

    ERC721Mock private nft;


    MyOwnable private myOwnable;

    function setUp() public {
      nft = new ERC721Mock("test", "test");
    }


    function testInitOwnership(uint256 tokenId) public {
      nft.mint(address(this), tokenId);

      MyOwnable mo = new MyOwnable();

      (address _contract, uint256 _id) = mo.owner();
      assertEq(_contract, address(0), "contract is set to 0");
      assertEq(_id, 0, "id not set");
      assertEq(address(0), mo.ownerAddress(), "no owner address, yet");

      vm.expectEmit(true, true, true, true);
      emit OwnershipTransferred(
            address(0),
            0,
            address(nft),
            tokenId
        );

      mo.init(address(nft), tokenId);

      (_contract, _id) = mo.owner();
      assertEq(address(nft), _contract, "owner contract set");
      assertEq(tokenId, _id, "id set");
      assertEq(address(this), mo.ownerAddress(), "owner address is this");
    }


    function testTransfer(uint256 tokenId) public {
      uint256 initId = 10;
      vm.assume(tokenId != initId);

      nft.mint(address(this), initId);
      nft.mint(address(this), tokenId);

      MyOwnable mo = new MyOwnable();
      mo.init(address(nft), initId);

      vm.expectEmit(true, true, true, true);
      emit OwnershipTransferred(
            address(nft),
            initId,
            address(nft),
            tokenId
        );
      mo.transferOwnership(address(nft), tokenId);

      (address _contract, uint256 _id) = mo.owner();
      assertEq(_contract, address(nft), "contract is set to nft");
      assertEq(_id, tokenId, "id set to tokenId");
      assertEq(address(this), mo.ownerAddress(), "owner address set");
    }

    function testTransfer_notOwner(uint256 tokenId, address otherUser) public {
      uint256 initId = 10;
      vm.assume(tokenId != initId && otherUser != address(this));

      nft.mint(address(this), initId);
      nft.mint(address(this), tokenId);

      MyOwnable mo = new MyOwnable();
      mo.init(address(nft), initId);

      vm.expectRevert("Ownable: caller is not the owner");
      vm.prank(otherUser);
      mo.transferOwnership(address(nft), tokenId);
    }

    function testTransfer_notZeroArress() public {
      uint256 initId = 10;

      nft.mint(address(this), initId);

      MyOwnable mo = new MyOwnable();
      mo.init(address(nft), initId);

      vm.expectRevert("Ownable: new owner contract is the zero address");
      mo.transferOwnership(address(0), 1);
    }

    function testRenounceOwnership() public {
      uint256 initId = 10;

      nft.mint(address(this), initId);

      MyOwnable mo = new MyOwnable();
      mo.init(address(nft), initId);

      vm.expectEmit(true, true, true, true);
      emit OwnershipTransferred(
            address(nft),
            initId,
            address(0),
            0
        );
      mo.renounceOwnership();

      (address _contract, uint256 _id) = mo.owner();
      assertEq(_contract, address(0), "contract is set to 0");
      assertEq(_id, 0, "id set to 0");
      assertEq(address(0), mo.ownerAddress(), "owner address is 0");
    }

    function testRenounceOwnership_onlyOwner() public {
      uint256 initId = 10;
      address otherUser = address(10023);

      nft.mint(address(this), initId);

      MyOwnable mo = new MyOwnable();
      mo.init(address(nft), initId);

      vm.expectRevert("Ownable: caller is not the owner");
      vm.prank(otherUser);
      mo.renounceOwnership();
    }
}

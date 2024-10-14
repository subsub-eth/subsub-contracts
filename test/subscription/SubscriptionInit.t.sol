// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/TimestampSubscription.sol";

import {MetadataStruct, SubSettings} from "../../src/subscription/ISubscription.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import {ERC721Mock} from "../mocks/ERC721Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SubscriptionInitTest is Test {
    // uses TimestampSubscription as a concrete example to test init

    TimestampSubscription public sub;
    TimestampSubscription public impl;
    ERC721Mock public handleContract;

    address public owner;

    ERC20DecimalsMock public testToken;

    string public name;
    string public symbol;
    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint64 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        owner = address(10);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        handleContract = new ERC721Mock("handle", "HANDLE");

        settings = SubSettings(address(testToken), rate, lock, epochSize, maxSupply);

        createSub();
        sub.initialize(name, symbol, metadata, settings);
    }

    function createSub() public {
        impl = new TimestampSubscription(address(handleContract));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        sub = TimestampSubscription(address(proxy));

        handleContract.mint(owner, uint256(uint160(address(sub))));
    }

    function testConstruct_initializerDisabledOnImpl() public {
        vm.expectRevert();
        impl.initialize("name", "symbol", metadata, settings);
    }

    function testInit() public view {
        assertEq(sub.name(), name, "name");
        assertEq(sub.symbol(), symbol, "symbol");
        assertEq(sub.symbol(), symbol, "symbol");

        {
            (address _token, uint256 _rate, uint24 _lock, uint256 _epochSize, uint256 _maxSupply) = sub.settings();

            assertEq(_token, address(testToken), "token");
            assertEq(_rate, rate, "rate");
            assertEq(_lock, lock, "lock");
            assertEq(_epochSize, epochSize, "epochSize");
            assertEq(_maxSupply, maxSupply, "maxSupply");
        }
        {
            (string memory _description, string memory _image, string memory _externalUrl) = sub.metadata();

            assertEq(_description, metadata.description, "description");
            assertEq(_image, metadata.image, "image");
            assertEq(_externalUrl, metadata.externalUrl, "externalUrl");
        }
        {
            (address _token, uint256 _rate, uint24 _lock, uint256 _epochSize, uint256 _maxSupply) = sub.settings();

            assertEq(_token, address(testToken), "token");
            assertEq(_rate, rate, "rate");
            assertEq(_lock, lock, "lock");
            assertEq(_epochSize, epochSize, "epochSize");
            assertEq(_maxSupply, maxSupply, "maxSupply");
        }
    }

    function testConstruct_not0rate() public {
        settings.rate = 0;

        createSub();

        vm.expectRevert("SUB: rate cannot be 0");
        sub.initialize(name, symbol, metadata, settings);
    }

    function testConstruct_not0epochSize() public {
        settings.epochSize = 0;

        createSub();

        vm.expectRevert("SUB: invalid epochSize");
        sub.initialize(name, symbol, metadata, settings);
    }

    function testConstruct_lockTooLarge() public {
        settings.lock = 10_001;

        createSub();

        vm.expectRevert("SUB: lock percentage out of range");
        sub.initialize(name, symbol, metadata, settings);
    }
}

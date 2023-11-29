// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/handle/ContractRegistry.sol";

contract TestContractRegistry is ContractRegistry {
    function addToRegistry(address addr, bool _isManaged) external returns (bool set) {
        return _addToRegistry(addr, _isManaged);
    }

    function isManaged(address addr) external view returns (bool) {
        return _isManaged(addr);
    }

    function isRegistered(address addr) external view returns (bool) {
        return _isRegistered(addr);
    }
}

contract ContractRegistryTest is Test {
    TestContractRegistry private registry;

    function setUp() public {
        registry = new TestContractRegistry();
    }

    function testAddToRegistry(address addr, bool isManaged) public {
        assertTrue(registry.addToRegistry(addr, isManaged), "successully added");
        assertTrue(registry.isRegistered(addr), "is registered");
        assertEq(registry.isManaged(addr), isManaged, "managed value set");

        assertFalse(registry.addToRegistry(addr, isManaged), "was already added");
        assertTrue(registry.isRegistered(addr), "is registered");
        assertEq(registry.isManaged(addr), isManaged, "managed value unchanged");

        assertFalse(registry.addToRegistry(addr, isManaged), "still false");
        assertTrue(registry.isRegistered(addr), "is registered");
        assertEq(registry.isManaged(addr), isManaged, "managed value still unchanged");
    }

    function testIsManaged(address addr, bool isManaged) public {
        registry.addToRegistry(addr, isManaged);

        assertEq(registry.isManaged(addr), isManaged, "contract management state set");
    }

    function testIsManaged_notRegistered(address addr) public {
        vm.expectRevert();
        registry.isManaged(addr);
    }

    function testIsRegistered(address addr, bool isManaged) public {
        assertFalse(registry.isRegistered(addr), "unregistered contract is never registered");
        registry.addToRegistry(addr, isManaged);

        assertTrue(registry.isRegistered(addr), "contract set");
    }
}

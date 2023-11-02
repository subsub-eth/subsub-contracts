// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/subscription/handle/ContractRegistry.sol";

contract TestContractRegistry is ContractRegistry {

  function addToRegistry(address addr, bool _isManaged) external returns (bool set) {
    return _addToRegistry(addr, _isManaged);
  }

  function isManaged(address addr) external view returns (bool) {
    return _isManaged(addr);
  }
}

contract ContractRegistryTest is Test {
    TestContractRegistry private registry;


    function setUp() public {
        registry = new TestContractRegistry();
    }

    function testAddToRegistry(address addr, bool isManaged) public {
      assertTrue(registry.addToRegistry(addr, isManaged), "successully added");
      assertEq(registry.isManaged(addr), isManaged, "managed value set");

      assertFalse(registry.addToRegistry(addr, isManaged), "was already added");
      assertEq(registry.isManaged(addr), isManaged, "managed value unchanged");

      assertFalse(registry.addToRegistry(addr, isManaged), "still false");
      assertEq(registry.isManaged(addr), isManaged, "managed value still unchanged");
    }

    function testIsManaged(address addr, bool isManaged) public {
      assertFalse(registry.isManaged(addr), "unregistered contract is never managed");
      registry.addToRegistry(addr, isManaged);

      assertEq(registry.isManaged(addr), isManaged, "contract management state set");
    }

}

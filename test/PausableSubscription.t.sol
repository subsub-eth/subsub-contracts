// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/subscription/PausableSubscription.sol";

contract PS is PausableSubscription {

  function init() public initializer {
    __PausableSubscription_init();
  }

  function pauseMinting() public {
    _pauseMinting();
  }

  function unpauseMinting() public {
    _unpauseMinting();
  }

  function pauseRenewal() public {
    _pauseRenewal();
  }

  function unpauseRenewal() public {
    _unpauseRenewal();
  }

  function pauseTipping() public {
    _pauseTipping();
  }

  function unpauseTipping() public {
    _unpauseTipping();
  }

}

contract PausableSubscriptionTest is Test {

  PS private ps;

    function setUp() public {
      ps = new PS();

      ps.init();
    }

    function testMintingPaused() public {
      assertFalse(ps.mintingPaused());
    }

    function testPauseMint() public {
      assertFalse(ps.mintingPaused());
      ps.pauseMinting();
      assertTrue(ps.mintingPaused());
      ps.unpauseMinting();
      assertFalse(ps.mintingPaused());
    }

    function testPauseRenewal() public {
      assertFalse(ps.renewalPaused());
      ps.pauseRenewal();
      assertTrue(ps.renewalPaused());
      ps.unpauseRenewal();
      assertFalse(ps.renewalPaused());
    }

    function testPauseTipping() public {
      assertFalse(ps.tippingPaused());
      ps.pauseTipping();
      assertTrue(ps.tippingPaused());
      ps.unpauseTipping();
      assertFalse(ps.tippingPaused());
    }

    function testAllPause() public {
      assertFalse(ps.mintingPaused());
      ps.pauseMinting();
      assertTrue(ps.mintingPaused());
      ps.unpauseMinting();
      assertFalse(ps.mintingPaused());

      assertFalse(ps.renewalPaused());
      ps.pauseRenewal();
      assertTrue(ps.renewalPaused());
      ps.unpauseRenewal();
      assertFalse(ps.renewalPaused());

      assertFalse(ps.tippingPaused());
      ps.pauseTipping();
      assertTrue(ps.tippingPaused());
      ps.unpauseTipping();
      assertFalse(ps.tippingPaused());
    }

}


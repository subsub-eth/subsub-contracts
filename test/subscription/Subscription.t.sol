// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Subscription.sol";
import "../mocks/TestSubscription.sol";
import "./AbstractTestSub.sol";

import {
    SubscriptionEvents,
    ClaimEvents,
    MetadataStruct,
    SubSettings,
    SubscriptionFlags
} from "../../src/subscription/ISubscription.sol";
import "../../src/subscription/handle/SubscriptionHandle.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SubscriptionTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags, TestSubEvents {
    event MetadataUpdate(uint256 _tokenId);

    Subscription public sub;

    address public owner;
    address public alice;
    address public bob;

    ERC20DecimalsMock public testToken;

    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint256 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        owner = address(10);
        alice = address(11);
        bob = address(12);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        testToken.mint(alice, 10_000_000_000 ether);
        // bob does not receive tokens

        settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);

        sub = new SimpleTestSub(owner, "name", "symbol", metadata, settings);
    }

    function testSetExternalUrl() public {
        string memory url = "something else";
        vm.prank(owner);
        sub.setExternalUrl(url);

        (,, string memory externalUrl) = sub.metadata();

        assertEq(url, externalUrl);
    }

    function testSetExternalUrl_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setExternalUrl("meh");
    }

    function testSetImage() public {
        string memory newImage = "something else";
        vm.prank(owner);
        sub.setImage(newImage);

        (, string memory image,) = sub.metadata();

        assertEq(newImage, image);
    }

    function testSetImage_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setImage("meh");
    }

    function testSetDescription() public {
        string memory desc = "something else";
        vm.prank(owner);
        sub.setDescription(desc);

        (string memory description,,) = sub.metadata();

        assertEq(desc, description);
    }

    function testSetDescription_notOwner() public {
        string memory desc = "something else";
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setDescription(desc);
    }

    function testSetFlags(uint256 flags) public {
        flags = bound(flags, 0, ALL_FLAGS);
        vm.prank(owner);
        sub.setFlags(flags);
    }

    function testSetFlags_invalid(uint256 flags) public {
        flags = bound(flags, ALL_FLAGS + 1, type(uint256).max);
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }

    function testSetFlags_notOwner() public {
        uint256 flags = 1;
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }

    function testBurn(uint256 tokenId) public {
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.totalSupply(), 1, "Token created");
        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.prank(alice);
        vm.expectEmit();
        emit Burned(tokenId);

        _sub.burn(tokenId);

        assertEq(_sub.totalSupply(), 0, "Token burned");
        assertEq(_sub.balanceOf(alice), 0, "Token burned from user");
    }

    function testBurn_notOwner(uint256 tokenId, address user) public {
        vm.assume(alice != user && user != address(this));
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.startPrank(user);
        vm.expectRevert();
        _sub.burn(tokenId);
    }

    function testBurn_twice(uint256 tokenId) public {
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        vm.prank(alice);

        _sub.burn(tokenId);

        vm.expectRevert();
        _sub.burn(tokenId);
    }

    function testMint(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);

        vm.expectEmit();
        emit SubCreated(1, amount * _sub.CONV(), multiplier);
        vm.expectEmit();
        emit AddedToEpochs(block.number, amount * _sub.CONV(), multiplier, rate);
        vm.expectEmit();
        emit SubscriptionRenewed(1, amount, alice, _sub.TOTAL_DEPOSITED(), message);

        _sub.mint(amount, multiplier, message);

        assertEq(_sub.balanceOf(alice), 1, "Token created");
        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testMint_maxSupply(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        settings.maxSupply = 1;
        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        _sub.mint(amount, multiplier, message);

        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_maxSupply0(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        settings.maxSupply = 0;
        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 0, 99));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier_large(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_mintPaused(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(owner, settings);
        vm.prank(owner);
        _sub.setFlags(MINTING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        _sub.mint(amount, multiplier, message);
    }

    function testChangeMultiplier_active(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        ChangeMultiplierActiveSub _sub = new ChangeMultiplierActiveSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);

        vm.expectEmit();
        emit MultiChange(tokenId, newMulti);
        vm.expectEmit();
        emit EpochsReduced(_sub.OLD_DEPOSITED_AT(), _sub.OLD_AMOUNT(), _sub.REDUCED_AMOUNT(), _sub.OLD_MULTI(), rate);
        vm.expectEmit();
        emit AddedToEpochs(_sub.NEW_DEPOSITED_AT(), _sub.NEW_AMOUNT(), newMulti, rate);
        vm.expectEmit();
        emit MultiplierChanged(tokenId, alice, _sub.OLD_MULTI(), newMulti);

        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_inactive(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);

        vm.expectEmit();
        emit MultiChange(tokenId, newMulti);
        vm.expectEmit();
        emit MultiplierChanged(tokenId, alice, _sub.OLD_MULTI(), newMulti);

        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_NoToken(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(owner, settings);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_invalidMulti_lower(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, 0, Lib.MULTIPLIER_BASE - 1));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_invalidMulti_higher(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, Lib.MULTIPLIER_MAX + 1, type(uint24).max));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_unauthorized(uint256 tokenId, uint24 newMulti, address user) public {
        vm.assume(user != alice);
        newMulti = uint24(bound(newMulti, Lib.MULTIPLIER_BASE, Lib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testRenew(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewExtendSub _sub = new RenewExtendSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, alice, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_reactivate(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewReactivateSub _sub = new RenewReactivateSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit AddedToEpochs(block.number, _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, alice, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_otherUser(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        vm.assume(user != address(0) && user != alice && user != address(this));

        testToken.mint(user, 100_000_000_000 ether);
        amount = bound(amount, 0, testToken.balanceOf(user));

        RenewExtendSub _sub = new RenewExtendSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, user, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_noToken(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(owner, settings);

        vm.startPrank(user);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.renew(tokenId, amount, message);
    }

    function testRenew_paused(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(owner, settings);

        vm.prank(owner);
        _sub.setFlags(RENEWAL_PAUSED);

        vm.startPrank(user);

        vm.expectRevert("Flag: setting enabled");
        _sub.renew(tokenId, amount, message);
    }

    function testWithdraw(uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        amount = bound(amount, 0, exWithdrawable);
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, amount, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.withdraw(tokenId, amount);

        assertEq(testToken.balanceOf(address(bob)), amount, "amount transferred");
    }

    function testWithdraw_tokenNotExist(uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        vm.startPrank(bob);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.withdraw(tokenId, amount);
    }

    function testWithdraw_notOwner(address user, uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        vm.assume(user != address(this) && user != bob);
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        amount = bound(amount, 0, exWithdrawable);
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.withdraw(tokenId, amount);
    }

    function testCancel(uint256 tokenId, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, withdrawable);
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, exWithdrawable, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.cancel(tokenId);

        assertEq(testToken.balanceOf(address(bob)), exWithdrawable, "amount transferred");
    }

    function testCancel_notOwner(address user, uint256 tokenId, uint256 withdrawable) public {
        vm.assume(user != address(this) && user != bob);
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.cancel(tokenId);
    }

    function testCancel_tokenNotExist(uint256 tokenId, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(owner, settings, withdrawable);

        vm.startPrank(bob);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.cancel(tokenId);
    }

    function testClaimable(uint256 claimable) public {
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        assertEq(_sub.claimable(), claimable / _sub.CONV(), "Claimable as external");
    }

    function testClaim(address to, uint256 claimable) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);
        uint256 exClaimable = claimable / _sub.CONV();
        testToken.mint(address(_sub), exClaimable);

        vm.startPrank(owner);
        vm.expectEmit();
        emit FundsClaimed(exClaimable, _sub.TOTAL_CLAIMED() / _sub.CONV());

        _sub.claim(to);

        assertEq(testToken.balanceOf(to), exClaimable, "claimable funds transferred");
    }

    function testClaimBatch(address to, uint256 claimable, uint256 upToEpoch) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);
        uint256 exClaimable = claimable / _sub.CONV();
        testToken.mint(address(_sub), exClaimable);

        vm.startPrank(owner);
        vm.expectEmit();
        emit FundsClaimed(exClaimable, _sub.TOTAL_CLAIMED() / _sub.CONV());

        _sub.claim(to, upToEpoch);

        assertEq(testToken.balanceOf(to), exClaimable, "claimable funds transferred");
    }

    function testClaimBatch_notOwner(address user, address to, uint256 claimable, uint256 upToEpoch) public {
        vm.assume(user != owner);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        vm.startPrank(user);
        vm.expectRevert();

        _sub.claim(to, upToEpoch);
    }

    function testClaim_notOwner(address user, address to, uint256 claimable) public {
        vm.assume(user != owner);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        vm.startPrank(user);
        vm.expectRevert();

        _sub.claim(to);
    }

    function testTip(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 1, testToken.balanceOf(alice));

        TipSub _sub = new TipSub(owner, settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit TipAdded(tokenId, amount);
        vm.expectEmit();
        emit Tipped(tokenId, amount, alice, _sub.TIPS(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.tip(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testTip_anyUser(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        vm.assume(user != address(0));
        testToken.mint(user, 100_000_000_000 ether);
        amount = bound(amount, 1, testToken.balanceOf(user));

        TipSub _sub = new TipSub(owner, settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit TipAdded(tokenId, amount);
        vm.expectEmit();
        emit Tipped(tokenId, amount, user, _sub.TIPS(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.tip(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testTip0(uint256 tokenId, string calldata message) public {
        TipSub _sub = new TipSub(owner, settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: amount too small");
        _sub.tip(tokenId, 0, message);
    }

    function testTip_notExist(uint256 tokenId, uint256 amount, string calldata message) public {
        TipSub _sub = new TipSub(owner, settings, 0);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.tip(tokenId, amount, message);
    }

    function testTip_disabled(uint256 tokenId, uint256 amount, string calldata message) public {
        TipSub _sub = new TipSub(owner, settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.prank(owner);
        _sub.setFlags(TIPPING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        _sub.tip(tokenId, amount, message);
    }

    function testClaimTips(address to, uint256 claimable) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        TipSub _sub = new TipSub(owner, settings, claimable);
        testToken.mint(address(_sub), claimable);

        vm.startPrank(owner);

        vm.expectEmit();
        emit TipsClaimed(claimable, _sub.CLAIMED_TIPS());

        _sub.claimTips(to);

        assertEq(testToken.balanceOf(address(to)), claimable, "amount transferred");
    }

    function testClaimTips_notOwner(address user, address to, uint256 claimable) public {
        vm.assume(user != owner);
        TipSub _sub = new TipSub(owner, settings, claimable);

        vm.prank(user);
        vm.expectRevert();
        _sub.claimTips(to);
    }
}

contract BurnSub is AbstractTestSub {
    constructor()
        AbstractTestSub(
            address(0),
            "name",
            "symbol",
            MetadataStruct("description", "image", "externalUrl"),
            SubSettings(new ERC20DecimalsMock(18), 0, 0, 0, 100)
        )
    {}

    function _deleteSubscription(uint256 tokenId) internal override {
        emit Burned(tokenId);
    }
}

contract MintSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _totalDeposited(uint256) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal override {
        emit SubCreated(tokenId, amount, multiplier);
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) internal override {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract RenewExtendSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _multiplier(uint256) internal pure override returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = false;
    }

    function _extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override
    {
        emit EpochsExtended(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract RenewReactivateSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _multiplier(uint256) internal pure override returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = true;
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) internal override {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract ChangeMultiplierActiveSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant OLD_MULTI = 999;
    uint24 public constant NEW_MULTI = 2222;

    uint256 public constant OLD_DEPOSITED_AT = 1234;
    uint256 public constant OLD_AMOUNT = 2345;
    uint256 public constant REDUCED_AMOUNT = 55433;
    uint256 public constant NEW_DEPOSITED_AT = 44444;
    uint256 public constant NEW_AMOUNT = 55555;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _changeMultiplier(uint256 tokenId, uint24 multi) internal virtual override returns (bool isActive_, MultiplierChange memory c) {
        emit MultiChange(tokenId, multi);

        isActive_ = true;
        c.oldDepositAt = OLD_DEPOSITED_AT;
        c.oldAmount = OLD_AMOUNT;
        c.oldMultiplier = OLD_MULTI;
        c.reducedAmount = REDUCED_AMOUNT;
        c.newDepositAt = NEW_DEPOSITED_AT;
        c.newAmount = NEW_AMOUNT;

    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) internal override {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
    }

    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override
    {
        emit EpochsReduced(depositedAt, oldDeposit, newDeposit, shares, rate);
    }
}

contract ChangeMultiplierInactiveSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant OLD_MULTI = 999;
    uint24 public constant NEW_MULTI = 2222;

    uint256 public constant OLD_DEPOSITED_AT = 1234;
    uint256 public constant OLD_AMOUNT = 2345;
    uint256 public constant REDUCED_AMOUNT = 55433;
    uint256 public constant NEW_DEPOSITED_AT = 44444;
    uint256 public constant NEW_AMOUNT = 55555;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _changeMultiplier(uint256 tokenId, uint24 multi) internal virtual override returns (bool isActive_, MultiplierChange memory c) {
        emit MultiChange(tokenId, multi);

        isActive_ = false;
        c.oldMultiplier = OLD_MULTI;

    }
}

contract WithdrawSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    uint256 public withdrawable;

    constructor(address owner, SubSettings memory settings, uint256 _withdrawable)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {
        withdrawable = _withdrawable;
    }

    function _withdrawableFromSubscription(uint256) internal view override returns (uint256) {
        return withdrawable;
    }

    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        emit SubWithdrawn(tokenId, amount);
        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
    }

    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override
    {
        emit EpochsReduced(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _multiplier(uint256) internal pure override returns (uint24) {
        return MULTI;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract ClaimSub is AbstractTestSub {
    uint256 public constant CONV = 10;

    uint256 public constant CURRENT_EPOCH = 1234;
    uint256 public constant LAST_PROCESSED_EPOCH = 2345;
    uint256 public constant TOTAL_CLAIMED = 9876;

    uint256 public claimable_;

    constructor(address owner, SubSettings memory settings, uint256 _claimable)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {
        claimable_ = _claimable;
    }

    function _scanEpochs(uint256, uint256) internal view override returns (uint256 amount, uint256 a, uint256 b) {
        amount = claimable_;
        a = 0;
        b = 0;
    }

    function _claimEpochs(uint256, uint256) internal view override returns (uint256) {
        return claimable_;
    }

    function _currentEpoch() internal pure override returns (uint256) {
        return CURRENT_EPOCH;
    }

    function _lastProcessedEpoch() internal pure override returns (uint256) {
        return LAST_PROCESSED_EPOCH;
    }

    function _claimed() internal pure virtual override returns (uint256) {
        return TOTAL_CLAIMED;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract TipSub is AbstractTestSub {
    uint256 public constant CONV = 10;

    uint256 public constant TIPS = 1234;
    uint256 public constant ALL_TIPS = 2345;
    uint256 public constant CLAIMED_TIPS = 6789;

    uint256 public claimable_;

    constructor(address owner, SubSettings memory settings, uint256 _claimable)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {
        claimable_ = _claimable;
    }

    function _scanEpochs(uint256, uint256) internal view override returns (uint256 amount, uint256 a, uint256 b) {
        amount = claimable_;
        a = 0;
        b = 0;
    }

    function _addTip(uint256 tokenId, uint256 amount) internal override {
        emit TipAdded(tokenId, amount);
    }

    function _tips(uint256) internal pure override returns (uint256) {
        return TIPS;
    }

    function _allTips() internal pure override returns (uint256) {
        return ALL_TIPS;
    }

    function _claimedTips() internal pure override returns (uint256) {
        return CLAIMED_TIPS;
    }

    function _claimableTips() internal view override returns (uint256) {
        return claimable_;
    }

    function _claimTips() internal view override returns (uint256) {
        return claimable_;
    }
}
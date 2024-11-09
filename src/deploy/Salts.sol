// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Salts {
    string public constant PROFILE_KEY = "createz::proxy::Profile";
    string public constant SUBSCRIPTION_BEACON_KEY = "createz::beacon::Subscription";
    string public constant SUBSCRIPTION_HANDLE_KEY = "createz::proxy::SubscriptionHandle";

    string public constant BADGE_BEACON_KEY = "createz::beacon::Badge";
    string public constant BADGE_HANDLE_KEY = "createz::proxy::BadgeHandle";
}
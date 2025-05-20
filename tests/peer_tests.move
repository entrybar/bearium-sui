#[test_only]
module bearium::peer_tests;

use bearium::peer::{Self};

use sui::sui::SUI;
use sui::test_scenario::{Self};

#[test]
fun test_provision_peer() {
    let mut scenario = test_scenario::begin(@0x0);
    {
        peer::iam<SUI>(scenario.ctx());
    };
    scenario.end();
}

// SPDX-License-Identifier: MIT
module bearium::toss;

use sui::coin::{Coin};
use sui::random::{Self, Random};

use bearium::peer::{Peer, Credit};
use bearium::room::{Self};

public fun edge_bps(): u16 {
    100 // x 0.01% = 1%
}

fun face_bps(actual: u8, expect: bool): u32 {
    if ((actual == 1 && expect) || (actual == 0 && !expect)) 2 * 10_000
    else 0
}

entry fun toss<T>(
    r: &Random,
    peer: &Peer<T>,
    c: Coin<T>,
    outcome: bool,
    ctx: &mut TxContext
): u8 {
    let mut generator = random::new_generator(r, ctx);
    let known = random::generate_u8_in_range(&mut generator, 0, 1);
    room::disburse(
        peer, ctx.sender(),
        option::some(c), option::none(),
        face_bps(known, outcome),
        edge_bps(), ctx);
    known
}

entry fun toss_up<T>(
    r: &Random, peer: &Peer<T>,
    c: Credit<T>,
    outcome: bool,
    ctx: &mut TxContext
): u8 {
    peer.identify(&c);
    let mut generator = random::new_generator(r, ctx);
    let known = random::generate_u8_in_range(&mut generator, 0, 1);
    room::disburse(
        peer, ctx.sender(),
        option::none(), option::some(c),
        face_bps(known, outcome),
        edge_bps(), ctx);
    known
}

entry fun toss_in<T>(
    r: &Random, peer: &Peer<T>,
    a: Coin<T>,
    c: Credit<T>,
    outcome: bool,
    ctx: &mut TxContext
): u8 {
    peer.identify(&c);
    let mut generator = random::new_generator(r, ctx);
    let known = random::generate_u8_in_range(&mut generator, 0, 1);
    room::disburse(
        peer, ctx.sender(),
        option::some(a), option::some(c),
        face_bps(known, outcome),
        edge_bps(), ctx);
    known
}

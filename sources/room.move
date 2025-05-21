// SPDX-License-Identifier: BUSL-1.1
module bearium::room;

use sui::coin::{Self, Coin};

use bearium::peer::{Peer, Credit};

public(package) fun disburse<T>(
    peer: &Peer<T>,
    creditor: address,
    charge: Option<Coin<T>>,
    mut credit: Option<Credit<T>>,
    face_bps: u32, // zero to odds
    edge_bps: u16, // instant rate
    ctx: &mut TxContext
) {
    // capture
    if (face_bps == 0) {
        charge.do!(|c| {
            if (c.value() == 0) coin::destroy_zero(c)
            else transfer::public_transfer(c, peer.at()) // merits
        });
        credit.do!(|c| c.draw()); // dedicated
        return
    };
    // default
    let mut stakes = 0;
    charge.do_ref!(|c| stakes = stakes + c.value());
    credit.do_ref!(|c| stakes = stakes + c.value());
    if (stakes > 0) {
        let rewards = derive_proportion(stakes, face_bps);
        let surplus = rewards - stakes;
        let instant = derive_proportion(rewards, edge_bps as u32);
        let mut present = peer.wedge(surplus, ctx);
        if (instant > 0) {
            let edge = present.withdraw(instant , ctx);
            transfer::public_transfer(edge, peer.at());
        };
        if (credit.is_some()) present.join(credit.extract());
        credit.fill(present);
    };
    charge.do!(|c| {
        if (c.value() == 0) coin::destroy_zero(c)
        else transfer::public_transfer(c, creditor);
    });
    credit.do!(|c| {
        if (c.value() == 0) c.draw()
        else transfer::public_transfer(c, creditor);
    });
}

fun derive_proportion(amount: u64, rate_bps: u32): u64 {
    ((amount as u128) * (rate_bps as u128) / 10_000) as u64
}

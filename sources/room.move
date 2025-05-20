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
    edge_bps: u16, // instant interest
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
    let mut stake = 0;
    charge.do_ref!(|c| stake = stake + c.value());
    credit.do_ref!(|c| stake = stake + c.value());
    if (stake > 0) {
        let total = derive_proportion(stake, face_bps);
        let gross = total - stake;
        let yield = derive_proportion(total, edge_bps as u32);
        let mut present = peer.wedge(gross, ctx);
        if (yield > 0) {
            let edge = present.withdraw(yield , ctx);
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

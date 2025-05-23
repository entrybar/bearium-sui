// SPDX-License-Identifier: BUSL-1.1
module bearium::peer;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};

//------------
// Invariants.
//------------

/// For when trying to operate on an unexpected peer.
const EBadPeer: u64 = 0;
/// For when trying to operate on a nonsensical value.
const EZero: u64 = 1;
/// For when trying to withdraw more than there is.
const ENotEnough: u64 = 2;

//---------
// Genesis.
//---------

/// A peer is a shared object.
/// Authenticity is eventually consistency.
/// Capital consensus is the fast path to UTXO.
public struct Peer<phantom CoinT> has key {
    id: UID,
    goods: u64,
    capital: Balance<CoinT>,
    entry: vector<Lot<CoinT>>,
    edge: Option<Credit<CoinT>>,
    chain: vector<Preferred<CoinT>>,
}

public fun iam<T>(ctx: &mut TxContext): ID {
    let id = object::new(ctx);
    let identity = id.to_inner();
    let self = Peer<T> {
        id,
        goods: 0,
        edge: option::none(),
        capital: balance::zero(),
        entry: vector[],
        chain: vector[],
    };
    transfer::share_object(self);
    identity
}

public fun at<T>(self: &Peer<T>): address {
    self.id.to_address()
}

public fun identify<T>(self: &Peer<T>, asset: &Credit<T>) {
    assert!(asset.peer_id == self.id.to_inner(), EBadPeer)
}

public fun capture<T>(peer: &mut Peer<T>, charge: transfer::Receiving<Coin<T>>) {
    let c = transfer::public_receive(&mut peer.id, charge);
    peer.capital.join(c.into_balance());
}

public fun promise<T>(peer: &mut Peer<T>, alpha: transfer::Receiving<Credit<T>>) {
    let c = transfer::public_receive(&mut peer.id, alpha);
    if (peer.edge.is_none()) peer.edge.fill(c)
    else peer.edge.borrow_mut().join(c)
}

//--------------------
// The Alpha's Rights.
//--------------------

public struct Credit<phantom CoinT> has key, store {
    id: UID,
    peer_id: ID,
    alpha: u64,
}

public(package) fun wedge<CoinT>(peer: &Peer<CoinT>, alpha: u64, ctx: &mut TxContext): Credit<CoinT> {
    Credit {
        id: object::new(ctx),
        peer_id: peer.id.to_inner(),
        alpha,
    }
}

/// Recycle
public(package) fun draw<T>(self: Credit<T>) {
    decay(self); // void
}

public fun value<T>(self: &Credit<T>): u64 {
    return self.alpha
}

//-------------------
// The Mass's Rights.
//-------------------

public fun redeem_available<T>(peer: &mut Peer<T>, credit: &mut Credit<T>, ctx: &mut TxContext): Coin<T> {
    assert!(credit.peer_id == peer.id.to_inner(), EBadPeer);
    assert!(credit.alpha > 0, EZero);
    let mut present = honor(peer, credit, ctx);
    if (present.is_none()) present.fill(coin::zero(ctx));
    present.destroy_some()
}

public fun redeem_with_debt<T>(peer: &mut Peer<T>, mut credit: Credit<T>, ctx: &mut TxContext): Coin<T> {
    let reward = redeem_available(peer, &mut credit, ctx);
    if (credit.alpha == 0) {
        draw(credit);
        return reward
    };
    // Liability is a Block.
    let block = prefer(credit, ctx);
    peer.chain.push_back(block);
    reward
}

public struct Preferred<phantom CoinT> has key, store {
    id: UID,
    lead: Credit<CoinT>,
    creditor: address,
    issued_at: u64,
}

fun prefer<T>(lead: Credit<T>, ctx: &mut TxContext): Preferred<T> {
    Preferred {
        id: object::new(ctx),
        lead,
        creditor: ctx.sender(),
        issued_at: ctx.epoch(), // on the same day
    }
}

//--------------------
// The Omega's Rights.
//--------------------

public struct Equity<phantom CoinT> has key, store {
    id: UID,
    peer_id: ID,
    omega: u64,
}

public struct Lot<phantom CoinT> has key, store {
    id: UID,
    land: Equity<CoinT>,
    liquid: Balance<CoinT>,
    outstanding_shares: u64,
}

/// Equity Interest of a Lot.
public struct Interest<phantom CoinT> has key, store {
    id: UID,
    lot_id: ID,
    liquidity: u64,
}

public fun assume<T>(peer: &mut Peer<T>, appetite: Coin<T>, ctx: &mut TxContext): Interest<T> {
    assert!(appetite.value() > 0, EZero);
    if (peer.has_no_plan()) {
        let plan = peer.allocate(ctx);
        peer.entry.push_back(plan)
    };
    let last = peer.entry.length() - 1;
    let plan = peer.entry.borrow_mut(last);
    let liquidity = appetite.value();
    plan.liquid.join(appetite.into_balance());
    plan.outstanding_shares = plan.outstanding_shares + liquidity;
    Interest {
        id: object::new(ctx),
        lot_id: plan.id.to_inner(),
        liquidity
    }
}

public fun secure<T>(self: &mut Peer<T>, ctx: &mut TxContext) {
    loop {
        if (self.chain.length() == 0) return; // clear
        let mut block = self.chain.pop_back();
        self.honor(&mut block.lead, ctx).do!(|present| {
            transfer::public_transfer(present, block.creditor)
        });
        if (block.lead.alpha == 0) {
            let Preferred { id, lead, creditor: _, issued_at: _ } = block;
            id.delete();
            draw(lead);
        } else {
            self.chain.push_back(block);
            return // empty
        }
    }
}

// archive
// claim

fun allocate<T>(self: &Peer<T>, ctx: &mut TxContext): Lot<T> {
    let land = Equity {
        id: object::new(ctx),
        peer_id: self.id.to_inner(),
        omega: 0,
    };
    Lot {
        id: object::new(ctx),
        land,
        liquid: balance::zero(),
        outstanding_shares: 0,
    }
}

fun has_no_plan<T>(self: &Peer<T>): bool {
    if (self.entry.length() == 0) return true;
    let last = self.entry.length() - 1;
    let lot = self.entry.borrow(last);
    lot.is_exclusive()
}

fun is_exclusive<T>(self: &Lot<T>): bool {
    // fully or partially spent
    self.liquid.value() != self.outstanding_shares
}

//-------------
// Equilibirum.
//-------------

fun honor<T>(self: &mut Peer<T>, asset: &mut Credit<T>, ctx: &mut TxContext): Option<Coin<T>> {
    let mut scale = vector<Coin<T>>[];

    // always take from capital first
    scale.append(self.turn(asset, ctx).to_vec());

    // lots after that
    let well = self.entry.length();
    let mut spot = 0;
    loop {
        if (asset.alpha == 0) break;
        if (spot == well) break;
        scale.append(self.hedge(spot, asset, ctx).to_vec());
        spot = spot + 1
    };

    // consolidate
    let mut present: Option<Coin<T>> = option::none();
    scale.do!(|c| {
        if (present.is_none()) present.fill(c)
        else present.borrow_mut().join(c);
    });
    present
}

fun turn<T>(self: &mut Peer<T>, metal: &mut Credit<T>, ctx: &mut TxContext): Option<Coin<T>> {
    let alpha = equilibirum(self, metal);
    if (alpha == 0) return option::none();
    let lead = withdraw(metal, alpha, ctx);
    let gold = debit(self, lead, ctx);
    option::some(gold)
}

fun equilibirum<T>(self: &Peer<T>, asset: &Credit<T>): u64 {
    if (asset.alpha > self.capital.value()) {
        self.capital.value()
    } else {
        asset.alpha
    }
}

fun hedge<T>(self: &mut Peer<T>, spot: u64, bar: &mut Credit<T>, ctx: &mut TxContext): Option<Coin<T>> {
    let lot = self.entry.borrow_mut(spot);
    let alpha  = promised(lot, bar);
    if (alpha == 0) return option::none();
    let stone = withdraw(bar, alpha, ctx);
    let (gold, parcel) = lot.base( stone, ctx);
    self.goods = self.goods + parcel.omega; // vibing
    lot.land.merge(parcel);
    option::some(gold)
}

fun promised<T>(self: &Lot<T>, asset: &Credit<T>): u64 {
    if (asset.alpha > self.liquid.value()) {
        self.liquid.value()
    } else {
        asset.alpha
    }
}

fun base<T>(self: &mut Lot<T>, lead: Credit<T>, ctx: &mut TxContext): (Coin<T>, Equity<T>) {
    assert!(lead.peer_id == self.land.peer_id);
    assert!(lead.alpha > 0, EZero);
    assert!(self.liquid.value() > 0, ENotEnough);
    let (peer_id, alpha) = decay(lead);
    (
        coin::take(&mut self.liquid, alpha, ctx),
        Equity {
            id: object::new(ctx),
            peer_id,
            omega: alpha,
        }
    )
}

public fun debit<T>(self: &mut Peer<T>, lead: Credit<T>, ctx: &mut TxContext): Coin<T> {
    assert!(lead.peer_id == self.id.to_inner(), EBadPeer);
    assert!(lead.alpha > 0, EZero);
    assert!(self.capital.value() >= lead.alpha, ENotEnough);
    let (_, alpha) = decay(lead);
    coin::take(&mut self.capital, alpha, ctx)
}

fun decay<CoinT>(um: Credit<CoinT>): (ID, u64) {
    let Credit { id, peer_id, alpha } = um;
    id.delete();
    (peer_id, alpha)
}

public fun withdraw<T>(um: &mut Credit<T>, alpha: u64, ctx: &mut TxContext): Credit<T> {
    assert!(um.alpha >= alpha, ENotEnough);
    um.alpha = um.alpha - alpha;
    Credit {
        id: object::new(ctx),
        peer_id: um.peer_id,
        alpha,
    }
}

public fun merge<T>(self: &mut Equity<T>, right: Equity<T>) {
    let Equity {id, peer_id, omega} = right;
    assert!(peer_id == self.peer_id, EBadPeer);
    id.delete();
    self.omega = self.omega + omega;
}

public fun join<T>(self: &mut Credit<T>, c: Credit<T>) {
    let (peer_id, alpha) = decay(c);
    assert!(peer_id == self.peer_id, EBadPeer);
    self.alpha = self.alpha + alpha
}

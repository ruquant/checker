(* ************************************************************************* *)
(*                                Uniswap                                    *)
(* ************************************************************************* *)
(* The general concept of uniswap is that you have quantity a of an asset A
 * and b of an asset B and you process buy and sell requests by maintaining
 * the product a * b constant. So if someone wants to sell a quantity da of
 * asset A to the contract, the balance would become (a + da) so you can
 * give that person a quantity db of asset B in exchange such that (a +
 * da)(b - db) = a * b. Solving for db gives db  = da * b / (a + da). We
 * can rewrite this as db = da * (b / a) * (a / (a + da)) where (b / a)
 * represents the  "price" before the order and a / (a + da)  represents
 * the "slippage". Indeed, a property of uniswap is that with arbitrageurs
 * around, the ratio (a / b) gives you the market price of A in terms of B.
 *
 * On top of that, we can add some fees of 0.2 cNp. So the equation becomes
 * something like db = da * b / (a + da) * (1 - 0.2/100) (note that this
 * formula is a first-order approximation in the sense that two orders of size
 * da / 2 will give you a better price than one order of size da, but the
 * difference is far smaller than typical fees or any amount we care about.
*)
type liquidity

val show_liquidity : liquidity -> string
val pp_liquidity : Format.formatter -> liquidity -> unit

val liquidity_of_int : int -> liquidity

(* TODO: The state of uniswap should also (in the future) include an ongoing
 * auction to decide who to delegate to, possibly multiple tez balances, etc.
 * Just leaving this note here lest we forget. *)
(* TODO: Would be sweet if we didn't have to expose the definition here *)
type t =
  { tez: Tez.t;
    kit: Kit.t;
    total_liquidity_tokens: liquidity;
  }

val show : t -> string
val pp : Format.formatter -> t -> unit

(** Check whether the uniswap contract contains at least some kit and some tez. *)
val uniswap_non_empty : t -> bool

(** Compute the current price of kit in tez, as estimated using the ratio of
  * tez and kit currently in the uniswap contract. *)
val kit_in_tez : t -> Q.t

(** Buy some kit from the uniswap contract. Fail if the desired amount of kit
  * cannot be bought or if the deadline has passed. *)
val buy_kit : t -> Tez.t -> min_kit_expected:Kit.t -> now:Timestamp.t -> deadline:Timestamp.t -> (Kit.t * t, Error.error) result

(** Sell some kit to the uniswap contract. Fail if the desired amount of tez
  * cannot be bought or if the deadline has passed. *)
val sell_kit : t -> Kit.t -> min_tez_expected:Tez.t -> now:Timestamp.t -> deadline:Timestamp.t -> (Tez.t * t, Error.error) result

(** Buy some liquidity from the uniswap contract, by giving it some tez and
  * some kit. If the given amounts does not have the right ratio, we
  * liquidate as much as we can with the right ratio, and return the
  * leftovers, along with the liquidity tokens. *)
(* But where do the assets in uniswap come from? Liquidity providers, or
 * "LP" deposit can deposit a quantity la and lb of assets A and B in the
 * same proportion as the contract la / lb = a / b . Assuming there are n
 * "liquidity tokens" extant, they receive m = floor(n la / a) tokens and
 * there are now m +n liquidity tokens extant. They can redeem then at
 * anytime for a fraction of the assets A and B. The reason to do this in
 * uniswap is that usage of uniswap costs 0.3%, and that ultimately can
 * grow the balance of the assets in the contract. An additional reason
 * to do it in huxian is that the kit balance of the uniswap contract is
 * continuously credited with the burrow fee taken from burrow holders.
*)
val buy_liquidity : t -> Tez.t -> Kit.t -> liquidity * Tez.t * Kit.t * t

(** Sell some liquidity to the uniswap contract. Selling liquidity always
  * succeeds, but might leave the contract without tez and kit if everybody
  * sells their liquidity. I think it is unlikely to happen, since the last
  * liquidity holders wouldn't want to lose the burrow fees.
*)
val sell_liquidity : t -> liquidity -> Tez.t * Kit.t * t

(** Add accrued burrowing fees to the uniswap contract. NOTE: non-negative? *)
val add_accrued_kit : t -> Kit.t -> t
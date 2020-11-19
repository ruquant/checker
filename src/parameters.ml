(* ************************************************************************* *)
(*                               Parameters                                  *)
(* ************************************************************************* *)
type t =
  { (* TODO: Perhaps maintain 1/q instead of q? TBD *)
    q : FixedPoint.t; (* 1/kit, really *)
    index: Tez.t;
    protected_index: Tez.t;
    target: FixedPoint.t;
    drift': FixedPoint.t;
    drift: FixedPoint.t;
    burrow_fee_index: FixedPoint.t;
    imbalance_index: FixedPoint.t;
    (* TODO: What would be a good starting value for this? Cannot be zero
     * because then it stays zero forever (only multiplications occur). *)
    outstanding_kit: Kit.t;
    circulating_kit: Kit.t;
    last_touched: Timestamp.t;
  }
[@@deriving show]

(** Initial state of the parameters. TODO: Contents TBD. *)
let make_initial (ts: Timestamp.t) : t =
  { q = FixedPoint.one;
    index = Tez.one;
    protected_index = Tez.one;
    target = FixedPoint.one;
    drift = FixedPoint.zero;
    drift' = FixedPoint.zero;
    burrow_fee_index = FixedPoint.one;
    imbalance_index = FixedPoint.one;
    outstanding_kit = Kit.of_mukit 1_000_000;
    circulating_kit = Kit.of_mukit 1_000_000;
    last_touched = ts;
  }

(* tez. To get tez/kit must multiply with q. *)
let tz_minting (p: t) : Tez.t = max p.index p.protected_index

(* tez. To get tez/kit must multiply with q. *)
let tz_liquidation (p: t) : Tez.t = min p.index p.protected_index

(** Current minting price (tez/kit). *)
let minting_price (p: t) : Q.t =
  Q.(FixedPoint.to_q p.q * Tez.to_q (tz_minting p))

(** Current liquidation price (tez/kit). *)
let liquidation_price (p: t) : Q.t =
  Q.(FixedPoint.to_q p.q * Tez.to_q (tz_liquidation p))

let qexp amount = Q.(one + amount)

let clamp (v: Q.t) (lower: Q.t) (upper: Q.t) : 'a =
  assert (Q.compare lower upper <> 1);
  Q.min upper (Q.max v lower)

(** Given the amount of kit necessary to close all existing burrows
  * (burrowed) and the amount of kit that are currently in circulation,
  * compute the current imbalance adjustment (can be either a fee or a
  * bonus).
  *
  * If we call "burrowed" the total amount of kit necessary to close all
  * existing burrows, and "circulating" the total amount of kit in circulation,
  * then the imbalance fee/bonus is calculated as follows (per year):
  *
  *   min(   5 * burrowed, (burrowed - circulating) ) * 1.0 cNp / burrowed , if burrowed >= circulating
  *   max( - 5 * burrowed, (burrowed - circulating) ) * 1.0 cNp / burrowed , otherwise
*)
let compute_imbalance ~(burrowed: Kit.t) ~(circulating: Kit.t) : Q.t =
  assert (burrowed >= Kit.zero);
  assert (circulating >= Kit.zero);
  (* No kit in burrows or in circulation means no imbalance adjustment *)
  if burrowed = Kit.zero then
    (* TODO: George: though unlikely, it is possible to have kit in
     * circulation, even when nothing is burrowed. How can we compute the
     * imbalance in this edge case? *)
    (assert (circulating = Kit.zero); Q.zero) (* George: the assert is just as a reminder *)
  else if burrowed >= circulating then
    Q.(min (Kit.to_q burrowed * of_int 5) Kit.(to_q (burrowed - circulating))
       * of_string "1/100"
       / Kit.to_q burrowed)
  else (* burrowed < circulating *)
    Q.(max (Kit.to_q burrowed * of_int (-5)) Kit.(to_q (burrowed - circulating))
       * of_string "1/100"
       / Kit.to_q burrowed)

(** Compute the current adjustment index. Basically this is the product of
  * the burrow fee index and the imbalance adjustment index. *)
let compute_adjustment_index (p: t) : FixedPoint.t =
  let burrow_fee_index = FixedPoint.to_q p.burrow_fee_index in
  let imbalance_index = FixedPoint.to_q p.imbalance_index in
  FixedPoint.of_q_floor Q.(burrow_fee_index * imbalance_index) (* FLOOR-or-CEIL *)

(** Given the current target, calculate the rate of change of the drift (drift
  * derivative). Thresholds were given in cnp / day^2, so we convert them to
  * cnp / second^2, assuming we're measuring time in seconds. Also, since exp
  * is monotonic, we exponentiate the whole equation to avoid using log. TODO:
  * double-check these calculations. *)
let compute_drift_derivative (target : FixedPoint.t) : FixedPoint.t =
  assert (target > FixedPoint.zero);
  let target = FixedPoint.to_q target in
  let target_low_bracket  = Constants.target_low_bracket in
  let target_high_bracket = Constants.target_high_bracket in
  let cnp_001 = FixedPoint.(of_string "0.0001") in
  let cnp_005 = FixedPoint.(of_string "0.0005") in
  let secs_in_a_day = FixedPoint.of_int (24 * 3600) in
  match () with
  (* No acceleration (0) *)
  | () when qexp (Q.neg target_low_bracket) < target && target < qexp target_low_bracket -> FixedPoint.zero
  (* Low acceleration (-/+) *)
  | () when qexp (Q.neg target_high_bracket) < target && target <= qexp (Q.neg target_low_bracket) -> FixedPoint.(neg (cnp_001 / pow secs_in_a_day 2))
  | () when qexp        target_high_bracket  > target && target >= qexp        target_low_bracket  -> FixedPoint.(    (cnp_001 / pow secs_in_a_day 2))
  (* High acceleration (-/+) *)
  | () when target <= qexp (Q.neg target_high_bracket) -> FixedPoint.(neg (cnp_005 / pow secs_in_a_day 2))
  | () when target >= qexp        target_high_bracket  -> FixedPoint.(    (cnp_005 / pow secs_in_a_day 2))
  | _ -> failwith "impossible"

(** Update the checker's parameters, given (a) the current timestamp
  * (Tezos.now), (b) the current index (the median of the oracles right now),
  * and (c) the current price of kit in tez, as given by the uniswap
  * sub-contract. *)
let touch
    (tezos: Tezos.t)
    (current_index: FixedPoint.t) (* TODO: George: shouldn't this be in Tez.t instead? *)
    (current_kit_in_tez: Q.t)
    (parameters: t)
  : Kit.t * t =
  let duration_in_seconds =
    Q.of_int
    @@ Timestamp.seconds_elapsed
      ~start:parameters.last_touched
      ~finish:tezos.now
  in

  let current_protected_index =
    let upper_lim = Q.(qexp      (Constants.protected_index_epsilon * duration_in_seconds)) in
    let lower_lim = Q.(qexp (neg  Constants.protected_index_epsilon * duration_in_seconds)) in

    Tez.of_q_floor Q.( (* FLOOR-or-CEIL *)
        Tez.to_q parameters.protected_index
        * clamp
          (FixedPoint.to_q current_index / Tez.to_q parameters.protected_index)
          lower_lim
          upper_lim
      ) in
  let current_drift' = compute_drift_derivative parameters.target in
  let current_drift =
    FixedPoint.of_q_floor Q.( (* FLOOR-or-CEIL *)
        FixedPoint.to_q parameters.drift
        + of_string "1/2"
          * FixedPoint.(to_q (parameters.drift' + current_drift'))
          * duration_in_seconds
      ) in

  let current_q =
    FixedPoint.of_q_floor Q.( (* FLOOR-or-CEIL *)
        FixedPoint.to_q parameters.q
        * qexp ( ( FixedPoint.to_q parameters.drift
                   + of_string "1/6"
                     * ((of_int 2 * FixedPoint.to_q parameters.drift') + FixedPoint.to_q current_drift')
                     * duration_in_seconds )
                 * duration_in_seconds )
      ) in

  let current_target = FixedPoint.of_q_floor Q.( (* FLOOR-or-CEIL *)
      FixedPoint.to_q current_q * FixedPoint.to_q current_index / current_kit_in_tez
    ) in

  (* Update the indices *)
  let current_burrow_fee_index = FixedPoint.of_q_floor Q.( (* FLOOR-or-CEIL *)
      FixedPoint.to_q parameters.burrow_fee_index
      * (one
         + Constants.burrow_fee_percentage
           * duration_in_seconds / Q.of_int Constants.seconds_in_a_year)
    ) in

  let imbalance_percentage =
    compute_imbalance
      ~burrowed:parameters.outstanding_kit
      ~circulating:parameters.circulating_kit in

  let current_imbalance_index = FixedPoint.of_q_floor Q.( (* FLOOR-or-CEIL *)
      FixedPoint.to_q parameters.imbalance_index
      * (one
         + imbalance_percentage
           * duration_in_seconds / Q.of_int Constants.seconds_in_a_year)
    ) in

  let with_burrow_fee = Kit.of_q_floor Q.( (* FLOOR-or-CEIL *)
      Kit.to_q parameters.outstanding_kit
      * FixedPoint.to_q current_burrow_fee_index
      / FixedPoint.to_q parameters.burrow_fee_index
    ) in

  let total_accrual_to_uniswap = Kit.(with_burrow_fee - parameters.outstanding_kit) in

  let current_outstanding_kit = Kit.of_q_floor Q.( (* FLOOR-or-CEIL *)
      Kit.to_q with_burrow_fee
      * FixedPoint.to_q current_imbalance_index
      / FixedPoint.to_q parameters.imbalance_index
    ) in

  let current_circulating_kit = Kit.(parameters.circulating_kit + total_accrual_to_uniswap) in

  ( total_accrual_to_uniswap
  , {
    index = Tez.(scale one current_index);
    protected_index = current_protected_index;
    target = current_target;
    drift = current_drift;
    drift' = current_drift';
    q = current_q;
    burrow_fee_index = current_burrow_fee_index;
    imbalance_index = current_imbalance_index;
    outstanding_kit = current_outstanding_kit;
    circulating_kit = current_circulating_kit;
    last_touched = tezos.now;
  }
  )

(** Add some kit to the total amount of kit in circulation. *)
let add_circulating_kit (parameters: t) (kit: Kit.t) : t =
  assert (kit >= Kit.zero);
  { parameters with circulating_kit = Kit.(parameters.circulating_kit + kit); }

(** Remove some kit from the total amount of kit in circulation. *)
let remove_circulating_kit (parameters: t) (kit: Kit.t) : t =
  assert (kit >= Kit.zero);
  assert (parameters.circulating_kit >= kit);
  { parameters with circulating_kit = Kit.(parameters.circulating_kit - kit); }

(** Add some kit to the total amount of kit required to close all burrows. *)
let add_outstanding_kit (parameters: t) (kit: Kit.t) : t =
  assert (kit >= Kit.zero);
  { parameters with outstanding_kit = Kit.(parameters.outstanding_kit + kit); }

(** Remove some kit from the total amount of kit required to close all burrows. *)
let remove_outstanding_kit (parameters: t) (kit: Kit.t) : t =
  assert (kit >= Kit.zero);
  assert (parameters.outstanding_kit >= kit);
  { parameters with outstanding_kit = Kit.(parameters.outstanding_kit - kit); }

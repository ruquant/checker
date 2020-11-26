(* ************************************************************************* *)
(*                               FixedPoint                                  *)
(* ************************************************************************* *)
type t = Z.t

let scaling_base = Z.of_int64 2L
let scaling_exponent = 64
let scaling_factor = Z.pow scaling_base scaling_exponent

(* Predefined values. *)
let zero = Z.zero
let one = scaling_factor

(* Arithmetic operations. *)
let ( + ) x y = Z.(x + y)
let ( - ) x y = Z.(x - y)
let ( * ) x y = Z.((x * y) / scaling_factor)

(* We round towards 0, for fixedpoint calculation, measuring things which are
 * inherently noisy, this is ok. Greater care must be excercised when doing
 * accounting (e.g. uniswap)... for measuring things like drift, targets,
 * imbalances etc which are naturally imprecise this is fine. *)
let ( / ) x y = Z.(x * scaling_factor / y)
let neg x = Z.neg x

let pow x y =
  assert (y >= 0);
  if y = 0
  then one
  else Z.div (Z.pow x y) (Z.pow scaling_factor Stdlib.(y - 1))

(* NOTE: Use another term from the taylor sequence for more accuracy:
 *   one + amount + (amount * amount) / (one + one) *)
let exp amount = one + amount

(* Conversions to/from other types. *)
let of_int amount = Z.(of_int amount * scaling_factor)

let of_hex_string str =
  let without_dot = Str.replace_first (Str.regexp (Str.quote ".")) "" str in
  let dotpos = String.rindex_opt str '.' in
  let mantissa = match dotpos with
    | None -> Z.one
    | Some pos -> Z.pow (Z.of_int 16) Stdlib.(String.length str - pos - 1) in
  Z.((Z.of_string_base 16 without_dot * scaling_factor) / mantissa)

let to_q amount = Q.make amount scaling_factor
let of_q_ceil amount = Z.(cdiv (Q.num amount * scaling_factor) (Q.den amount))
let of_q_floor amount = Z.(fdiv (Q.num amount * scaling_factor) (Q.den amount))
(* George: do we need flooring-division or truncating-division? more thought is needed *)

(* Pretty printing functions (in hex, otherwise it's massive) *)
let show amount =
  let zfill s width =
    let to_fill = Stdlib.(width - (String.length s)) in
    if to_fill <= 0
    then s
    else (String.make to_fill '0') ^ s in

  let sign = if amount < Z.zero then "-" else "" in
  let (upper, lower) = Z.div_rem (Z.abs amount) scaling_factor in

  Format.sprintf "%s%s.%s"
    sign
    (Z.format "%X" upper)
    (zfill (Z.format "%X" lower) Stdlib.(scaling_exponent / 4))

let pp ppf amount = Format.fprintf ppf "%s" (show amount)


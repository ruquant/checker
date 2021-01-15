(* type address *)
(**
   An untyped address which can refer to a smart contract or account.
*)

(* type ('key, 'value) big_map *)

(**
   The type of a big map from values of type key to values of type value is big_map (key, value).

   Be aware that a big_map cannot appear inside another big_map.
*)

(* type bool *)

(* type bytes *)

(* type 'parameter contract *)
(**
   A typed contract.

   Use unit as parameter to indicate an implicit account.
*)

(* type chain_id *)
(**
    The identifier of a chain, used to indicate test or main chains.
*)

type int
(**
   An integer.

   The only size limit to integers is gas.
*)

val int_from_literal : Int.t -> int
val compare_int : int -> int -> Int.t
val string_of_int : int -> string

(* type key *)
(**
    A public cryptographic key.
*)

(* type key_hash *)
(**
    The hash of a public cryptographic key.
*)

(* type 't list *)
(**
    A sequence of elements of the same type.
*)

(* type ('key, 'value) map *)
(**
    The type of a map from values of type key to values of type value is map (key, value).
*)

(* type nat *)
(**
    A natural number.

     The only size limit to natural numbers is gas.
*)

(* type operation *)
(**
    An operation emitted by the contract
*)

(* type 'value set *)

(* type signature *)
(**
    A cryptographic signature.
*)

(* type string *)
(**
    A sequence of characters.
*)

(* type tez *)
(**
    A specific type for tokens.
*)

(* type timestamp *)
(**
    A date in the real world.
*)

(* type unit *)

(* val is_nat: int -> nat option *)
(**
   Convert an int to a nat if possible.

   Note that Michelson.is_nat is deprecated. Please use is_nat instead.
*)

(* val abs: int -> nat *)
(**
   Cast an int to nat.
*)

(* val int: nat -> int *)
(**
   Cast an nat to int.
*)

(* val unit: unit *)
(**
   A helper to create a unit.
*)

(* val failwith : 'a -> unit *)
(**
   Cause the contract to fail with an error message or integer. Other types are not supported at the moment.

   Using this currently requires in general a type annotation on the failwith call.
*)

(* val assert : bool -> unit *)
(**
    Check if a certain condition has been met. If not the contract will fail.
*)

(* val ediv_int_int : int -> int -> (int * nat) option *)

(* val ediv_tez_nat : tez -> nat -> (tez * tez) option *)

(* val ediv_tez_tez : tez -> tez -> (nat * tez) option *)

(* val ediv_nat_nat : nat -> nat -> (nat * nat) option *)

(* Additions *)

(* val add_nat_nat : nat -> nat -> nat *)

val add_int_int : int -> int -> int

(* val add_tez_tez : tez -> tez -> tez *)

(* val add_nat_int : nat -> int -> int *)

(* val add_int_nat : int -> nat -> int *)

(* val add_timestamp_int : timestamp -> int -> timestamp *)

(* val add_int_timestamp : int -> timestamp -> timestamp *)

(* Subtractions *)

(* val sub_timestamp_int : timestamp -> int -> timestamp *)

(* val sub_timestamp_timestamp : timestamp -> timestamp -> int *)

(* val sub_int_int : int -> int -> int *)

(* val sub_int_nat : int -> nat -> int *)

(* val sub_nat_int : nat -> int -> int *)

(* val sub_nat_nat : nat -> nat -> int *)

(* TODO: The following also seem to be allowed,
 *
 *   val sub_mutez_mutez : mutez -> mutez -> mutez
 *   val sub_mutez_tez : mutez -> tez -> mutez
 *   val sub_tez_mutez : tez -> mutez -> mutez
 *   val sub_tez_tez : tez -> tez -> mutez
 *
 * but I (George) am totally unclear as to what is mutez as a type. My
 * impression is that the only type we have for tez is "tez", values of which
 * we can construct by giving a number of tez or mutez.
*)

(* TODO: arithmetic shim functions *)

(* BEGIN_OCAML *)

val pp_int : Format.formatter -> int -> unit
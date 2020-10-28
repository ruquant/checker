open Avl
open OUnit2
module Q = QCheck
open BigMap
open Tez

type element_list = (int * unit * Tez.t) list [@@deriving show]

let nTez (i: int) : Tez.t =
  Tez.of_float (float_of_int i)

let rec to_list (mem: (int, unit) mem) (root: ptr option) : element_list =
  match root with
  | None -> []
  | Some k -> match mem_get mem k with
    | Leaf leaf -> [(leaf.key, leaf.value, leaf.tez)]
    | Branch branch ->
      List.append
        (to_list mem (Some branch.left))
        (to_list mem (Some branch.right))

let from_list (mem: (int, unit) mem) (elements: element_list)
  : (int, unit) mem * ptr option =
  add_all mem None elements

let assert_invariants (mem: (int, unit) mem) (root: ptr option) : unit =
  let rec go (parent: ptr option) (curr: ptr) =
    match mem_get mem curr with
    | Leaf leaf ->
      assert (leaf.parent = parent)
    | Branch branch ->
      let left = mem_get mem branch.left in
      let right = mem_get mem branch.right in
      assert (branch.parent = parent);
      assert (branch.left_height = node_height left);
      assert (branch.left_tez = node_tez left);
      assert (branch.right_height = node_height right);
      assert (branch.right_tez = node_tez right);
      assert (abs (branch.left_height - branch.right_height) < 2);
      go (Some curr) branch.left;
      go (Some curr) branch.right
  in match root with
  | None -> ()
  | Some root_ptr -> go None root_ptr

let assert_dangling_pointers (mem: (int, unit) mem) (roots: ptr option list) : unit =
  let rec delete_tree (mem: (int, unit) mem) (root_ptr: ptr) : (int, unit) mem =
    let root = mem_get mem root_ptr in
    let mem = mem_del mem root_ptr in
    match root with
    | Leaf _ -> mem
    | Branch branch ->
      let mem = delete_tree mem branch.left in
      let mem = delete_tree mem branch.right in
      mem in
  let mem = List.fold_left
      (fun mem x -> Option.fold ~none:mem ~some:(delete_tree mem) x)
      mem
      roots in
  assert (BigMap.is_empty mem)

let qcheck_to_ounit t = OUnit.ounit2_of_ounit1 @@ QCheck_ounit.to_ounit_test t

module IntSet = Set.Make(Int)

let property_test_count = 1000

let suite =
  "AVLTests" >::: [
    "test_singleton" >::
    (fun _ ->
       let (mem, root) = add BigMap.empty empty 0 () (nTez 5) in
       let actual = to_list mem (Some root) in
       let expected = [(0, (), nTez 5)] in
       assert_equal expected actual);

    (*
    "test_multiple" >::
    (fun _ ->
       let elements =
         (List.map (fun i -> { id = i; tez = nTez 5; })
            [ 1; 2; 8; 4; 3; 5; 6; 7; ]) in
       let (mem, root) = add_all BigMap.empty None elements in
       let actual = to_list mem root in
       let expected = List.sort (fun a b -> compare a.id b.id) elements in
       assert_equal expected actual ~printer:show_element_list);
    *)

    "test_del_singleton" >::
    (fun _ ->
       let (mem, root) = add BigMap.empty None 1 () (nTez 5) in
       let (mem, root) = del mem (Some root) 1 in
       assert_equal None root;
       assert_bool "mem wasn't empty" (BigMap.is_empty mem));

    "test_del" >::
    (fun _ ->
       let elements =
         (List.map (fun i -> (i, (), nTez 5))
            [ 1; 2; 8; 4; 3; 5; 6; 7; ]) in
       let (mem, root) = from_list BigMap.empty elements in
       let (mem, root) = del mem root 5 in
       assert_invariants mem root;
       assert_dangling_pointers mem [root];
       let actual = to_list mem root in
       let expected =
         List.sort
           (fun (a, _, _) (b, _, _) -> compare a b)
           (List.filter (fun (i, _,_ ) -> i <> 5) elements) in
       assert_equal expected actual ~printer:show_element_list);

    "test_empty_from_list_to_list" >::
    (fun _ ->
       let elements = [] in
       let (mem, root) = from_list BigMap.empty elements in
       let actual = to_list mem root in
       let expected = [] in
       assert_equal expected actual);

    (qcheck_to_ounit
     @@ Q.Test.make ~name:"prop_from_list_to_list" ~count:property_test_count Q.(list small_int)
     @@ fun xs ->
     let mkitem i = (i, (), nTez (100 + i)) in

     let (mem, root) = add_all BigMap.empty None (List.map mkitem xs) in
     assert_invariants mem root;
     assert_dangling_pointers mem [root];

     let actual = to_list mem root in

     let expected = List.map mkitem (IntSet.elements @@ IntSet.of_list xs) in
     assert_equal expected actual ~printer:show_element_list;
     true
    );

    (qcheck_to_ounit
     @@ Q.Test.make ~name:"prop_del" ~count:property_test_count Q.(list small_int)
     @@ fun xs ->
     Q.assume (List.length xs > 0);
     let (to_del, xs) = (List.hd xs, List.tl xs) in

     let mkitem i = (i, (), nTez (100 + i)) in

     let (mem, root) = add_all BigMap.empty None (List.map mkitem xs) in
     assert_invariants mem root;

     let (mem, root) = del mem root to_del in
     assert_invariants mem root;

     let actual = to_list mem root in

     let expected =
       xs
       |> IntSet.of_list
       |> IntSet.remove to_del
       |> IntSet.elements
       |> List.map mkitem in
     assert_equal expected actual ~printer:show_element_list;
     true
    );

    (qcheck_to_ounit
     @@ Q.Test.make ~name:"prop_join" ~count:property_test_count Q.(list small_int)
     @@ fun xs ->
     Q.assume (List.length xs > 2);
     let (pos, xs) = (List.hd xs, List.tl xs) in

     let xs = List.sort_uniq (fun i j -> Int.compare i j) xs in

     Q.assume (pos > 0);
     Q.assume (pos < List.length xs - 1);
     Q.assume (List.for_all (fun i -> i > 0) xs);

     let splitAt n xs =
       let rec go n xs acc =
         if n <= 0
         then (List.rev acc, xs)
         else match xs with
           | [] -> failwith "index out of bounds"
           | (x::xs) -> go (n-1) xs (x::acc)
       in go n xs [] in

     let mkitem i = (i, (), nTez (100 + i)) in
     let (left, right) = splitAt pos xs in
     let (left, right) = (List.map mkitem left, List.map mkitem right) in

     let mem = BigMap.empty in
     let (mem, left_tree) = add_all mem None left in
     let (mem, right_tree) = add_all mem None right in

         (*
         print_string "=Left==================================\n";
         print_string (debug_string mem left_tree);
         print_newline ();
         print_string "-Right---------------------------------\n";
         print_string (debug_string mem right_tree);
         print_newline ();
         *)

     let (mem, joined_tree) =
       join mem (Option.get left_tree) (Option.get right_tree) in

         (*
         print_string "-Joined--------------------------------\n";
         print_string (debug_string mem (Some joined_tree));
         print_newline ();
         *)

     let joined_tree = Some joined_tree in
     assert_invariants mem joined_tree;
     assert_dangling_pointers mem [joined_tree];

     let actual = to_list mem joined_tree in
     let expected = left @ right in

     assert_equal expected actual ~printer:show_element_list;
     true
    );

    (qcheck_to_ounit
     @@ Q.Test.make ~name:"prop_split" ~count:property_test_count Q.(list small_int)
     @@ fun xs ->
     Q.assume (List.length xs > 0);
     Q.assume (List.for_all (fun i -> i > 0) xs);
     let (limit, xs) = (List.hd xs, List.tl xs) in
     let mkitem i = (i, (), nTez i) in

     let (mem, root) = add_all BigMap.empty None (List.map mkitem xs) in

     let (mem, left, right) = split mem root (nTez limit) in
     assert_invariants mem left;
     assert_invariants mem right;
     assert_dangling_pointers mem [left; right];

     let actual_left = to_list mem left in
     let actual_right = to_list mem right in

     let rec split_list lim xs =
       match xs with
       | [] -> ([], [])
       | x :: xs ->
         if x <= lim
         then
           match split_list (lim - x) xs with
             (l, r) -> (x::l, r)
         else
           ([], x::xs)
     in

     let (expected_left, expected_right) =
       xs
       |> IntSet.of_list
       |> IntSet.elements
       |> split_list limit in

     assert_equal
       (List.map mkitem expected_left)
       actual_left
       ~printer:show_element_list;

     assert_equal
       (List.map mkitem expected_right)
       actual_right
       ~printer:show_element_list;

     true
    )
  ]
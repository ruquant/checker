open Huxian
open OUnit2
open Tez

let suite =
  "HuxianTests" >::: [
    "test_step" >::
    fun _ -> let initial_parameters = { q = 0.9;
                                        index = Tez.of_float 0.36;
                                        target = 1.08;
                                        protected_index = Tez.of_float 0.35;
                                        drift = 0.0;
                                        drift' = 0.0;
                                      } in
      let interblock_time = Seconds 3600 in
      let new_index = 0.34 in
      let tez_per_kit = 0.305 in
      let new_parameters = step_parameters interblock_time new_index tez_per_kit initial_parameters in
      assert_equal
        { q = 0.900000130208;
          index = Tez.of_float 0.34;
          protected_index = Tez.of_float 0.34;
          target = 1.00327883367;
          drift' = 6.69795953361e-14;
          drift = 1.20563271605e-10 }
        new_parameters
        ~printer:show_checker_parameters
  ]


let () =
  run_test_tt_main suite


package bp_common_aviary_pkg;
  `include "bp_common_aviary_defines.vh"

  // Suitably high enough to not run out of configs.
  localparam max_cfgs    = 128;
  localparam lg_max_cfgs = `BSG_SAFE_CLOG2(max_cfgs);

  localparam bp_proc_param_s bp_inv_cfg_p = 
    '{default: "inv"};

  localparam bp_proc_param_s bp_single_core_cfg_p = 
    '{num_core: 1
      ,num_cce: 1
      ,num_lce: 2

      ,vaddr_width: 39
      ,paddr_width: 56
      ,asid_width : 1
      
      ,btb_tag_width: 10
      ,btb_idx_width: 6
      ,bht_idx_width: 9
      ,ras_idx_width: 2
      
      ,lce_sets       : 64
      ,lce_assoc      : 8
      ,cce_block_width: 512

      ,fe_queue_fifo_els: 8
      ,fe_cmd_fifo_els  : 2

      ,dword_width: 64
      };

  localparam bp_proc_param_s bp_dual_core_cfg_p = 
    '{num_core: 2
      ,num_cce: 2
      ,num_lce: 4
      
      ,vaddr_width: 39
      ,paddr_width: 56
      ,asid_width : 1
      
      ,btb_tag_width: 10
      ,btb_idx_width: 6
      ,bht_idx_width: 9
      ,ras_idx_width: 2
      
      ,lce_sets       : 64
      ,lce_assoc      : 8
      ,cce_block_width: 512

      ,fe_queue_fifo_els: 8
      ,fe_cmd_fifo_els  : 2

      ,dword_width: 64
      };

  typedef enum bit [lg_max_cfgs-1:0] 
  {
    e_bp_dual_core_cfg    = 2
    ,e_bp_single_core_cfg = 1
    ,e_bp_inv_cfg         = 0
  } bp_cfgs_e;

  parameter bp_proc_param_s [max_cfgs-1:0] all_cfgs_assoc_gp =
  {
    bp_dual_core_cfg_p
    ,bp_single_core_cfg_p
    ,bp_inv_cfg_p
  };

endpackage : bp_common_aviary_pkg


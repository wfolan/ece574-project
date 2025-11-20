// Copyright (c) 2025 Patrick Schaumont
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

package mmreg_pkg;
   parameter int AddressBits = 1;
   parameter int RegWidth    = 32;

   typedef struct packed {
      logic [31:0] reg0;
      logic [31:0] reg1;
   } mmreg_reg_fields_t;

   typedef union packed {
      mmreg_reg_fields_t strct; 
      logic [2*32-1:0]  arr; 
   } mmreg_reg_union_t;
   
   parameter logic [AddressBits-1:0] REG0_OFFSET = 1'b0;
   parameter logic [AddressBits-1:0] REG1_OFFSET = 1'b1;

   parameter logic [31:0] REG0_DEFAULT = 32'h00000000;
   parameter logic [31:0] REG1_DEFAULT = 32'h11111111;

   parameter logic [2*32-1:0] register_default = {REG0_DEFAULT,
						  REG1_DEFAULT};
endpackage; // mmreg_pkg

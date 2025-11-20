`include "common_cells/registers.svh"

// Copyright (c) 2025 Patrick Schaumont
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

module mmreg #(
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
) (
   input logic clk_i, 
   input logic rst_ni,
    
   input       obi_req_t obi_req_i, 
   output      obi_rsp_t obi_rsp_o
   );

   import mmreg_pkg::*;
   
   logic [ObiCfg.DataWidth-1:0] rsp_data;
   logic			valid_d, valid_q;
   logic			err;
   logic			w_err_d, w_err_q;
   logic [AddressBits-1:0]	word_addr_d, word_addr_q;
   logic [ObiCfg.IdWidth-1:0]	id_d, id_q;  
   logic			we_d, we_q;
   logic			req_d, req_q;
   
   // OBI rsp Assignment
   always_comb begin
      obi_rsp_o.r.rdata       = rsp_data;
      obi_rsp_o.r.rid         = id_q;
      obi_rsp_o.r.err         = err;
      obi_rsp_o.r.r_optional  = '0;
      obi_rsp_o.gnt           = obi_req_i.req;
      obi_rsp_o.rvalid        = valid_q;
   end

   // id, valid and address handling
   assign id_d          = obi_req_i.a.aid;
   assign valid_d       = obi_req_i.req;
   assign word_addr_d   = obi_req_i.a.addr[AddressBits+2:2]; 
   assign we_d          = obi_req_i.a.we;
   assign req_d         = obi_req_i.req;

   `FF(id_q, id_d, '0, clk_i, rst_ni)
   `FF(valid_q, valid_d, '0, clk_i, rst_ni)
   `FF(word_addr_q, word_addr_d, '0, clk_i, rst_ni)
   `FF(we_q, we_d, '0, clk_i, rst_ni)
   `FF(w_err_q, w_err_d, '0, clk_i, rst_ni)
   `FF(req_q, req_d, '0, clk_i, rst_ni)

   // memory mapped registers
   mmreg_reg_union_t reg_d, reg_q;

   always_comb 
     begin
	err     = w_err_q;
	w_err_d = 1'b0;
	rsp_data = 32'h0;  
	
	// internal writes go here
	// ...
	
	// OBI-Writes
	if (obi_req_i.req & obi_req_i.a.we & obi_req_i.a.be[0]) 
	  begin
	     w_err_d = 1'b0;
             case (word_addr_d)
	       REG0_OFFSET: 
		 begin
		    reg_d.strct.reg0 = obi_req_i.a.wdata[RegWidth-1:0];
		 end
	       REG1_OFFSET: 
		 begin
		    reg_d.strct.reg1 = obi_req_i.a.wdata[RegWidth-1:0];
		 end
               default: 
		 begin
		    w_err_d = 1'b1;
		 end
             endcase
	  end // if (obi_req_i.req & obi_req_i.a.we & obi_req_i.a.be[0])
	
	// internal reads go here
	// ...
	
	// OBI reads
	if (req_q & ~we_q) 
	  begin
	     err = 1'b0; 
	     case (word_addr_q)
	       REG0_OFFSET: rsp_data[RegWidth-1:0] = reg_q.strct.reg0;	     
	       REG1_OFFSET: rsp_data[RegWidth-1:0] = reg_q.strct.reg1;
               default:     err = 1'b1; 
	     endcase
	  end // if (req_q & ~we_q)
	
     end // always_comb
   
   `FF(reg_q.arr, reg_d.arr, mmreg_pkg::register_default, clk_i, rst_ni);
   
endmodule

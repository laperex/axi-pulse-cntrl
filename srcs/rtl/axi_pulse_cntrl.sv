module axi_pulse_cntrl (
    if_axi_lite.slave s_axi,

    output logic pulse_out
);
    // Registers: 0x00 CTRL [0]=enable [1]=invert
    //            0x04 PERIOD  0x08 WIDTH  0x0C STATUS(ro)
    logic [31: 0] reg_ctrl;
    logic [31: 0] reg_period;
    logic [31: 0] reg_width;

    typedef enum logic [1: 0] {
        WR_IDLE,
        WR_RESP
    } wr_state_t;
    wr_state_t wr_state;

    always_ff @(posedge s_axi.aclk) begin
        if (!s_axi.aresetn) begin
            wr_state <= WR_IDLE;
            s_axi.awready <= 1'b0;
            s_axi.wready <= 1'b0;
            s_axi.bvalid <= 1'b0;
            s_axi.bresp <= 2'b00;
            reg_ctrl <= '0;
            reg_period <= 32'd50_000_000;
            reg_width <= 32'd25_000_000;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi.awready <= 1'b1;
                    s_axi.wready <= 1'b1;
                    if (s_axi.awvalid && s_axi.wvalid) begin
                        s_axi.awready <= 1'b0;
                        s_axi.wready <= 1'b0;
                        case (s_axi.awaddr[3: 2])
                            2'b00:   reg_ctrl <= s_axi.wdata;
                            2'b01:   reg_period <= (s_axi.wdata == 0) ? 32'd1 : s_axi.wdata;
                            2'b10:   reg_width <= s_axi.wdata;
                            default: ;
                        endcase
                        wr_state <= WR_RESP;
                    end
                end

                WR_RESP: begin
					s_axi.bvalid <= 1'b1;
					s_axi.bresp  <= 2'b00;
					if (s_axi.bvalid && s_axi.bready) begin   // only clear after master has seen it
						s_axi.bvalid <= 1'b0;
						wr_state     <= WR_IDLE;
					end
				end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    typedef enum logic {
        RD_IDLE,
        RD_DATA
    } rd_state_t;
    rd_state_t rd_state;

    always_ff @(posedge s_axi.aclk) begin
        if (!s_axi.aresetn) begin
            rd_state <= RD_IDLE;
            s_axi.arready <= 1'b0;
            s_axi.rvalid <= 1'b0;
            s_axi.rresp <= 2'b00;
            s_axi.rdata <= '0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi.arready <= 1'b1;
                    if (s_axi.arvalid) begin
                        s_axi.arready <= 1'b0;
                        case (s_axi.araddr[3: 2])
                            2'b00: s_axi.rdata <= reg_ctrl;
                            2'b01: s_axi.rdata <= reg_period;
                            2'b10: s_axi.rdata <= reg_width;
                            2'b11: s_axi.rdata <= {31'b0, pulse_out};
                        endcase
                        s_axi.rvalid <= 1'b1;
                        s_axi.rresp <= 2'b00;
                        rd_state <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    if (s_axi.rready) begin
                        s_axi.rvalid <= 1'b0;
                        rd_state <= RD_IDLE;
                    end
                end
            endcase
        end
    end

    logic [31: 0] counter;
    logic raw_pulse;
    wire enable = reg_ctrl[0];
    wire invert = reg_ctrl[1];

    always_ff @(posedge s_axi.aclk) begin
        if (!s_axi.aresetn || !enable) begin
            counter <= '0;
            raw_pulse <= 1'b0;
        end else begin
            counter <= (counter >= reg_period - 1) ? '0 : counter + 1;
            raw_pulse <= (counter < reg_width);
        end
    end

    assign pulse_out = invert ? ~raw_pulse : raw_pulse;

endmodule

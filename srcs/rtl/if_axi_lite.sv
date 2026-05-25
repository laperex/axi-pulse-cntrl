interface if_axi_lite #(
	parameter integer ADDR_WIDTH		= 4,
	parameter integer DATA_WIDTH		= 32
);
	logic							aclk;
	logic							aresetn;
	logic [ADDR_WIDTH - 1: 0]		awaddr;
	logic [2: 0] 					awprot;
	logic							awvalid;
	logic							awready;
	logic [DATA_WIDTH - 1: 0] 		wdata;
	logic [(DATA_WIDTH / 8) - 1: 0]	wstrb;
	logic							wvalid;
	logic							wready;
	logic [1: 0] 					bresp;
	logic							bvalid;
	logic							bready;
	logic [ADDR_WIDTH - 1: 0] 		araddr;
	logic [2: 0] 					arprot;
	logic							arvalid;
	logic							arready;
	logic [DATA_WIDTH - 1: 0] 		rdata;
	logic [1: 0] 					rresp;
	logic							rvalid;
	logic							rready;

	modport slave (
		input aclk, aresetn,
		input awaddr, awprot, awvalid,
		output awready,
		input wdata, wstrb, wvalid,
		output wready, bresp, bvalid,
		input bready, araddr, arprot, arvalid,
		output arready, rdata, rresp, rvalid,
		input rready
	);

	modport master (
		input aclk, aresetn,
		output awaddr, awprot, awvalid,
		input awready,
		output wdata, wstrb, wvalid,
		input wready, bresp, bvalid,
		output bready, araddr, arprot, arvalid,
		input arready, rdata, rresp, rvalid,
		output rready
	);
endinterface

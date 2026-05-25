# Clock - W5 (100 MHz)
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk_100MHz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100MHz]

# Reset - btnC (centre button, active high)
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports reset_rtl_0]
set_false_path -from [get_ports reset_rtl_0]

# pulse_led - LD4
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports pulse_out_0]

# LEDs [3:0] - LD3..LD0  (gpio_rtl_0_tri_o)
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_0_tri_o[3]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_0_tri_o[2]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_0_tri_o[1]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_0_tri_o[0]}]

# Buttons [3:0] - btnU, btnL, btnR, btnD  (gpio_rtl_1_tri_i)
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_1_tri_i[3]}]
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_1_tri_i[2]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_1_tri_i[1]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {gpio_rtl_1_tri_i[0]}]
set_false_path -from [get_ports {gpio_rtl_1_tri_i[*]}]

# UART - USB-UART bridge (Basys3 onboard FTDI)
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports uart_0_txd]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports uart_0_rxd]
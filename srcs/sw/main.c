#include "xil_printf.h"
#include "xparameters.h"
#include "xgpio.h"

#define PULSE_BASE   XPAR_AXI_PULSE_CTRL_0_BASEADDR
#define PULSE_CTRL   0x00
#define PULSE_PERIOD 0x04
#define PULSE_WIDTH  0x08
#define PULSE_STATUS 0x0C

#define CTRL_ENABLE  (1u << 0)
#define CTRL_INVERT  (1u << 1)

#define CLK_HZ       50000000UL

#define PULSE_WR(off, val) Xil_Out32(PULSE_BASE + (off), (u32)(val))
#define PULSE_RD(off)      Xil_In32 (PULSE_BASE + (off))

static XGpio gpio;

static void set_leds(u8 val) {
    XGpio_DiscreteWrite(&gpio, 1, val & 0xF);
}

static u8 read_btns(void) {
    return (u8)(XGpio_DiscreteRead(&gpio, 2) & 0xF);
}

int main(void) {
    XGpio_Initialize(&gpio, XPAR_AXI_GPIO_0_DEVICE_ID);
    XGpio_SetDataDirection(&gpio, 1, 0x0);  // ch1 outputs (leds)
    XGpio_SetDataDirection(&gpio, 2, 0xF);  // ch2 inputs  (btns)

    PULSE_WR(PULSE_CTRL,   0);
    PULSE_WR(PULSE_PERIOD, CLK_HZ);
    PULSE_WR(PULSE_WIDTH,  CLK_HZ / 2);
    PULSE_WR(PULSE_CTRL,   CTRL_ENABLE);

    xil_printf("axi_pulse_ctrl demo running\r\n");
    xil_printf("btnU=faster  btnD=slower  btnL=invert  btnR=toggle enable\r\n\r\n");

    u8  prev_btns   = 0;
    u32 period      = CLK_HZ;
    u8  invert      = 0;
    u8  enabled     = 1;
    u32 prev_pulse  = 0xFF;

    while (1) {
        u8 btns = read_btns();
        u8 edge = btns & ~prev_btns;  // rising edges only

        if (edge & 0x8) {  // btnU: halve period (faster)
            if (period > 500000) period /= 2;
            PULSE_WR(PULSE_PERIOD, period);
            PULSE_WR(PULSE_WIDTH,  period / 2);
            xil_printf("period -> %lu cycles\r\n", period);
        }
        if (edge & 0x1) {  // btnD: double period (slower)
            if (period < CLK_HZ * 8) period *= 2;
            PULSE_WR(PULSE_PERIOD, period);
            PULSE_WR(PULSE_WIDTH,  period / 2);
            xil_printf("period -> %lu cycles\r\n", period);
        }
        if (edge & 0x4) {  // btnL: toggle invert
            invert ^= 1;
            PULSE_WR(PULSE_CTRL, (enabled ? CTRL_ENABLE : 0) | (invert ? CTRL_INVERT : 0));
            xil_printf("invert -> %d\r\n", invert);
        }
        if (edge & 0x2) {  // btnR: toggle enable
            enabled ^= 1;
            PULSE_WR(PULSE_CTRL, (enabled ? CTRL_ENABLE : 0) | (invert ? CTRL_INVERT : 0));
            xil_printf("enabled -> %d\r\n", enabled);
        }

        prev_btns = btns;

        // Mirror pulse_out to LEDs: pulse on LD0, speed indicator on LD1..LD3
        u32 pulse = PULSE_RD(PULSE_STATUS) & 1;
        if (pulse != prev_pulse) {
            u8 speed_bits = (period <= CLK_HZ / 4) ? 0x7 :
                            (period <= CLK_HZ / 2) ? 0x3 :
                            (period <= CLK_HZ)     ? 0x1 : 0x0;
            set_leds((speed_bits << 1) | (u8)pulse);
            prev_pulse = pulse;
        }
    }

    return 0;
}
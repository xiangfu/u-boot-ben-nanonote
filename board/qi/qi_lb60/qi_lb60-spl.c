/*
 * Authors: Xiangfu Liu <xiangfu@openmobilefree.cc>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 3 of the License, or (at your option) any later version.
 */

#include <common.h>
#include <nand.h>
#include <asm/io.h>
#include <asm/jz4740.h>

#define KEY_U_OUT       (32 * 2 + 16)
#define KEY_U_IN        (32 * 3 + 19)

extern void usb_boot(void);

static void check_usb_boot(void)
{
	__gpio_as_input(KEY_U_IN);
	__gpio_enable_pull(KEY_U_IN);
	__gpio_as_output(KEY_U_OUT);
	__gpio_clear_pin(KEY_U_OUT);

	if (!__gpio_get_pin(KEY_U_IN)) {
		puts("[U] pressed, goto USBBOOT mode\n");
		usb_boot();
	}
}

void nand_spl_boot(void)
{
	__gpio_as_sdram_16bit_4720();
	__gpio_as_uart0();
	__gpio_jtag_to_uart0();

	serial_init();

	pll_init();
	sdram_init();

	check_usb_boot();

	nand_init();

	puts("\nQi LB60 SPL: Starting U-Boot ...\n");
	nand_boot();
}

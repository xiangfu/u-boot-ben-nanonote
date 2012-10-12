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

void nand_spl_boot(void)
{
	__gpio_as_sdram_16bit_4720();
	__gpio_as_uart0();
	__gpio_jtag_to_uart0();

	serial_init();

	pll_init();
	sdram_init();

	nand_init();

	puts("\nQi LB60 SPL: Starting U-Boot ...\n");
	nand_boot();
}

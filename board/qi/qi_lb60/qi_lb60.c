/*
 * Authors: Xiangfu Liu <xiangfu@openmobilefree.net>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 3 of the License, or (at your option) any later version.
 */

#include <common.h>
#include <asm/io.h>
#include <asm/jz4740.h>

DECLARE_GLOBAL_DATA_PTR;

static void gpio_init(void)
{
	unsigned int i, j;

	/* Initialize NAND Flash Pins */
	__gpio_as_nand();

	/* Initialize SDRAM pins */
	__gpio_as_sdram_16bit_4720();

	/* Initialize LCD pins */
	__gpio_as_lcd_18bit();

	/* Initialize MSC pins */
	__gpio_as_msc();

	/* Initialize Other pins */
	for (i = 0; i < 7; i++) {
		__gpio_as_input(GPIO_KEYIN_BASE + i);
		__gpio_enable_pull(GPIO_KEYIN_BASE + i);
	}

	for (i = 0; i < 8; i++) {
		__gpio_as_output(GPIO_KEYOUT_BASE + i);
		__gpio_clear_pin(GPIO_KEYOUT_BASE + i);
	}

	if (__gpio_get_pin(GPIO_KEYIN_BASE + 2) == 0){
		printf("[S] pressed, enable UART0\n");
		gd->boot_option |= BOOT_WITH_ENABLE_UART;
		__gpio_as_uart0();
	} else {
		__gpio_as_input(GPIO_KEYIN_8);
		__gpio_enable_pull(GPIO_KEYIN_8);
	}

	if (__gpio_get_pin(GPIO_KEYIN_BASE + 3) == 0) {
		printf("[M] pressed, boot from memory card\n");
		gd->boot_option |= BOOT_FROM_MEMCARD;
		__gpio_jtag_to_uart0();
	}

	for (j = 0; j < 4; j++) {
		for (i = 0; i < 4; i++)
			__gpio_set_pin(GPIO_KEYOUT_BASE + i);

		__gpio_clear_pin(GPIO_KEYOUT_BASE + j);

		if (__gpio_get_pin(GPIO_KEYIN_BASE) == 0) {
			printf("[F%d] pressed", (j + 1));
			gd->boot_option |= (1 << (j + 2));
			/* BOOT_WITH_F1	(1 << 2) */
			/* BOOT_WITH_F2	(1 << 3) */
			/* BOOT_WITH_F3	(1 << 4) */
			/* BOOT_WITH_F4	(1 << 5) */
		}
	}

	__gpio_as_output(GPIO_AUDIO_POP);
	__gpio_set_pin(GPIO_AUDIO_POP);

	__gpio_as_output(GPIO_LCD_CS);
	__gpio_clear_pin(GPIO_LCD_CS);

	__gpio_as_output(GPIO_AMP_EN);
	__gpio_clear_pin(GPIO_AMP_EN);

	__gpio_as_output(GPIO_SDPW_EN);
	__gpio_disable_pull(GPIO_SDPW_EN);
	__gpio_clear_pin(GPIO_SDPW_EN);

	__gpio_as_input(GPIO_SD_DETECT);
	__gpio_disable_pull(GPIO_SD_DETECT);

	__gpio_as_input(GPIO_USB_DETECT);
	__gpio_enable_pull(GPIO_USB_DETECT);
}

static void cpm_init(void)
{
	struct jz4740_cpm *cpm = (struct jz4740_cpm *)JZ4740_CPM_BASE;
	uint32_t reg = readl(&cpm->clkgr);

	reg |=	CPM_CLKGR_IPU |
		CPM_CLKGR_CIM |
		CPM_CLKGR_I2C |
		CPM_CLKGR_SSI |
		CPM_CLKGR_UART1 |
		CPM_CLKGR_SADC |
		CPM_CLKGR_UHC |
		CPM_CLKGR_UDC |
		CPM_CLKGR_AIC1;

	writel(reg, &cpm->clkgr);
}

int board_early_init_f(void)
{
	gpio_init();
	cpm_init();
	calc_clocks();	/* calc the clocks */
	rtc_init();	/* init rtc on any reset */

	return 0;
}

/* U-Boot common routines */
int checkboard(void)
{
	printf("Board: Qi LB60 (Ingenic XBurst Jz4740 SoC)\n");
	printf(" CPU: %ld\n", gd->cpu_clk);
	printf(" MEM: %ld\n", gd->mem_clk);
	printf(" DEV: %ld\n", gd->dev_clk);

	return 0;
}

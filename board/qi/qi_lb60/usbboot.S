/*
 *  for jz4740 usb boot
 *
 *  Copyright (c) 2009 Author: <jlwei@ingenic.cn>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */
    .set noreorder
    .globl usb_boot
    .text

/*
 * Both NAND and USB boot load data to D-Cache first, then transfer
 * data from D-Cache to I-Cache, and jump to execute the code in I-Cache.
 * So init caches first and then dispatch to a proper boot routine.
 */

.macro load_addr reg addr
	li \reg, 0x80000000
	addiu \reg, \reg, \addr
	la $2, usbboot_begin
	subu \reg, \reg, $2
.endm

usb_boot:
	/* Initialize PLL: set ICLK to 84MHz and HCLK to 42MHz. */
	la	$9, 0xB0000000		/* CPCCR: Clock Control Register */
	la	$8, 0x42041110		/* I:S:M:P=1:2:2:2 */
	sw	$8, 0($9)

	la	$9, 0xB0000010		/* CPPCR: PLL Control Register */
	la	$8, 0x06000120		/* M=12 N=0 D=0 CLK=12*(M+2)/(N+2) */
	sw	$8, 0($9)

	mtc0	$0, $26		/* CP0_ERRCTL, restore WST reset state */
	nop

	mtc0	$0, $16			/* CP0_CONFIG */
	nop

	/* Relocate code to beginning of the ram */

	la $2, usbboot_begin
	la $3, usbboot_end
	li $4, 0x80000000

1:
	lw $5, 0($2)
	sw $5, 0($4)
	addiu $2, $2, 4
	bne $2, $3, 1b
	addiu $4, $4, 4

	li $2, 0x80000000
	ori $3, $2, 0
	addiu $3, $3, usbboot_end
	la $4, usbboot_begin
	subu $3, $3, $4


2:
	cache	0x0, 0($2)		/* Index_Invalidate_I */
	cache	0x1, 0($2)		/* Index_Writeback_Inv_D */
	addiu	$2, $2, 32
	subu $4, $3, $2
	bgtz	$4, 2b
	nop

	load_addr $3, usb_boot_return

	jr $3

usbboot_begin:

init_caches:
	li	$2, 3			/* cacheable for kseg0 access */
	mtc0	$2, $16			/* CP0_CONFIG */
	nop

	li	$2, 0x20000000		/* enable idx-store-data cache insn */
	mtc0	$2, $26			/* CP0_ERRCTL */

	ori	$2, $28, 0		/* start address */
	ori	$3, $2, 0x3fe0		/* end address, total 16KB */
	mtc0	$0, $28, 0		/* CP0_TAGLO */
	mtc0	$0, $28, 1		/* CP0_DATALO */
cache_clear_a_line:
	cache	0x8, 0($2)		/* Index_Store_Tag_I */
	cache	0x9, 0($2)		/* Index_Store_Tag_D */
	bne	$2, $3, cache_clear_a_line
	addiu	$2, $2, 32		/* increment CACHE_LINE_SIZE */

	ori	$2, $28, 0		/* start address */
	ori	$3, $2, 0x3fe0		/* end address, total 16KB */
	la	$4, 0x1ffff000		/* physical address and 4KB page mask */
cache_alloc_a_line:
	and	$5, $2, $4
	ori	$5, $5, 1		/* V bit of the physical tag */
	mtc0	$5, $28, 0		/* CP0_TAGLO */
	cache	0x8, 0($2)		/* Index_Store_Tag_I */
	cache	0x9, 0($2)		/* Index_Store_Tag_D */
	bne	$2, $3, cache_alloc_a_line
	addiu	$2, $2, 32		/* increment CACHE_LINE_SIZE */

	nop
	nop
	nop
	/*
	 * Transfer data from dcache to icache, then jump to icache.
	 * Input parameters:
	 * $19: data length in bytes
	 * $20: jump target address
	 */
xfer_d2i:

	ori	$8, $20, 0
	addu	$9, $8, $19		/* total 16KB */

1:
	cache	0x0, 0($8)		/* Index_Invalidate_I */
	cache	0x1, 0($8)		/* Index_Writeback_Inv_D */
	bne	$8, $9, 1b
	addiu	$8, $8, 32

	/* flush write-buffer */
	sync

	/* Invalidate BTB */
	mfc0	$8, $16, 7		/* CP0_CONFIG */
	nop
	ori	$8, 2
	mtc0	$8, $16, 7
	nop

	/* Overwrite config to disable ram initalisation */
	li $2, 0xff
	sb $2, 20($20)

	jalr	$20
	nop

icache_return:
	/* User code can return to here after executing itself in
	  icache, by jumping to $31. */
	b	usb_boot_return
	nop


usb_boot_return:
	/* Enable the USB PHY */
	la	$9, 0xB0000024		/* CPM_SCR */
	lw	$8, 0($9)
	ori	$8, 0x40		/* USBPHY_ENABLE */
	sw	$8, 0($9)

	/* Initialize USB registers */
	la	$27, 0xb3040000	/* USB registers base address */

	sb	$0, 0x0b($27)	/* INTRUSBE: disable common USB interrupts */
	sh	$0, 0x06($27)	/* INTRINE: disable EPIN interrutps */
	sh	$0, 0x08($27)	/* INTROUTE: disable EPOUT interrutps */

	li	$9, 0x61
	sb	$9, 0x01($27)	/* POWER: HSENAB | SUSPENDM | SOFTCONN */

	/* Initialize USB states */
	li	$22, 0			/* set EP0 to IDLE state */
	li	$23, 1			/* no data stage */

	/* Main loop of polling the usb commands */
usb_command_loop:
	lbu	$9, 0x0a($27)		/* read INTRUSB */
	andi	$9, 0x04		/* check USB_INTR_RESET */
	beqz	$9, check_intr_ep0in
	nop

 	/* 1. Handle USB reset interrupt */
handle_reset_intr:
	lbu	$9, 0x01($27)		/* read POWER */
	andi	$9, 0x10		/* test HS_MODE */
	bnez	$9, _usb_set_maxpktsize
	li	$9, 512			/* max packet size of HS mode */
	li	$9, 64			/* max packet size of FS mode */

_usb_set_maxpktsize:
	li	$8, 1
	sb	$8, 0x0e($27)		/* set INDEX 1 */

	sh	$9, 0x10($27)		/* INMAXP */
	sb	$0, 0x13($27)		/* INCSRH */
	sh	$9, 0x14($27)		/* OUTMAXP */
	sb	$0, 0x17($27)		/* OUTCSRH */

_usb_flush_fifo:
	li	$8, 0x48		/* INCSR_CDT && INCSR_FF */
	sb	$8, 0x12($27)		/* INCSR */
	li	$8, 0x90		/* OUTCSR_CDT && OUTCSR_FF */
	sb	$8, 0x16($27)		/* OUTCSR */

	li	$22, 0			/* set EP0 to IDLE state */
	li	$23, 1			/* no data stage */

	/* 2. Check and handle EP0 interrupt */
check_intr_ep0in:
	lhu	$10, 0x02($27)		/* read INTRIN */
	andi	$9, $10, 0x1		/* check EP0 interrupt */
	beqz	$9, check_intr_ep1in
	nop

handle_ep0_intr:
	sb	$0, 0x0e($27)		/* set INDEX 0 */
	lbu	$11, 0x12($27)		/* read CSR0 */

	andi	$9, $11, 0x04		/* check SENTSTALL */
	beqz	$9, _ep0_setupend
	nop

_ep0_sentstall:
	andi	$9, $11, 0xdb
	sb	$9, 0x12($27)		/* clear SENDSTALL and SENTSTALL */
	li	$22, 0			/* set EP0 to IDLE state */

_ep0_setupend:
	andi	$9, $11, 0x10		/* check SETUPEND */
	beqz	$9, ep0_idle_state
	nop

	ori	$9, $11, 0x80
	sb	$9, 0x12($27)		/* set SVDSETUPEND */
	li	$22, 0			/* set EP0 to IDLE state */

ep0_idle_state:
	bnez	$22, ep0_tx_state
	nop

	/* 2.1 Handle EP0 IDLE state interrupt */
	andi	$9, $11, 0x01		/* check OUTPKTRDY */
	beqz	$9, check_intr_ep1in
	nop

	/* Read 8-bytes setup packet from the FIFO */
	lw	$25, 0x20($27)		/* first word of setup packet */
	lw	$26, 0x20($27)		/* second word of setup packet */

	andi	$9, $25, 0x60		/* bRequestType & USB_TYPE_MASK */
	beqz	$9, _ep0_std_req
	nop

	/* 2.1.1 Vendor-specific setup request */
_ep0_vend_req:
	li	$22, 0			/* set EP0 to IDLE state */
	li	$23, 1			/* NoData = 1 */

	andi	$9, $25, 0xff00		/* check bRequest */
	srl	$9, $9, 8
	beqz	$9, __ep0_get_cpu_info
	sub	$8, $9, 0x1
	beqz	$8, __ep0_set_data_address
	sub	$8, $9, 0x2
	beqz	$8, __ep0_set_data_length
	sub	$8, $9, 0x3
	beqz	$8, __ep0_flush_caches
	sub	$8, $9, 0x4
	beqz	$8, __ep0_prog_start1
	sub	$8, $9, 0x5
	beqz	$8, __ep0_prog_start2
	nop
	b	_ep0_idle_state_fini	/* invalid request */
	nop

__ep0_get_cpu_info:
	load_addr $20, cpu_info_data	/* data pointer to transfer */
	li	$21, 8			/* bytes left to transfer */
	li	$22, 1			/* set EP0 to TX state */
	li	$23, 0			/* NoData = 0 */

	b	_ep0_idle_state_fini
	nop

__ep0_set_data_address:
	li	$9, 0xffff0000
	and	$9, $25, $9
	andi	$8, $26, 0xffff
	or	$20, $9, $8		/* data address of next transfer */

	b	_ep0_idle_state_fini
	nop

__ep0_set_data_length:
	li	$9, 0xffff0000
	and	$9, $25, $9
	andi	$8, $26, 0xffff
	or	$21, $9, $8		/* data length of next transfer */

	li	$9, 0x48		/* SVDOUTPKTRDY and DATAEND */
	sb	$9, 0x12($27)		/* CSR0 */

	/* We must write packet to FIFO before EP1-IN interrupt here. */
	b	handle_epin1_intr
	nop

__ep0_flush_caches:
	/* Flush dcache and invalidate icache. */
	li	$8, 0x80000000
	addi	$9, $8, 0x3fe0		/* total 16KB */

1:
	cache	0x0, 0($8)		/* Index_Invalidate_I */
	cache	0x1, 0($8)		/* Index_Writeback_Inv_D */
	bne	$8, $9, 1b
	addiu	$8, $8, 32

	/* flush write-buffer */
	sync

	/* Invalidate BTB */
	mfc0	$8, $16, 7		/* CP0_CONFIG */
	nop
	ori	$8, 2
	mtc0	$8, $16, 7
	nop

	b	_ep0_idle_state_fini
	nop

__ep0_prog_start1:
	li	$9, 0x48		/* SVDOUTPKTRDY and DATAEND */
	sb	$9, 0x12($27)		/* CSR0 */

	li	$9, 0xffff0000
	and	$9, $25, $9
	andi	$8, $26, 0xffff
	or	$20, $9, $8		/* target address */

	b	xfer_d2i
	li	$19, 0x2000		/* 16KB data length */

__ep0_prog_start2:
	li	$9, 0x48		/* SVDOUTPKTRDY and DATAEND */
	sb	$9, 0x12($27)		/* CSR0 */

	li	$9, 0xffff0000
	and	$9, $25, $9
	andi	$8, $26, 0xffff
	or	$20, $9, $8		/* target address */

	jalr	$20		/* jump, and place the return address in $31 */
	nop

__ep0_prog_start2_return:
/* User code can return to here after executing itself, by jumping to $31 */
	b	usb_boot_return
	nop

	/* 2.1.2 Standard setup request */
_ep0_std_req:
	andi	$12, $25, 0xff00	/* check bRequest */
	srl	$12, $12, 8
	sub	$9, $12, 0x05		/* check USB_REQ_SET_ADDRESS */
	bnez	$9, __ep0_req_set_config
	nop

	/* Handle USB_REQ_SET_ADDRESS */
__ep0_req_set_addr:
	srl	$9, $25, 16		/* get wValue */
	sb	$9, 0x0($27)		/* set FADDR */
	li	$23, 1			/* NoData = 1 */
	b	_ep0_idle_state_fini
	nop

__ep0_req_set_config:
	sub	$9, $12, 0x09		/* check USB_REQ_SET_CONFIGURATION */
	bnez	$9, __ep0_req_get_desc
	nop

	/* Handle USB_REQ_SET_CONFIGURATION */
	li	$23, 1			/* NoData = 1 */
	b	_ep0_idle_state_fini
	nop

__ep0_req_get_desc:
	sub	$9, $12, 0x06		/* check USB_REQ_GET_DESCRIPTOR */
	bnez	$9, _ep0_idle_state_fini
	li	$23, 1			/* NoData = 1 */

	/* Handle USB_REQ_GET_DESCRIPTOR */
	li	$23, 0			/* NoData = 0 */

	srl	$9, $25, 24		/* wValue >> 8 */
	sub	$8, $9, 0x01		/* check USB_DT_DEVICE */
	beqz	$8, ___ep0_get_dev_desc
	srl	$21, $26, 16		/* get wLength */
	sub	$8, $9, 0x02		/* check USB_DT_CONFIG */
	beqz	$8, ___ep0_get_conf_desc
	sub	$8, $9, 0x03		/* check USB_DT_STRING */
	beqz	$8, ___ep0_get_string_desc
	sub	$8, $9, 0x06		/* check USB_DT_DEVICE_QUALIFIER */
	beqz	$8, ___ep0_get_dev_qualifier
	nop
	b	_ep0_idle_state_fini
	nop

___ep0_get_dev_desc:
	load_addr	$20, device_desc	/* data pointer */
	li	$22, 1			/* set EP0 to TX state */
	sub	$8, $21, 18
	blez	$8, _ep0_idle_state_fini /* wLength <= 18 */
	nop
	li	$21, 18			/* max length of device_desc */
	b	_ep0_idle_state_fini
	nop

___ep0_get_dev_qualifier:
	load_addr	$20, dev_qualifier	/* data pointer */
	li	$22, 1			/* set EP0 to TX state */
	sub	$8, $21, 10
	blez	$8, _ep0_idle_state_fini /* wLength <= 10 */
	nop
	li	$21, 10			/* max length of dev_qualifier */
	b	_ep0_idle_state_fini
	nop

___ep0_get_conf_desc:
	load_addr	$20, config_desc_fs	/* data pointer of FS mode */
	lbu	$8, 0x01($27)		/* read POWER */
	andi	$8, 0x10		/* test HS_MODE */
	beqz	$8, ___ep0_get_conf_desc2
	nop
	load_addr $20, config_desc_hs	/* data pointer of HS mode */

___ep0_get_conf_desc2:
	li	$22, 1			/* set EP0 to TX state */
	sub	$8, $21, 32
	blez	$8, _ep0_idle_state_fini /* wLength <= 32 */
	nop
	li	$21, 32			/* max length of config_desc */
	b	_ep0_idle_state_fini
	nop

___ep0_get_string_desc:
	li	$22, 1			/* set EP0 to TX state */

	srl	$9, $25, 16		/* wValue & 0xff */
	andi	$9, 0xff

	sub	$8, $9, 1
	beqz	$8, ___ep0_get_string_manufacture
	sub	$8, $9, 2
	beqz	$8, ___ep0_get_string_product
	nop

___ep0_get_string_lang_ids:
	load_addr	$20, string_lang_ids	/* data pointer */
	b	_ep0_idle_state_fini
	li	$21, 4			/* data length */

___ep0_get_string_manufacture:
	load_addr	$20, string_manufacture	/* data pointer */
	b	_ep0_idle_state_fini
	li	$21, 16			/* data length */

___ep0_get_string_product:
	load_addr	$20, string_product	/* data pointer */
	b	_ep0_idle_state_fini
	li	$21, 46			/* data length */

_ep0_idle_state_fini:
	li	$9, 0x40		/* SVDOUTPKTRDY */
	beqz	$23, _ep0_idle_state_fini2
	nop
	ori	$9, $9, 0x08		/* DATAEND */
_ep0_idle_state_fini2:
	sb	$9, 0x12($27)		/* CSR0 */
	beqz	$22, check_intr_ep1in
	nop

	/* 2.2 Handle EP0 TX state interrupt */
ep0_tx_state:
	sub	$9, $22, 1
	bnez	$9, check_intr_ep1in
	nop

	sub	$9, $21, 64		/* max packetsize */
	blez	$9, _ep0_tx_state2	/* data count <= 64 */
	ori	$19, $21, 0
	li	$19, 64

_ep0_tx_state2:
	beqz	$19, _ep0_tx_state3	/* send ZLP */
	ori	$18, $19, 0		/* record bytes to be transferred */
	sub	$21, $21, $19		/* decrement data count */

_ep0_fifo_write_loop:
	lbu	$9, 0($20)		/* read data */
	sb	$9, 0x20($27)		/* load FIFO */
	sub	$19, $19, 1		/* decrement counter */
	bnez	$19, _ep0_fifo_write_loop
	addi	$20, $20, 1		/* increment data pointer */

	sub	$9, $18, 64		/* max packetsize */
	beqz	$9, _ep0_tx_state4
	nop

_ep0_tx_state3:
	/* transferred bytes < max packetsize */
	li	$9, 0x0a		/* set INPKTRDY and DATAEND */
	sb	$9, 0x12($27)		/* CSR0 */
	li	$22, 0			/* set EP0 to IDLE state */
	b	check_intr_ep1in
	nop

_ep0_tx_state4:
	/* transferred bytes == max packetsize */
	li	$9, 0x02		/* set INPKTRDY */
	sb	$9, 0x12($27)		/* CSR0 */
	b	check_intr_ep1in
	nop

	/* 3. Check and handle EP1 BULK-IN interrupt */
check_intr_ep1in:
	andi	$9, $10, 0x2		/* check EP1 IN interrupt */
	beqz	$9, check_intr_ep1out
	nop

handle_epin1_intr:
	li	$9, 1
	sb	$9, 0x0e($27)		/* set INDEX 1 */
	lbu	$9, 0x12($27)		/* read INCSR */

	andi	$8, $9, 0x2		/* check INCSR_FFNOTEMPT */
	bnez	$8, _epin1_tx_state4
	nop

_epin1_write_fifo:
	lhu	$9, 0x10($27)		/* get INMAXP */
	sub	$8, $21, $9
	blez	$8, _epin1_tx_state1	/* bytes left <= INMAXP */
	ori	$19, $21, 0
	ori	$19, $9, 0

_epin1_tx_state1:
	beqz	$19, _epin1_tx_state4	/* No data */
	nop

	sub	$21, $21, $19		/* decrement data count */

	srl	$5, $19, 2		/* # of word */
	andi	$6, $19, 0x3		/* # of byte */
	beqz	$5, _epin1_tx_state2
	nop

_epin1_fifo_write_word:
	lw	$9, 0($20)		/* read data from source address */
	sw	$9, 0x24($27)		/* write FIFO */
	sub	$5, $5, 1		/* decrement counter */
	bnez	$5, _epin1_fifo_write_word
	addiu	$20, $20, 4		/* increment dest address */

_epin1_tx_state2:
	beqz	$6, _epin1_tx_state3
	nop

_epin1_fifo_write_byte:
	lbu	$9, 0($20)		/* read data from source address */
	sb	$9, 0x24($27)		/* write FIFO */
	sub	$6, $6, 1		/* decrement counter */
	bnez	$6, _epin1_fifo_write_byte
	addiu	$20, $20, 1		/* increment dest address */

_epin1_tx_state3:
	li	$9, 0x1
	sb	$9, 0x12($27)		/* INCSR, set INPKTRDY */

_epin1_tx_state4:
	/* 4. Check and handle EP1 BULK-OUT interrupt */
check_intr_ep1out:
	lhu	$9, 0x04($27)		/* read INTROUT */
	andi	$9, 0x2
	beqz	$9, check_status_next
	nop

handle_epout1_intr:
	li	$9, 1
	sb	$9, 0x0e($27)		/* set INDEX 1 */

	lbu	$9, 0x16($27)		/* read OUTCSR */
	andi	$9, 0x1			/* check OUTPKTRDY */
	beqz	$9, check_status_next
	nop

_epout1_read_fifo:
	lhu	$19, 0x18($27)		/* read OUTCOUNT */
	srl	$5, $19, 2		/* # of word */
	andi	$6, $19, 0x3		/* # of byte */
	beqz	$5, _epout1_rx_state1
	nop

_epout1_fifo_read_word:
	lw	$9, 0x24($27)		/* read FIFO */
	sw	$9, 0($20)		/* store to dest address */
	sub	$5, $5, 1		/* decrement counter */
	bnez	$5, _epout1_fifo_read_word
	addiu	$20, $20, 4		/* increment dest address */

_epout1_rx_state1:
	beqz	$6, _epout1_rx_state2
	nop

_epout1_fifo_read_byte:
	lbu	$9, 0x24($27)		/* read FIFO */
	sb	$9, 0($20)		/* store to dest address */
	sub	$6, $6, 1		/* decrement counter */
	bnez	$6, _epout1_fifo_read_byte
	addiu	$20, $20, 1		/* increment dest address */

_epout1_rx_state2:
	sb	$0, 0x16($27)		/* clear OUTPKTRDY */

check_status_next:
	b	usb_command_loop
	nop

/* Device/Configuration/Interface/Endpoint/String Descriptors */

	.align	2
device_desc:
	.byte	0x12		/* bLength */
	.byte	0x01		/* bDescriptorType */
	.byte	0x00		/* bcdUSB */
	.byte	0x02		/* bcdUSB */
	.byte	0x00		/* bDeviceClass */
	.byte	0x00		/* bDeviceSubClass */
	.byte	0x00		/* bDeviceProtocol */
	.byte	0x40		/* bMaxPacketSize0 */
	.byte	0x1a		/* idVendor */
	.byte	0x60		/* idVendor */
	.byte	0x40		/* idProduct */
	.byte	0x47		/* idProduct */
	.byte	0x00		/* bcdDevice */
	.byte	0x01		/* bcdDevice */
	.byte	0x01		/* iManufacturer */
	.byte	0x02		/* iProduct */
	.byte	0x00		/* iSerialNumber */
	.byte	0x01		/* bNumConfigurations */

	.align	2
dev_qualifier:
	.byte	0x0a		/* bLength */
	.byte	0x06		/* bDescriptorType */
	.byte	0x00		/* bcdUSB */
	.byte	0x02		/* bcdUSB */
	.byte	0x00		/* bDeviceClass */
	.byte	0x00		/* bDeviceSubClass */
	.byte	0x00		/* bDeviceProtocol */
	.byte	0x40		/* bMaxPacketSize0 */
	.byte	0x01		/* bNumConfigurations */
	.byte	0x00		/* bRESERVED */

	.align	2
config_desc_hs:
	.byte	0x09		/* bLength */
	.byte	0x02		/* bDescriptorType */
	.byte	0x20		/* wTotalLength */
	.byte	0x00		/* wTotalLength */
	.byte	0x01		/* bNumInterfaces */
	.byte	0x01		/* bConfigurationValue */
	.byte	0x00		/* iConfiguration */
	.byte	0xc0		/* bmAttributes */
	.byte	0x01		/* MaxPower */
intf_desc_hs:
	.byte	0x09		/* bLength */
	.byte	0x04		/* bDescriptorType */
	.byte	0x00		/* bInterfaceNumber */
	.byte	0x00		/* bAlternateSetting */
	.byte	0x02		/* bNumEndpoints */
	.byte	0xff		/* bInterfaceClass */
	.byte	0x00		/* bInterfaceSubClass */
	.byte	0x50		/* bInterfaceProtocol */
	.byte	0x00		/* iInterface */
ep1_desc_hs:
	.byte	0x07		/* bLength */
	.byte	0x05		/* bDescriptorType */
	.byte	0x01		/* bEndpointAddress */
	.byte	0x02		/* bmAttributes */
	.byte	0x00		/* wMaxPacketSize */
	.byte	0x02		/* wMaxPacketSize */
	.byte	0x00		/* bInterval */
ep2_desc_hs:
	.byte	0x07		/* bLength */
	.byte	0x05		/* bDescriptorType */
	.byte	0x81		/* bEndpointAddress */
	.byte	0x02		/* bmAttributes */
	.byte	0x00		/* wMaxPacketSize */
	.byte	0x02		/* wMaxPacketSize */
	.byte	0x00		/* bInterval */

	.align	2
config_desc_fs:
	.byte	0x09		/* bLength */
	.byte	0x02		/* bDescriptorType */
	.byte	0x20		/* wTotalLength */
	.byte	0x00		/* wTotalLength */
	.byte	0x01		/* bNumInterfaces */
	.byte	0x01		/* bConfigurationValue */
	.byte	0x00		/* iConfiguration */
	.byte	0xc0		/* bmAttributes */
	.byte	0x01		/* MaxPower */
intf_desc_fs:
	.byte	0x09		/* bLength */
	.byte	0x04		/* bDescriptorType */
	.byte	0x00		/* bInterfaceNumber */
	.byte	0x00		/* bAlternateSetting */
	.byte	0x02		/* bNumEndpoints */
	.byte	0xff		/* bInterfaceClass */
	.byte	0x00		/* bInterfaceSubClass */
	.byte	0x50		/* bInterfaceProtocol */
	.byte	0x00		/* iInterface */
ep1_desc_fs:
	.byte	0x07		/* bLength */
	.byte	0x05		/* bDescriptorType */
	.byte	0x01		/* bEndpointAddress */
	.byte	0x02		/* bmAttributes */
	.byte	0x40		/* wMaxPacketSize */
	.byte	0x00		/* wMaxPacketSize */
	.byte	0x00		/* bInterval */
ep2_desc_fs:
	.byte	0x07		/* bLength */
	.byte	0x05		/* bDescriptorType */
	.byte	0x81		/* bEndpointAddress */
	.byte	0x02		/* bmAttributes */
	.byte	0x40		/* wMaxPacketSize */
	.byte	0x00		/* wMaxPacketSize */
	.byte	0x00		/* bInterval */

	.align	2
string_lang_ids:
	.byte	0x04
	.byte	0x03
	.byte	0x09
	.byte	0x04

	.align	2
string_manufacture:
	.byte	0x10
	.byte	0x03
	.byte	0x49
	.byte	0x00
	.byte	0x6e
	.byte	0x00
	.byte	0x67
	.byte	0x00
	.byte	0x65
	.byte	0x00
	.byte	0x6e
	.byte	0x00
	.byte	0x69
	.byte	0x00
	.byte	0x63
	.byte	0x00

	.align	2
string_product:
	.byte	0x2e
	.byte	0x03
	.byte	0x4a
	.byte	0x00
	.byte	0x5a
	.byte	0x00
	.byte	0x34
	.byte	0x00
	.byte	0x37
	.byte	0x00
	.byte	0x34
	.byte	0x00
	.byte	0x30
	.byte	0x00
	.byte	0x20
	.byte	0x00
	.byte	0x55
	.byte	0x00
	.byte	0x53
	.byte	0x00
	.byte	0x42
	.byte	0x00
	.byte	0x20
	.byte	0x00
	.byte	0x42
	.byte	0x00
	.byte	0x6f
	.byte	0x00
	.byte	0x6f
	.byte	0x00
	.byte	0x74
	.byte	0x00
	.byte	0x20
	.byte	0x00
	.byte	0x44
	.byte	0x00
	.byte	0x65
	.byte	0x00
	.byte	0x76
	.byte	0x00
	.byte	0x69
	.byte	0x00
	.byte	0x63
	.byte	0x00
	.byte	0x65
	.byte	0x00

	.align	2
cpu_info_data:
	.byte	0x4a
	.byte	0x5a
	.byte	0x34
	.byte	0x37
	.byte	0x34
	.byte	0x30
	.byte	0x56
	.byte	0x31
usbboot_end:

    .set reorder

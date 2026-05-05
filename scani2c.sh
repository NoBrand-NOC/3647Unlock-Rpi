#!/bin/bash

BUS=1
echo "开始扫描 I2C bus $BUS 上的 PXE1610C 设备..."
echo

found=0

for addr in {0x08..0x77}; do
    # 1. 读 0xFD（必须是 0xB3）
    val_fd=$(i2cget -y $BUS $addr 0xFD 2>/dev/null)
    if [ "$val_fd" != "0xb3" ]; then
        continue
    fi

    # 2. 读 0x1A（必须是 0x00）
    val_1a=$(i2cget -y $BUS $addr 0x1A 2>/dev/null)
    if [ "$val_1a" != "0x00" ]; then
        continue
    fi

    # 3. 读 0x32（word，必须是 0x0415）
    val_32=$(i2cget -y $BUS $addr 0x32 w 2>/dev/null)
    if [ "$val_32" != "0x0415" ]; then
        continue
    fi

    echo "√ 找到 PXE1610C 设备：I2C 地址 = $addr"
    found=1
done

if [ $found -eq 0 ]; then
    echo "X 未在 bus $BUS 上找到 PXE1610C 设备。"
else
    echo
    echo "扫描完成。"
fi


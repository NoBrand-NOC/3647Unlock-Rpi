#!/bin/bash

BUS=1
ADDR=$1   # 例如 0x40

if [ -z "$ADDR" ]; then
    echo "用法: sudo ./pxe1610c_iccmax.sh 0x40"
    exit 1
fi

echo "正在操作 PXE1610C: I2C 地址 $ADDR (bus $BUS)"
echo

#############################################
# i2c 读写函数（i2ctransfer 版本）
#############################################

# i2c_write_page <page> <bytes...>
i2c_write_page() {
    PAGE=$1
    shift

    # 切换 page
    if [ $PAGE -ge 0 ]; then
        sudo i2ctransfer -y $BUS w2@$ADDR 0x00 $PAGE >/dev/null 2>&1 || return 1
    fi

    # 写数据块
    LEN=$#
    sudo i2ctransfer -y $BUS w$LEN@$ADDR "$@" >/dev/null 2>&1
    return $?
}

# i2c_read_page <page> <reg> <length>
i2c_read_page() {
    PAGE=$1
    REG=$2
    LEN=$3

    # 切换 page
    if [ $PAGE -ge 0 ]; then
        sudo i2ctransfer -y $BUS w2@$ADDR 0x00 $PAGE >/dev/null 2>&1 || echo "ERR" && return
    fi

    # 读 LEN 字节
    read_bytes=$(i2ctransfer -y $BUS w1@$ADDR $REG r$LEN 2>/dev/null)
    if [ $? -ne 0 ]; then echo "ERR"; return; fi

    echo $read_bytes
}

#############################################
# Step 1: Detect Device
#############################################

echo "[检测设备]"

fd=$(i2c_read_page 0 0xFD 1)
if [[ "$fd" != *"0xb3"* ]]; then
    echo "不是 PXE1610C (FD != B3)"
    exit 1
fi
echo " - Page00 cmdFD = B3 OK"

cmd1a=$(i2c_read_page 79 0x1A 1)
if [[ "$cmd1a" != *"0x00"* ]]; then
    echo "不是 PXE1610C (1A != 00)"
    exit 1
fi
echo " - Page4F cmd1A = 00 OK"

cmd32=$(i2c_read_page 79 0x32 2)
if [[ "$cmd32" != *"0x15 0x04"* ]]; then
    echo "不是 PXE1610C (32 != 0415)"
    exit 1
fi
echo " - Page4F cmd32 = 0415 OK"

echo "✔ PXE1610C 已确认"
echo

#############################################
# Step 2: Enter Programming Mode
#############################################

echo "[进入编程模式]"

i2c_write_page 63 39 124 179
if [ $? -ne 0 ]; then echo "进入编程模式失败"; exit 1; fi
echo " - 编程模式已开启 (cmd27)"
echo

#############################################
# Step 3: Read current ICC_MAX
#############################################

echo "[读取当前 ICC_MAX]"

icc_bytes=$(i2c_read_page 32 115 2)
if [[ "$icc_bytes" == "ERR" ]]; then
    echo "读取 ICC_MAX 失败"
    exit 1
fi

# 小端取低字节
iccmax=$((0x$(echo $icc_bytes | awk '{print $1}' | sed 's/0x//')))
echo " - 当前 ICC_MAX = $iccmax"

if [ $iccmax -eq 255 ]; then
    echo "✔ ICC_MAX 已经是最大(255)，无需修改"
    exit 0
fi

echo

#############################################
# Step 4: Set ICC_MAX = 255
#############################################

echo "[写入 ICC_MAX = 255]"

i2c_write_page 32 115 255 0
if [ $? -ne 0 ]; then echo "写入 ICC_MAX 失败"; exit 1; fi
echo " - 写入成功"
echo

#############################################
# Step 5: Verify ICC_MAX
#############################################

icc_bytes2=$(i2c_read_page 32 115 2)
iccnew=$((0x$(echo $icc_bytes2 | awk '{print $1}' | sed 's/0x//')))
echo " - 验证 ICC_MAX = $iccnew"

if [ $iccnew -ne 255 ]; then
    echo "验证失败：ICC_MAX != 255"
    exit 1
fi
echo "✔ ICC_MAX 修改成功"
echo

#############################################
# Step 6: Write verification command (page 63)
#############################################

echo "[写入校验命令]"

i2c_write_page 63 41 215 239 || { echo "失败"; exit 1; }
echo " - cmd29 D7 EF OK"

#############################################
# Step 7: Store Command (page 63)
#############################################

echo "[存储数据]"

i2c_write_page 63 52 || { echo "失败"; exit 1; }
echo " - cmd34 OK"

sleep 0.2
echo " - Store 完成"

#############################################
# Step 8: Exit programming mode
#############################################

echo "[退出编程模式]"

i2c_write_page 63 41 0 0 || { echo "失败"; exit 1; }
echo " - 编程模式已解除"
echo

echo "🎉 PXE1610C ICC_MAX 修改完成！"
exit 0


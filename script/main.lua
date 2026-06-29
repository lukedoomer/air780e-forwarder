PROJECT = "air780e_forwarder"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require "sys"
sysplus = require "sysplus"
require "sysplus"

-- 添加硬狗防止程序卡死, 在支持的设备上启用这个功能
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 设置 DNS
socket.setDNS(nil, 1, "168.95.1.1")
socket.setDNS(nil, 2, "1.1.1.1")

-- 设置 SIM 自动恢复(单位: 毫秒), 搜索小区信息间隔(单位: 毫秒), 最大搜索时间(单位: 秒)
mobile.setAuto(1000 * 10)

-- POWERKEY
local powerkey_timer = 0
gpio.setup(
    35,
    function()
        if gpio.get(35) == 0 then
            powerkey_timer = mcu.ticks()
        else
            if powerkey_timer == 0 then
                return
            end
            local time_diff = mcu.ticks() - powerkey_timer
            if time_diff > 2000 then
                log.debug("EVENT.POWERKEY_LONG_PRESS", time_diff)
                sys.publish("POWERKEY_LONG_PRESS", time_diff)
            else
                log.debug("EVENT.POWERKEY_SHORT_PRESS", time_diff)
                sys.publish("POWERKEY_SHORT_PRESS", time_diff)
            end
            powerkey_timer = 0
        end
    end,
    gpio.PULLUP
)

-- 加载模块
config = require "config"
util_http = require "util_http"
util_netled = require "util_netled"
util_mobile = require "util_mobile"
util_location = require "util_location"
util_notify = require "util_notify"

-- 短信接收回调
sms.setNewSmsCb(
    function(sender_number, sms_content, m)
        local time = string.format("%d/%02d/%02d %02d:%02d:%02d", m.year + 2000, m.mon, m.day, m.hour, m.min, m.sec)
        log.info("smsCallback", time, sender_number, sms_content)

        -- 短信控制
        local is_sms_ctrl = false
        local receiver_number, sms_content_to_be_sent = sms_content:match("^SMS,(+?%d+),(.+)$")
        receiver_number, sms_content_to_be_sent = receiver_number or "", sms_content_to_be_sent or ""
        if sms_content_to_be_sent ~= "" and receiver_number ~= "" and #receiver_number >= 5 and #receiver_number <= 20 then
            sms.send(receiver_number, sms_content_to_be_sent)
            is_sms_ctrl = true
        end

        -- 发送通知
        util_notify.send(
            {
                sms_content,
                "",
                "发件号码: " .. sender_number,
                "发件时间: " .. time,
                "#SMS" .. (is_sms_ctrl and " #CTRL" or "")
            }
        )
    end
)

sys.taskInit(
    function()
        -- 等待网络环境准备就绪
        sys.waitUntil("IP_READY")

        util_netled.init()

        -- 开机通知
        if config.BOOT_NOTIFY then
            util_notify.send("#BOOT")
        end

        -- 定时查询流量
        if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
            sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
        end

        -- 定时基站定位
        if config.LOCATION_INTERVAL and config.LOCATION_INTERVAL >= 1000 * 20 then
            sys.timerLoopStart(util_location.refresh, config.LOCATION_INTERVAL, 30)
        end

        -- 电源键短按发送测试通知
        sys.subscribe(
            "POWERKEY_SHORT_PRESS",
            function()
                util_notify.send("#ALIVE")
            end
        )
        -- 电源键长按查询流量
        sys.subscribe("POWERKEY_LONG_PRESS", util_mobile.queryTraffic)

        -- 关闭电源
        sys.wait(1000 * 5)
        pm.power(pm.USB, false) -- 关闭 usb 电源, 查看日志需注释掉
        pm.power(pm.GPS, false)
        pm.power(pm.GPS_ANT, false)
        if pm.DAC_EN then
            pm.power(pm.DAC_EN, false) -- 最新编译的固件才支持
        end

        -- 休眠
        sys.wait(1000 * 5)
        pm.force(pm.LIGHT)
    end
)

sys.run()

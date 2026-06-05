#!/bin/bash
# Fix conky font issue - use xfont instead

CONKYRC="/home/radioadmin/.conkyrc"

cat > "$CONKYRC" << 'CONKYEOF'
conky.config = {
    background = true,
    update_interval = 2,
    cpu_avg_samples = 2,
    double_buffer = true,
    no_buffers = true,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    alignment = 'top_right',
    gap_x = 20,
    gap_y = 40,
    minimum_width = 300,
    maximum_width = 300,
    default_color = '00BFFF',
    color1 = 'FFFFFF',
    color2 = 'AAAAAA',
    use_xft = false,
    font = 'fixed:size=10',
};

conky.text = [[
${color1}${font fixed:size=12:bold} RADIO VPS - CDELU${font}
${color2}${hr}
${color1}SISTEMA
${color2} Hostname: ${color}${alignr}${sysname} ${kernel}
${color2} Uptime:   ${color}${alignr}${uptime}
${color2} Procesos: ${color}${alignr}${processes} / ${running_processes}
${color2}
${color1}CPU
${color2} Uso:       ${color}${alignr}${cpu}%
${color2} Carga:     ${color}${alignr}${loadavg}
${color2}${cpugraph cpu0 30,290 00BFFF 0044FF}
${color2}
${color1}RAM
${color2} Usada:     ${color}${alignr}${mem} / ${memmax}
${color2} Porcentaje:${color}${alignr}${memperc}%
${color2}${membar 8,290}
${color2}
${color1}DISCO
${color2} Usado:     ${color}${alignr}${fs_used /} / ${fs_size /}
${color2} Porcentaje:${color}${alignr}${fs_used_perc /}%
${color2}${fs_bar 8,290 /}
${color2}
${color1}RED (eth0)
${color2} IP Publica: ${color}${alignr}${addr eth0}
${color2} Subida:    ${color}${alignr}${upspeed eth0}
${color2} Bajada:   ${color}${alignr}${downspeed eth0}
${color2} Total Sub: ${color}${alignr}${totalup eth0}
${color2} Total Baj: ${color}${alignr}${totaldown eth0}
${color2}
${color1}RADIO (puerto 3000)
${color2} Oyentes:   ${color}${alignr}${exec curl -s http://localhost:3000/status 2>/dev/null | grep -oP '"listeners":\K[0-9]+' || echo 'N/A'}
${color2} Estado:    ${color}${alignr}${exec pgrep -x node >/dev/null && echo 'ONLINE' || echo 'OFFLINE'}
${color1}${hr}
${color2}${alignc}${time %d/%m/%Y %H:%M:%S}
]];
CONKYEOF

chown radioadmin:radioadmin "$CONKYRC"

# kill and restart
killall conky 2>/dev/null
sleep 1
su - radioadmin -c 'export DISPLAY=:10 && conky -d'

echo "Done!"

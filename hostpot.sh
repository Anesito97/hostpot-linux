#!/bin/bash

# --- Configuración ---
HOTSPOT_NAME="LaptopAnesito"
HOTSPOT_PASS="12344330000"
HOTSPOT_CHANNEL="6"
HOTSPOT_IP="192.168.50.1"

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Verificación de Root ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}¡Error! Debes ejecutar esto con sudo.${NC}"
    exit 1
fi

SOURCE_IF=""
WIFI_IF=""

# --- Limpieza al salir ---
cleanup() {
    echo -e "\n${BLUE}--- Restaurando configuración de red... ---${NC}"
    killall hostapd >/dev/null 2>&1
    killall dnsmasq >/dev/null 2>&1
    
    if [ -n "$SOURCE_IF" ] && [ -n "$WIFI_IF" ]; then
        iptables -t nat -D POSTROUTING -o "$SOURCE_IF" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i "$WIFI_IF" -o "$SOURCE_IF" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -i "$SOURCE_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    fi

    if [ -n "$WIFI_IF" ]; then
        nmcli device set "$WIFI_IF" managed yes >/dev/null 2>&1
        ip link set "$WIFI_IF" down >/dev/null 2>&1
        ip addr flush dev "$WIFI_IF" >/dev/null 2>&1
        ip link set "$WIFI_IF" up >/dev/null 2>&1
    fi
    echo -e "${GREEN}✓ Internet restaurado.${NC}"
}
trap cleanup EXIT

# --- Funciones ---

check_internet() {
    echo -e "${BLUE}Probando conexión a internet...${NC}"
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Tienes internet.${NC}"
    else
        echo -e "${YELLOW}⚠ No detecto internet. El hotspot creará una red local sin salida.${NC}"
    fi
}

select_interfaces() {
    # 1. Selección de FUENTE (Internet)
    echo -e "\n${BOLD}Paso 1: ¿De dónde viene tu internet?${NC}"
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo\|vir\|docker\|waydroid"))
    local i=1
    
    for iface in "${interfaces[@]}"; do
        echo " $i) $iface"
        ((i++))
    done
    
    read -p "Elige número de interfaz con Internet: " sel_src
    if [[ "$sel_src" =~ ^[0-9]+$ ]] && [ "$sel_src" -le "${#interfaces[@]}" ]; then
        SOURCE_IF=${interfaces[$((sel_src-1))]}
    else
        echo -e "${RED}Selección inválida.${NC}"; exit 1
    fi
    echo -e "Internet: ${CYAN}$SOURCE_IF${NC}"

    # 2. Selección de WIFI (Emisor) - Búsqueda estricta
    echo -e "\n${BOLD}Paso 2: Buscando tarjeta WiFi real...${NC}"
    
    # Intentar desbloquear antes de buscar
    rfkill unblock wifi
    
    # Buscar solo interfaces inalámbricas reales
    local wifi_list=($(iw dev | awk '/Interface/ {print $2}'))
    
    if [ ${#wifi_list[@]} -eq 0 ]; then
        echo -e "${RED}❌ NO SE ENCONTRÓ NINGUNA TARJETA WIFI.${NC}"
        echo -e "${YELLOW}Posibles causas:${NC}"
        echo "1. Tu tarjeta está apagada por botón físico o teclado."
        echo "2. Falta el driver."
        echo "3. Necesitas reiniciar el PC."
        exit 1
    fi

    local j=1
    for wiface in "${wifi_list[@]}"; do
        echo " $j) $wiface"
        ((j++))
    done
    
    read -p "Elige número de tarjeta WiFi para el hotspot: " sel_wifi
    if [[ "$sel_wifi" =~ ^[0-9]+$ ]] && [ "$sel_wifi" -le "${#wifi_list[@]}" ]; then
        WIFI_IF=${wifi_list[$((sel_wifi-1))]}
    else
        echo -e "${RED}Selección inválida.${NC}"; exit 1
    fi

    if [ "$SOURCE_IF" == "$WIFI_IF" ]; then
        echo -e "${RED}Error: No puedes usar la misma tarjeta para recibir y emitir.${NC}"
        exit 1
    fi
    
    echo -e "Hotspot WiFi: ${CYAN}$WIFI_IF${NC}"
}

prepare_system() {
    echo -e "\n${BLUE}--- Configurando Hotspot ---${NC}"
    nmcli device set "$WIFI_IF" managed no
    ip link set "$WIFI_IF" down
    ip addr flush dev "$WIFI_IF"
    ip addr add $HOTSPOT_IP/24 dev "$WIFI_IF"
    ip link set "$WIFI_IF" up
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

configure_nat() {
    iptables -t nat -D POSTROUTING -o "$SOURCE_IF" -j MASQUERADE 2>/dev/null
    iptables -t nat -A POSTROUTING -o "$SOURCE_IF" -j MASQUERADE
    iptables -I FORWARD 1 -i "$SOURCE_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -I FORWARD 1 -i "$WIFI_IF" -o "$SOURCE_IF" -j ACCEPT
}

start_services() {
    killall dnsmasq >/dev/null 2>&1
    
    cat > /tmp/dnsmasq_hotspot.conf <<EOF
interface=$WIFI_IF
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,12h
dhcp-option=3,$HOTSPOT_IP
dhcp-option=6,8.8.8.8,1.1.1.1
server=8.8.8.8
server=1.1.1.1
domain-needed
bogus-priv
EOF

    cat > /tmp/hostapd_hotspot.conf <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=$HOTSPOT_NAME
hw_mode=g
channel=$HOTSPOT_CHANNEL
auth_algs=1
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

    echo -e "${YELLOW}Iniciando dnsmasq...${NC}"
    dnsmasq -C /tmp/dnsmasq_hotspot.conf

    echo -e "${GREEN}Iniciando Hostapd...${NC}"
    hostapd -B /tmp/hostapd_hotspot.conf > /tmp/hostapd.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Falló hostapd. Detalles:${NC}"
        cat /tmp/hostapd.log
        echo -e "\n${YELLOW}Intenta reiniciar tu PC si el error persiste.${NC}"
        exit 1
    fi
}

# --- Ejecución ---
clear
check_internet
select_interfaces
prepare_system
configure_nat
start_services

echo -e "\n${GREEN}${BOLD}=== HOTSPOT FUNCIONANDO ===${NC}"
echo -e "Red:  $HOTSPOT_NAME"
echo -e "Pass: $HOTSPOT_PASS"
echo -e "Presiona Enter para detener."
read -p ""
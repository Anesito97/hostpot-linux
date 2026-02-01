#!/bin/bash

# --- Configuración ---
HOTSPOT_NAME="LaptopAnesito"
HOTSPOT_PASS="12344330000"
HOTSPOT_CHANNEL="6"
HOTSPOT_IP="192.168.50.1"

# --- Paleta de Colores (Cyber Style) ---
R='\033[0;31m'    # Rojo
G='\033[0;32m'    # Verde
Y='\033[1;33m'    # Amarillo
B='\033[0;34m'    # Azul
C='\033[0;36m'    # Cyan
P='\033[0;35m'    # Púrpura
W='\033[1;37m'    # Blanco Brillante
NC='\033[0m'      # Reset

# --- Verificación de Root ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}✖ Error: Debes ejecutar esto con sudo.${NC}"
    exit 1
fi

SOURCE_IF=""
WIFI_IF=""

# --- Utilidades Visuales ---
banner() {
    clear
    echo -e "${C}"
    echo "  █  █ █▀▀█ ▀▀█▀▀ █▀▀█ █▀▀█ █▀▀█ ▀▀█▀▀ "
    echo "  █▄▄█ █  █   █   ▀▀▄▄ █▄▄█ █  █   █   "
    echo "  ▄▄▄█ ▀▀▀▀   ▀   ▀▀▀▀ █    ▀▀▀▀   ▀   "
    echo -e "${NC}      ${P}»» SYSTEM CONTROLLER v2.0 ««${NC}"
    echo -e "${B}----------------------------------------${NC}"
}

print_status() {
    local msg="$1"
    local status="$2" # 0=OK, 1=FAIL, 2=WARN
    
    # Calcular espacios para alinear a la derecha
    local term_width=60
    local msg_len=${#msg}
    local spaces=$((term_width - msg_len))
    
    echo -n -e "${W}$msg${NC}"
    for ((i=0; i<spaces; i++)); do echo -n "."; done
    
    if [ "$status" -eq 0 ]; then
        echo -e " [ ${G}OK${NC} ]"
    elif [ "$status" -eq 1 ]; then
        echo -e " [${R}FAIL${NC}]"
    else
        echo -e " [${Y}WARN${NC}]"
    fi
}

spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- Limpieza al salir ---
cleanup() {
    echo ""
    echo -e "${B}┌──────────────────────────────────────┐${NC}"
    echo -e "${B}│${NC}      ${R}DETENIENDO SERVICIOS...${NC}         ${B}│${NC}"
    echo -e "${B}└──────────────────────────────────────┘${NC}"
    
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
    print_status "Restaurando NetworkManager" 0
    print_status "Limpiando reglas IPTables" 0
    echo -e "\n${G}✓ Sistema restaurado y listo.${NC}"
}
trap cleanup EXIT

# --- Funciones ---

check_internet() {
    echo -n -e "${C}Probando conectividad...${NC}"
    ping -c 1 8.8.8.8 >/dev/null 2>&1 &
    spinner
    if [ $? -eq 0 ]; then
        print_status "Conexión a Internet" 0
    else
        print_status "Conexión a Internet" 2
        echo -e "${Y}  (Se creará una red local sin salida)${NC}"
    fi
}

select_interfaces() {
    banner
    check_internet
    echo ""
    echo -e "${P}█ PASO 1: Fuente de Internet${NC}"
    
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo\|vir\|docker\|waydroid"))
    local i=1
    
    echo -e "${B}┌───┬─────────────────────────┐${NC}"
    for iface in "${interfaces[@]}"; do
        printf "${B}│${NC} ${C}%d${NC} ${B}│${NC} %-23s ${B}│${NC}\n" "$i" "$iface"
        ((i++))
    done
    echo -e "${B}└───┴─────────────────────────┘${NC}"
    
    echo -n -e "${W}Selecciona interfaz [1-${#interfaces[@]}]: ${NC}"
    read sel_src
    
    if [[ "$sel_src" =~ ^[0-9]+$ ]] && [ "$sel_src" -le "${#interfaces[@]}" ]; then
        SOURCE_IF=${interfaces[$((sel_src-1))]}
    else
        echo -e "${R}Selección inválida.${NC}"; exit 1
    fi

    echo ""
    echo -e "${P}█ PASO 2: Tarjeta Emisora (WiFi)${NC}"
    rfkill unblock wifi >/dev/null 2>&1
    local wifi_list=($(iw dev | awk '/Interface/ {print $2}'))
    
    if [ ${#wifi_list[@]} -eq 0 ]; then
        print_status "Buscando WiFi" 1
        echo -e "${R}❌ FATAL: No hay tarjeta WiFi disponible.${NC}"
        exit 1
    fi

    local j=1
    echo -e "${B}┌───┬─────────────────────────┐${NC}"
    for wiface in "${wifi_list[@]}"; do
        printf "${B}│${NC} ${C}%d${NC} ${B}│${NC} %-23s ${B}│${NC}\n" "$j" "$wiface"
        ((j++))
    done
    echo -e "${B}└───┴─────────────────────────┘${NC}"
    
    echo -n -e "${W}Selecciona WiFi [1-${#wifi_list[@]}]: ${NC}"
    read sel_wifi
    
    if [[ "$sel_wifi" =~ ^[0-9]+$ ]] && [ "$sel_wifi" -le "${#wifi_list[@]}" ]; then
        WIFI_IF=${wifi_list[$((sel_wifi-1))]}
    else
        echo -e "${R}Selección inválida.${NC}"; exit 1
    fi
}

start_sequence() {
    banner
    echo -e "${P}>>> INICIANDO PROTOCOLOS DE RED <<<${NC}\n"

    # Preparar WiFi
    nmcli device set "$WIFI_IF" managed no >/dev/null 2>&1
    ip link set "$WIFI_IF" down
    ip addr flush dev "$WIFI_IF"
    ip addr add $HOTSPOT_IP/24 dev "$WIFI_IF"
    ip link set "$WIFI_IF" up
    print_status "Configurando Interfaz $WIFI_IF" 0
    
    # Forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    print_status "Habilitando IP Forwarding" 0

    # Firewall
    iptables -t nat -D POSTROUTING -o "$SOURCE_IF" -j MASQUERADE 2>/dev/null
    iptables -t nat -A POSTROUTING -o "$SOURCE_IF" -j MASQUERADE
    iptables -I FORWARD 1 -i "$SOURCE_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -I FORWARD 1 -i "$WIFI_IF" -o "$SOURCE_IF" -j ACCEPT
    print_status "Aplicando reglas NAT/Firewall" 0
    
    # Configurar Archivos
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

    # Iniciar Servicios con Spinner
    echo -n -e "${W}Iniciando servidor DHCP (dnsmasq)...${NC}"
    dnsmasq -C /tmp/dnsmasq_hotspot.conf &
    spinner
    if [ $? -eq 0 ]; then print_status "Servicio DHCP" 0; else print_status "Servicio DHCP" 1; exit 1; fi

    echo -n -e "${W}Levantando Access Point (hostapd)...${NC}"
    hostapd -B /tmp/hostapd_hotspot.conf > /tmp/hostapd.log 2>&1 &
    spinner
    
    # Verificación final
    if pgrep hostapd > /dev/null; then
         print_status "Punto de Acceso WiFi" 0
    else 
         print_status "Punto de Acceso WiFi" 1
         echo -e "\n${R}Detalles del error:${NC}"
         cat /tmp/hostapd.log
         exit 1
    fi
}

show_dashboard() {
    clear
    echo -e "${G}"
    echo "   █▄▄ █▀▀█ █▀▀█ █▀▀█ █▀▀▄ █▀▀ █▀▀█ █▀▀ ▀▀█▀▀ "
    echo "   █▄█ █▄▄▀ █  █ █▄▄█ █  █ █   █▄▄█ ▀▀█   █   "
    echo "   ▀▀▀ ▀ ▀▀ ▀▀▀▀ ▀  ▀ ▀▀▀  ▀▀▀ ▀  ▀ ▀▀▀   ▀   "
    echo -e "${NC}"
    echo -e "${B}╔════════════════════════════════════════════╗${NC}"
    echo -e "${B}║${NC} ${C}ESTADO:${NC} ${G}● EN LÍNEA${NC}                         ${B}║${NC}"
    echo -e "${B}╠════════════════════════════════════════════╣${NC}"
    printf "${B}║${NC} ${W}%-15s${NC} : ${C}%-22s${NC} ${B}║${NC}\n" "SSID Name" "$HOTSPOT_NAME"
    printf "${B}║${NC} ${W}%-15s${NC} : ${C}%-22s${NC} ${B}║${NC}\n" "Password" "$HOTSPOT_PASS"
    printf "${B}║${NC} ${W}%-15s${NC} : ${C}%-22s${NC} ${B}║${NC}\n" "Gateway IP" "$HOTSPOT_IP"
    printf "${B}║${NC} ${W}%-15s${NC} : ${C}%-22s${NC} ${B}║${NC}\n" "Interface" "$WIFI_IF"
    echo -e "${B}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " ${W}Mantén esta ventana abierta.${NC}"
    echo -e " ${W}Para gestionar usuarios, abre una nueva terminal y ejecuta:${NC}"
    echo -e " ${Y}sudo ./gestor-hotspot.sh $WIFI_IF${NC}"
    echo ""
    echo -e " ${R}[ Presiona ENTER para APAGAR el Hotspot ]${NC}"
    read -p ""
}

# --- Ejecución ---
select_interfaces
start_sequence
show_dashboard
#!/bin/bash

# Configuración
HOTSPOT_NAME="LinuxHotspot"
HOTSPOT_PASS="linux1234"
HOTSPOT_CHANNEL="6"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Verificar si el script se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Este script debe ejecutarse como root${NC}"
    exit 1
fi

# Función para obtener la interfaz con internet
get_internet_interface() {
    # Buscar la interfaz con la ruta por defecto
    local default_if=$(ip route show default 2>/dev/null | awk '/default/ {print $5}')
    
    # Verificar si la interfaz tiene conectividad
    if [ -n "$default_if" ] && ping -c 1 -I $default_if 8.8.8.8 >/dev/null 2>&1; then
        echo "$default_if"
    else
        echo ""
    fi
}

# Función para verificar conexión a internet
check_internet() {
    echo -e "${BLUE}Verificando conexión a internet...${NC}"
    
    if [ -n "$(get_internet_interface)" ]; then
        echo -e "${GREEN}✓ Hay conexión a internet${NC}"
        return 0
    else
        echo -e "${RED}✗ No se detectó conexión a internet${NC}"
        return 1
    fi
}

# Función para listar interfaces de red
list_interfaces() {
    local internet_if=$(get_internet_interface)
    echo -e "${BLUE}Interfaces de red disponibles:${NC}"
    interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
    
    for i in "${!interfaces[@]}"; do
        if [ "${interfaces[$i]}" == "$internet_if" ]; then
            echo -e "$((i+1)). ${GREEN}${interfaces[$i]} (*)${NC} ${CYAN}(Tiene conexión a internet)${NC}"
        else
            echo "$((i+1)). ${interfaces[$i]}"
        fi
    done
    
    echo -n -e "${YELLOW}Selecciona el número de la interfaz con internet (1-${#interfaces[@]}): ${NC}"
    read source_num
    
    if [[ $source_num -lt 1 || $source_num -gt ${#interfaces[@]} ]]; then
        echo -e "${RED}Selección inválida${NC}"
        exit 1
    fi
    
    SOURCE_IF=${interfaces[$((source_num-1))]}
    echo -e "${GREEN}Interfaz seleccionada: ${SOURCE_IF}${NC}"
}

# Función para seleccionar interfaz WiFi para hotspot
select_wifi_interface() {
    echo -e "${BLUE}Buscando interfaces WiFi...${NC}"
    wifi_interfaces=($(iw dev | awk '/Interface/ {print $2}'))
    
    if [ ${#wifi_interfaces[@]} -eq 0 ]; then
        echo -e "${RED}No se encontraron interfaces WiFi${NC}"
        exit 1
    fi
    
    for i in "${!wifi_interfaces[@]}"; do
        echo "$((i+1)). ${wifi_interfaces[$i]}"
    done
    
    echo -n -e "${YELLOW}Selecciona el número de la interfaz WiFi para el hotspot (1-${#wifi_interfaces[@]}): ${NC}"
    read wifi_num
    
    if [[ $wifi_num -lt 1 || $wifi_num -gt ${#wifi_interfaces[@]} ]]; then
        echo -e "${RED}Selección inválida${NC}"
        exit 1
    fi
    
    WIFI_IF=${wifi_interfaces[$((wifi_num-1))]}
    echo -e "${GREEN}Interfaz WiFi seleccionada: ${WIFI_IF}${NC}"
}

# Función para iniciar el hotspot
start_hotspot() {
    echo -e "${BLUE}Configurando hotspot...${NC}"
    
    # Detener servicios que podrían interferir
    systemctl stop hostapd >/dev/null 2>&1
    systemctl stop dnsmasq >/dev/null 2>&1
    systemctl stop systemd-resolved >/dev/null 2>&1
    
    # Liberar la dirección IP de la interfaz WiFi
    dhclient -r $WIFI_IF >/dev/null 2>&1
    
    # Configurar NAT
    echo -e "${YELLOW}Configurando NAT...${NC}"
    iptables -t nat -F
    iptables -t nat -A POSTROUTING -o $SOURCE_IF -j MASQUERADE
    iptables -A FORWARD -i $WIFI_IF -o $SOURCE_IF -j ACCEPT
    iptables -A FORWARD -i $SOURCE_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Configurar dnsmasq (con más opciones)
    echo -e "${YELLOW}Configurando dnsmasq...${NC}"
    cat > /etc/dnsmasq.conf <<EOF
interface=$WIFI_IF
dhcp-range=192.168.100.2,192.168.100.254,255.255.255.0,24h
dhcp-option=3,192.168.100.1
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
no-resolv
EOF
    
    # Configurar hostapd (igual que antes)
    echo -e "${YELLOW}Configurando hostapd...${NC}"
    cat > /etc/hostapd.conf <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=$HOTSPOT_NAME
hw_mode=g
channel=$HOTSPOT_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    
    # Asignar dirección IP a la interfaz WiFi
    echo -e "${YELLOW}Configurando dirección IP...${NC}"
    ip addr flush dev $WIFI_IF
    ip addr add 192.168.100.1/24 dev $WIFI_IF
    ip link set $WIFI_IF up
    
    # Iniciar servicios en el orden correcto
    echo -e "${YELLOW}Iniciando servicios...${NC}"
    systemctl restart dnsmasq
    hostapd -B /etc/hostapd.conf >/dev/null 2>&1
    
    # Habilitar el forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    echo -e "${GREEN}✓ Hotspot iniciado correctamente${NC}"
    echo -e "${BLUE}Nombre del hotspot: ${HOTSPOT_NAME}${NC}"
    echo -e "${BLUE}Contraseña: ${HOTSPOT_PASS}${NC}"
    
    # Mostrar información de conexión
    echo -e "\n${CYAN}Para solucionar problemas:${NC}"
    echo -e "1. Verifica que $SOURCE_IF tiene internet: ping -c 3 google.com"
    echo -e "2. Verifica NAT: sudo iptables -t nat -L -n -v"
    echo -e "3. Prueba DNS: dig @192.168.100.1 google.com"
}

# Función para detener el hotspot
stop_hotspot() {
    echo -e "${BLUE}Deteniendo hotspot...${NC}"
    
    # Detener procesos
    killall hostapd >/dev/null 2>&1
    systemctl stop dnsmasq >/dev/null 2>&1
    
    # Limpiar iptables
    iptables -t nat -D POSTROUTING -o $SOURCE_IF -j MASQUERADE
    iptables -D FORWARD -i $WIFI_IF -o $SOURCE_IF -j ACCEPT
    iptables -D FORWARD -i $SOURCE_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Reiniciar interfaz WiFi
    ip addr flush dev $WIFI_IF
    ip link set $WIFI_IF down
    ip link set $WIFI_IF up
    
    echo -e "${GREEN}✓ Hotspot detenido correctamente${NC}"
}

# Función para mostrar clientes conectados
show_clients() {
    echo -e "${BLUE}Clientes conectados:${NC}"
    
    # Intentar varios métodos para mostrar clientes
    if command -v ip >/dev/null 2>&1; then
        ip neigh show dev $WIFI_IF | grep -v FAILED
    elif command -v arp >/dev/null 2>&1; then
        arp -i $WIFI_IF | grep -v incomplete
    else
        echo -e "${RED}No se encontró ni 'ip' ni 'arp' en el sistema${NC}"
        echo -e "${YELLOW}Instala net-tools o iproute2 para ver los clientes conectados${NC}"
    fi
    
    # Mostrar también información de dnsmasq leases
    if [ -f "/var/lib/misc/dnsmasq.leases" ]; then
        echo -e "\n${BLUE}Direcciones asignadas por dnsmasq:${NC}"
        cat /var/lib/misc/dnsmasq.leases
    fi
}

# Menú principal
main_menu() {
    clear
    echo -e "${BLUE}=== Menú Hotspot WiFi ===${NC}"
    echo -e "1. Iniciar hotspot"
    echo -e "2. Detener hotspot"
    echo -e "3. Reiniciar hotspot"
    echo -e "4. Ver clientes conectados"
    echo -e "5. Salir"
    echo -n -e "${YELLOW}Selecciona una opción (1-5): ${NC}"
    read option
    
    case $option in
        1)
            check_internet
            list_interfaces
            select_wifi_interface
            start_hotspot
            ;;
        2)
            stop_hotspot
            ;;
        3)
            stop_hotspot
            sleep 2
            start_hotspot
            ;;
        4)
            show_clients
            ;;
        5)
            echo -e "${GREEN}Saliendo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
    
    read -p "Presiona Enter para continuar..."
    main_menu
}

# Iniciar el menú principal
main_menu
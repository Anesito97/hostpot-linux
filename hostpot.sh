#!/bin/bash

# --- Configuración ---
HOTSPOT_NAME="LaptopAnesito"
HOTSPOT_PASS="12344330000"
HOTSPOT_CHANNEL="6"

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Variables Globales ---
SOURCE_IF=""
WIFI_IF=""
IP_FORWARD_ORIGINAL=""

# --- Verificación de Root ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Este script debe ejecutarse como root.${NC}"
    exit 1
fi

# --- Verificación de Dependencias ---
check_dependencies() {
    echo -e "${BLUE}Verificando dependencias...${NC}"
    local missing=0
    for cmd in ip iw iptables hostapd dnsmasq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}✗ Comando no encontrado: $cmd${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo -e "${YELLOW}Por favor, instala los paquetes faltantes. En Ubuntu/Debian:${NC}"
        echo "sudo apt update && sudo apt install hostapd dnsmasq net-tools iw iproute2 iptables"
        exit 1
    fi
    echo -e "${GREEN}✓ Todas las dependencias están instaladas.${NC}"
}

# --- Función de Limpieza ---
# Se ejecuta al salir del script para restaurar todo
cleanup() {
    echo -e "\n${BLUE}Ejecutando limpieza antes de salir...${NC}"
    
    # Detener servicios
    killall hostapd >/dev/null 2>&1
    systemctl stop dnsmasq >/dev/null 2>&1
    
    # Limpiar iptables solo si las variables están definidas
    if [ -n "$SOURCE_IF" ] && [ -n "$WIFI_IF" ]; then
        iptables -t nat -D POSTROUTING -o "$SOURCE_IF" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i "$WIFI_IF" -o "$SOURCE_IF" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -i "$SOURCE_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    fi
    
    # Restaurar ip_forward
    if [ -n "$IP_FORWARD_ORIGINAL" ]; then
        echo -e "${YELLOW}Restaurando ip_forward a su estado original ($IP_FORWARD_ORIGINAL)...${NC}"
        echo "$IP_FORWARD_ORIGINAL" > /proc/sys/net/ipv4/ip_forward
    fi
    
    # Reiniciar la interfaz WiFi a su estado normal
    if [ -n "$WIFI_IF" ]; then
        ip addr flush dev "$WIFI_IF" >/dev/null 2>&1
        ip link set "$WIFI_IF" down >/dev/null 2>&1
        ip link set "$WIFI_IF" up >/dev/null 2>&1
    fi
    
    # <<< MEJORA CRÍTICA: Reiniciar el servicio de DNS de Ubuntu >>>
    echo -e "${YELLOW}Reiniciando el servicio DNS del sistema (systemd-resolved)...${NC}"
    systemctl restart systemd-resolved
    
    echo -e "${GREEN}✓ Limpieza completada. El sistema ha sido restaurado.${NC}"
}

# <<< MEJORA: Atrapar la salida (Ctrl+C) para ejecutar la limpieza >>>
trap cleanup EXIT

# --- Funciones del Menú ---

get_internet_interface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5}'
}

list_interfaces() {
    local internet_if=$(get_internet_interface)
    echo -e "${BLUE}Interfaces de red disponibles:${NC}"
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
    
    for i in "${!interfaces[@]}"; do
        if [ "${interfaces[$i]}" == "$internet_if" ]; then
            echo -e "$((i+1)). ${GREEN}${interfaces[$i]} (*)${NC} ${CYAN}(Tiene conexión a internet)${NC}"
        else
            echo "$((i+1)). ${interfaces[$i]}"
        fi
    done
    
    read -p "Selecciona el número de la interfaz con internet (1-${#interfaces[@]}): " source_num
    
    if [[ ! "$source_num" =~ ^[0-9]+$ ]] || [[ $source_num -lt 1 || $source_num -gt ${#interfaces[@]} ]]; then
        echo -e "${RED}Selección inválida${NC}"; exit 1
    fi
    
    SOURCE_IF=${interfaces[$((source_num-1))]}
    echo -e "${GREEN}Interfaz con internet seleccionada: ${SOURCE_IF}${NC}"
}

select_wifi_interface() {
    echo -e "${BLUE}Buscando interfaces WiFi...${NC}"
    local wifi_interfaces=($(iw dev | awk '/Interface/ {print $2}'))
    
    if [ ${#wifi_interfaces[@]} -eq 0 ]; then
        echo -e "${RED}No se encontraron interfaces WiFi.${NC}"; exit 1
    fi
    
    echo "Interfaces WiFi disponibles:"
    for i in "${!wifi_interfaces[@]}"; do echo "$((i+1)). ${wifi_interfaces[$i]}"; done
    
    read -p "Selecciona el número de la interfaz WiFi para el hotspot (1-${#wifi_interfaces[@]}): " wifi_num
    
    if [[ ! "$wifi_num" =~ ^[0-9]+$ ]] || [[ $wifi_num -lt 1 || $wifi_num -gt ${#wifi_interfaces[@]} ]]; then
        echo -e "${RED}Selección inválida${NC}"; exit 1
    fi
    
    WIFI_IF=${wifi_interfaces[$((wifi_num-1))]}
    echo -e "${GREEN}Interfaz WiFi para hotspot: ${WIFI_IF}${NC}"
}

start_hotspot() {
    list_interfaces
    select_wifi_interface

    echo -e "${BLUE}Configurando hotspot...${NC}"
    
    # <<< MEJORA: Detener servicios que interfieren de forma más segura >>>
    systemctl stop hostapd >/dev/null 2>&1
    systemctl stop dnsmasq >/dev/null 2>&1
    # <<< MEJORA CRÍTICA: Detenemos resolved, pero la función cleanup LO RESTAURARÁ >>>
    systemctl stop systemd-resolved >/dev/null 2>&1

    # <<< MEJORA: Guardar estado original de ip_forward >>>
    IP_FORWARD_ORIGINAL=$(cat /proc/sys/net/ipv4/ip_forward)
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # <<< MEJORA: Limpiar reglas previas de forma más segura >>>
    iptables -t nat -F
    iptables -F FORWARD

    # Configurar NAT
    echo -e "${YELLOW}Configurando NAT...${NC}"
    iptables -t nat -A POSTROUTING -o "$SOURCE_IF" -j MASQUERADE
    iptables -A FORWARD -i "$WIFI_IF" -o "$SOURCE_IF" -j ACCEPT
    iptables -A FORWARD -i "$SOURCE_IF" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Configurar la IP de la interfaz WiFi
    echo -e "${YELLOW}Configurando dirección IP para $WIFI_IF...${NC}"
    ip addr flush dev "$WIFI_IF"
    ip addr add 192.168.100.1/24 dev "$WIFI_IF"
    ip link set "$WIFI_IF" up

    # Configurar dnsmasq
    echo -e "${YELLOW}Configurando dnsmasq...${NC}"
    cat > /etc/dnsmasq.conf <<EOF
interface=$WIFI_IF
dhcp-range=192.168.100.10,192.168.100.100,255.255.255.0,12h
dhcp-option=3,192.168.100.1
dhcp-option=6,192.168.100.1 # Usar el hotspot como DNS
server=8.8.8.8
server=1.1.1.1
no-resolv
EOF

    # Configurar hostapd
    echo -e "${YELLOW}Configurando hostapd...${NC}"
    cat > /etc/hostapd.conf <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=$HOTSPOT_NAME
hw_mode=g
channel=$HOTSPOT_CHANNEL
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
    
    # Iniciar servicios
    echo -e "${YELLOW}Iniciando servicios...${NC}"
    systemctl restart dnsmasq
    hostapd -B /etc/hostapd.conf

    echo -e "${GREEN}✓ Hotspot iniciado correctamente${NC}"
    echo -e "${BLUE}Nombre: ${CYAN}$HOTSPOT_NAME${NC}"
    echo -e "${BLUE}Contraseña: ${CYAN}$HOTSPOT_PASS${NC}"
}

# <<< MEJORA: stop_hotspot ahora solo llama a la función de limpieza y sale >>>
stop_hotspot() {
    echo -e "${BLUE}Deteniendo hotspot...${NC}"
    exit 0 # El 'trap' se encargará de llamar a cleanup()
}

show_clients() {
    if [ -z "$WIFI_IF" ]; then
        echo -e "${RED}El hotspot no está iniciado. No se puede determinar la interfaz.${NC}"
        return
    fi
    echo -e "${BLUE}Clientes conectados (Interfaz: $WIFI_IF):${NC}"
    echo -e "${CYAN}--- Leases de Dnsmasq (IP, MAC, Nombre) ---${NC}"
    cat /var/lib/misc/dnsmasq.leases | awk '{print "IP:", $3, " \tMAC:", $2, "\tNombre:", $4}'
    echo -e "\n${CYAN}--- Tabla de vecinos (ARP) ---${NC}"
    ip neigh show dev "$WIFI_IF" | grep -v FAILED
}

# Menú principal
main_menu() {
    clear
    check_dependencies
    echo -e "${BLUE}=== Menú Hotspot WiFi (Mejorado) ===${NC}"
    echo -e "1. Iniciar hotspot"
    echo -e "2. Detener hotspot"
    echo -e "3. Ver clientes conectados"
    echo -e "4. Gestión de dispositivos conectados"
    echo -e "5. Salir"
    echo -n -e "${YELLOW}Selecciona una opción (1-5): ${NC}"
    read -r option
    
    case $option in
        1)
            start_hotspot
            ;;
        2)
            stop_hotspot
            ;;
        3)
            show_clients
            ;;
        4) 
            if [ -z "$WIFI_IF" ]; then
                echo -e "${RED}El hotspot debe estar iniciado para gestionar dispositivos.${NC}"
            else
                # <<< MEJORA: Pasar la interfaz como argumento >>>
                ./gestor-hotspot.sh "$WIFI_IF"
            fi
            ;;
        5)
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
    
    echo ""
    read -p "Presiona Enter para continuar..."
    main_menu
}

# Iniciar el menú principal
main_menu
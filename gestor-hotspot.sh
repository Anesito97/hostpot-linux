#!/bin/bash

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Validación de Entrada ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Requiere permisos de root.${NC}"
    exit 1
fi

WIFI_IF="$1"
if [ -z "$WIFI_IF" ]; then
    echo -e "${RED}Error: Este script debe ser llamado desde el script principal.${NC}"
    exit 1
fi

# --- Funciones ---

header() {
    clear
    echo -e "${BLUE}${BOLD}=== GESTOR DE DISPOSITIVOS ($WIFI_IF) ===${NC}"
}

listar_clientes() {
    header
    echo -e "${CYAN}Dispositivos DHCP (Leases):${NC}"
    if [ -f "/var/lib/misc/dnsmasq.leases" ]; then
        awk '{print "IP: " $3 " | MAC: " $2 " | Nombre: " $4}' /var/lib/misc/dnsmasq.leases
    else
        echo "No hay leases DHCP activos."
    fi
    echo -e "\n${CYAN}Dispositivos Activos (ARP):${NC}"
    ip neigh show dev "$WIFI_IF" | grep -v "FAILED"
}

limitar_velocidad() {
    listar_clientes
    echo -e "\n${YELLOW}--- Limitar Ancho de Banda ---${NC}"
    read -p "IP del dispositivo: " ip
    read -p "Velocidad (ej: 500kbit, 2mbit): " vel
    
    if [[ -z "$ip" || -z "$vel" ]]; then return; fi
    
    # Asegurar que tc está limpio
    tc qdisc del dev "$WIFI_IF" root >/dev/null 2>&1
    
    # Configuración HTB
    tc qdisc add dev "$WIFI_IF" root handle 1: htb default 10
    tc class add dev "$WIFI_IF" parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev "$WIFI_IF" parent 1:1 classid 1:10 htb rate 1000mbit # Default rápido
    tc class add dev "$WIFI_IF" parent 1:1 classid 1:11 htb rate "$vel" # Clase lenta
    
    # Filtro
    tc filter add dev "$WIFI_IF" protocol ip parent 1:0 prio 1 u32 match ip dst "$ip" flowid 1:11
    
    echo -e "${GREEN}✓ Límite de $vel aplicado a $ip.${NC}"
    read -p "Enter para continuar..."
}

bloquear_mac() {
    listar_clientes
    echo -e "\n${RED}--- Bloquear Dispositivo (Blacklist) ---${NC}"
    read -p "MAC a bloquear (XX:XX:XX:XX:XX:XX): " mac
    
    if [ -z "$mac" ]; then return; fi
    
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
    # Desconectar si está conectado
    hostapd_cli -i "$WIFI_IF" deauthenticate "$mac" >/dev/null 2>&1
    
    echo -e "${GREEN}✓ MAC $mac bloqueada y desconectada.${NC}"
    read -p "Enter para continuar..."
}

desbloquear_mac() {
    header
    echo -e "${CYAN}Dispositivos Bloqueados actualmente:${NC}"
    iptables -L FORWARD -v -n | grep "MAC"
    
    echo -e "\n${GREEN}--- Desbloquear Dispositivo ---${NC}"
    read -p "MAC a desbloquear: " mac
    
    if [ -z "$mac" ]; then return; fi
    
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Dispositivo desbloqueado.${NC}"
    else
        echo -e "${RED}✗ Esa MAC no estaba bloqueada.${NC}"
    fi
    read -p "Enter para continuar..."
}

# --- Menú del Gestor ---
while true; do
    header
    echo "1. Listar dispositivos"
    echo "2. Limitar velocidad (Traffic Shaping)"
    echo "3. Bloquear acceso (MAC Address)"
    echo "4. Desbloquear acceso"
    echo "5. Volver al Hotspot"
    
    read -p "Opción: " op
    case $op in
        1) listar_clientes; read -p "" ;;
        2) limitar_velocidad ;;
        3) bloquear_mac ;;
        4) desbloquear_mac ;;
        5) exit 0 ;;
        *) ;;
    esac
done
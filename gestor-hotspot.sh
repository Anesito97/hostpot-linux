#!/bin/bash

# --- Configuración Visual ---
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}Error: Requiere sudo.${NC}"
    exit 1
fi

WIFI_IF="$1"
if [ -z "$WIFI_IF" ]; then
    echo -e "${R}Uso: sudo ./gestor-hotspot.sh <interfaz_wifi>${NC}"
    exit 1
fi

# --- Funciones Visuales ---

header() {
    clear
    echo -e "${C}"
    echo "   █▀▀ █▀▀ █▀▀ ▀▀█▀▀ █▀▀█ █▀▀█ "
    echo "   █ █ █▀▀ ▀▀█   █   █  █ █▄▄▀ "
    echo "   ▀▀▀ ▀▀▀ ▀▀▀   ▀   ▀▀▀▀ ▀ ▀▀ "
    echo -e "${NC}   --- CONTROL CENTER : ${Y}$WIFI_IF${NC} ---"
    echo -e "${B}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
}

print_row() {
    printf "${B}│${NC} %-16s ${B}│${NC} %-17s ${B}│${NC} %-15s ${B}│${NC}\n" "$1" "$2" "$3"
}

listar_clientes() {
    echo -e "\n${W}>> DISPOSITIVOS CONECTADOS <<${NC}"
    echo -e "${B}┌──────────────────┬───────────────────┬─────────────────┐${NC}"
    echo -e "${B}│${C} DIRECCIÓN IP     ${B}│${C} DIRECCIÓN MAC     ${B}│${C} NOMBRE/HOST     ${B}│${NC}"
    echo -e "${B}├──────────────────┼───────────────────┼─────────────────┤${NC}"
    
    if [ -f "/var/lib/misc/dnsmasq.leases" ]; then
        while read -r line; do
            ip=$(echo $line | awk '{print $3}')
            mac=$(echo $line | awk '{print $2}')
            name=$(echo $line | awk '{print $4}')
            print_row "$ip" "$mac" "$name"
        done < /var/lib/misc/dnsmasq.leases
    else
         echo -e "${B}│${Y}      (Vacío)     ${B}│${NC}         -         ${B}│${NC}        -        ${B}│${NC}"
    fi
    echo -e "${B}└──────────────────┴───────────────────┴─────────────────┘${NC}"
    
    # Mostrar bloqueados si hay
    local blocked=$(iptables -L FORWARD -v -n | grep "MAC" | wc -l)
    if [ "$blocked" -gt 0 ]; then
        echo -e "\n${R}⚠ HAY $blocked DISPOSITIVO(S) BLOQUEADO(S)${NC}"
    fi
}

limitar_velocidad() {
    echo -e "\n${Y}[ LIMITADOR DE ANCHO DE BANDA ]${NC}"
    read -p " IP del Objetivo : " ip
    read -p " Velocidad (ej: 500kbit) : " vel
    
    if [[ -z "$ip" || -z "$vel" ]]; then return; fi

    tc qdisc del dev "$WIFI_IF" root >/dev/null 2>&1
    tc qdisc add dev "$WIFI_IF" root handle 1: htb default 10
    tc class add dev "$WIFI_IF" parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev "$WIFI_IF" parent 1:1 classid 1:10 htb rate 1000mbit
    tc class add dev "$WIFI_IF" parent 1:1 classid 1:11 htb rate "$vel"
    tc filter add dev "$WIFI_IF" protocol ip parent 1:0 prio 1 u32 match ip dst "$ip" flowid 1:11
    
    echo -e "${G}✓ Regla aplicada con éxito.${NC}"
    sleep 2
}

bloquear_mac() {
    echo -e "\n${R}[ BLACKLIST / BLOQUEO ]${NC}"
    read -p " MAC Address (XX:XX:XX...): " mac
    if [ -z "$mac" ]; then return; fi
    
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
    hostapd_cli -i "$WIFI_IF" deauthenticate "$mac" >/dev/null 2>&1
    echo -e "${G}✓ Dispositivo expulsado y bloqueado.${NC}"
    sleep 2
}

desbloquear_mac() {
    echo -e "\n${G}[ DESBLOQUEO ]${NC}"
    iptables -L FORWARD -v -n | grep "MAC"
    echo ""
    read -p " MAC a desbloquear: " mac
    if [ -z "$mac" ]; then return; fi
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    echo -e "${G}✓ Acceso restaurado.${NC}"
    sleep 2
}

# --- Loop Principal ---
while true; do
    header
    listar_clientes
    echo ""
    echo -e "${B}╔══════════════════════════════════════╗${NC}"
    echo -e "${B}║${NC} 1. ${C}Actualizar Lista${NC}                 ${B}║${NC}"
    echo -e "${B}║${NC} 2. ${Y}Limitar Velocidad${NC} (Shape)        ${B}║${NC}"
    echo -e "${B}║${NC} 3. ${R}Bloquear MAC${NC} (Kick/Ban)         ${B}║${NC}"
    echo -e "${B}║${NC} 4. ${G}Desbloquear MAC${NC}                 ${B}║${NC}"
    echo -e "${B}║${NC} 5. ${W}Salir${NC}                           ${B}║${NC}"
    echo -e "${B}╚══════════════════════════════════════╝${NC}"
    echo ""
    read -p " Selecciona Opción > " op
    
    case $op in
        1) ;;
        2) limitar_velocidad ;;
        3) bloquear_mac ;;
        4) desbloquear_mac ;;
        5) clear; exit 0 ;;
        *) ;;
    esac
done